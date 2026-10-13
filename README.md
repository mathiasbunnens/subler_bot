# Subler Automation

Application native macOS 14+ (SwiftUI / MenuBarExtra), sans fenêtre principale et sans sandbox. Projet indépendant : aucun fichier de Molec ou de Quota Monitor n’est modifié.

## Installation locale

1. Compiler : `./build.sh` depuis le dossier du projet (Xcode ou ses outils Swift nécessaires).
2. Ouvrir `dist/Subler Automation.app`. Une icône pellicule apparaît dans la barre des menus ; l’absence de fenêtre principale est normale.
3. Dans Réglages, vérifier les dossiers et autoriser les notifications si souhaité.
4. Au premier traitement, autoriser le contrôle de Subler par les Apple Events. En cas de refus : Réglages Système > Confidentialité et sécurité > Automatisation. Les accès aux dossiers et aux volumes réseau peuvent aussi être demandés par macOS.
5. Monter le partage Movies au moins une fois via Finder avec adminMat et enregistrer ses identifiants dans le Trousseau. L’application ne reçoit et ne stocke aucun mot de passe.
6. Pour le lancement automatique, placer de préférence l’application dans /Applications, puis activer l’option dans ses réglages. Ne pas déplacer l’application après l’enregistrement du service.

La signature est ad hoc pour utilisation sur ce Mac, sans notarisation ni Developer ID. La recompilation peut conduire macOS à redemander des autorisations. Le projet n’utilise pas l’accessibilité pour piloter Subler.

Subler 1.9.5 est la version réellement testée. AVFoundation contrôle les MP4 ; ffprobe contrôle les pistes et la durée des MKV. ffprobe est déjà disponible sur ce Mac dans /opt/homebrew/bin. Sur un autre Mac sans ffprobe : `brew install ffmpeg` (seul ffprobe est appelé en production, jamais FFmpeg pour convertir).

## Utilisation

Déposer des MKV dans `~/Movies/Subler Automation/À convertir/`, ou utiliser Ajouter des films. Les fichiers ajoutés manuellement restent à leur emplacement d’origine. Surveillance non récursive, fichiers MKV seulement.

Avant traitement : au moins 60 secondes de taille et date inchangées, et aucun descripteur ouvert en écriture détecté par lsof. Une copie peut théoriquement rester en pause plus longtemps que ce délai sans garder de descripteur ouvert : pour une garantie transactionnelle, copier avec une extension .part puis renommer en .mkv après la fin de copie. Le MKV est également vérifié et une modification pendant la conversion interdit le transfert.

Les films sont traités un par un. Les préférences de Subler, notamment fournisseur, langue et réglages audio/vidéo, ne sont pas modifiées. La sélection automatique est volontairement stricte : correspondance unique du titre normalisé et de l’année. Un titre traduit ou ambigu peut demander une sélection dans le menu. Aucun premier résultat arbitraire n’est appliqué.

La conversion reste locale dans `~/Movies/Subler Automation/Temp/<identifiant>/`. La barre des menus affiche une animation indéterminée pendant la conversion ; aucun pourcentage de conversion inventé. Le transfert affiche les octets effectivement écrits, la vitesse et l’estimation de durée restante. À 100 % des octets écrits, la vérification d’intégrité peut encore prendre du temps : le fichier n’est pas encore publié.

La pause arrête les nouveaux travaux après le film en cours ; elle ne stoppe jamais globalement la file de Subler. Un transfert peut être suspendu ; les copies originales et locales sont conservées. Quitter pendant une conversion ne tue pas Subler : au relancement, son élément de file est vérifié et ne sera jamais considéré terminé du seul fait qu’un MP4 existe.

## Serveur et intégrité

Par défaut : `smb://192.168.1.100/Movies`, utilisateur `adminMat`, chemin attendu `/Volumes/Movies`.

L’origine réelle smbfs est vérifiée, pas seulement le nom du dossier. Aucun dossier de remplacement n’est créé sous /Volumes. Les remontages utilisent le Trousseau et ne demandent pas de nouveau mot de passe ; une impossibilité d’authentification met la tâche en attente.

Classement : `Titre (Année)/Titre (Année).mp4`. Accents Unicode conservés, séparateurs et caractères problématiques nettoyés. Les appels POSIX emploient la normalisation Unicode NFD du montage macOS ; le titre affiché reste inchangé.

Sur votre serveur, le renommage exclusif de fichiers et les liens durs ne sont pas pris en charge. La copie par blocs utilise donc un dossier privé `.subler-<tâche>-<UUID>.staging` contenant le fichier `.part`. Le SHA-256 source est calculé pendant la copie et doit correspondre au digest de validation. Après synchronisation, le MP4 est renommé à l’intérieur du dossier privé, puis relu une seule fois par blocs de 8 Mio pour comparer son SHA-256 complet. La progression affiche les octets réellement vérifiés, la vitesse et le temps restant. Le même descripteur reste ouvert jusqu’à la publication atomique du dossier entier ; les identités, taille et dates sont contrôlées sans relecture intégrale redondante. Le renommage d’un dossier ne peut pas écraser un dossier concurrent non vide contenant un film. Un dossier cible préexistant, même vide, est signalé comme conflit avant publication ; dans l’ultime course système, seul un dossier vide pourrait être remplacé, jamais un film.

Les copies incomplètes ne sont pas publiées dans le dossier final du film. Après une coupure, le MP4 local est conservé et le transfert est relancé depuis zéro dans un nouveau staging privé, sans réencoder. Les staging abandonnés sont conservés par sécurité et peuvent être nettoyés manuellement ; aucun nettoyage récursif de fichiers inconnus n’est réalisé.

Un doublon doit être traité explicitement dans l’interface : Ignorer ou Remplacer avec confirmation. Aucun remplacement automatique. Sur SMB, un remplacement préserve le dossier existant entier (y compris ses sous-titres et autres fichiers) sous `.subler-<UUID>.backup` ; son chemin est enregistré dans la tâche et le journal. En cas d’échec de publication, une restauration est tentée sans écraser de film concurrent. Une destination contenant déjà exactement les mêmes octets est reconnue sans réécriture.

Les MKV originaux ne sont jamais supprimés. Le nettoyage des MP4 locaux est désactivé par défaut et ne peut intervenir qu’après réussite, sauvegarde persistante de l’état terminé et nouvelle vérification de propriété et d’intégrité du fichier temporaire.

## Persistance et récupération

État, réglages, verrou d’instance et journal : `~/Library/Application Support/Subler Automation/`.

- `jobs.json` : file persistante ; écritures atomiques.
- `settings.json` : réglages sans secrets.
- `automation.log` : étapes et erreurs, chemins de fichiers uniquement.
- `instance.lock` : évite deux moteurs concurrents.

Une file illisible n’est pas remplacée silencieusement. Conversions interrompues : reprise prudente à partir de l’élément Subler correspondant à notre chemin local, validation obligatoire avant tout transfert. Les erreurs restent visibles avec Réessayer.

Ne pas démarrer simultanément des opérations manuelles dans la file partagée de Subler. L’application refuse de lancer des éléments prêts/actifs appartenant à d’autres workflows et ne les supprime pas.

## Développement et tests

`swift test` : tests déterministes avec fichiers temporaires, sans films personnels.

`./build.sh` : compilation release, génération de l’icône, création et signature de l’app.

`python3 scripts/app-smoke.py` : test réel du bundle compilé, avec surveillance et persistance isolées en pause. Aucun appel à Subler ni au serveur pendant ce test.

Les essais de conversion doivent uniquement employer un MKV synthétique créé pour les tests. FFmpeg n’est jamais utilisé comme moteur de conversion de production : la conversion est exclusivement réalisée par Subler. Voir `TEST-RESULTS.md` pour les commandes réellement exécutées, résultats et blocages.

Pour isoler les essais de l’app de la file réelle, lancer l’exécutable avec `SUBLER_AUTOMATION_TEST_ROOT=/chemin/vers/un/dossier/de/test` : persistance, source et temporaires seront redirigés. Ne pas activer le lancement automatique pour une instance de test.
