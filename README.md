# Subler Automation

Application native macOS 14+ (SwiftUI / AppKit), sans sandbox, avec présentation exclusive barre des menus ou Dock + fenêtre. Projet indépendant : aucun fichier de Molec ou de Quota Monitor n’est modifié.

## Installation locale

1. Compiler : `./build.sh` depuis le dossier du projet (Xcode ou ses outils Swift nécessaires).
2. Ouvrir `dist/Subler Automation.app`. Une icône pellicule apparaît dans la barre des menus ; l’absence de fenêtre principale est normale.
3. Au démarrage, préparer les autorisations avant tout traitement : contrôle de Subler, lecture du dossier source, écriture des temporaires et notifications facultatives. Subler est ouvert en arrière-plan si nécessaire, sans importer de film ni modifier sa file.
4. Réglages > Autorisations affiche les accès prêts ou bloqués et propose Préparer / Réessayer. Les configurations déjà préparées sont revérifiées sans demande interactive ; un refus bloque le démarrage, sans répéter de popup dans la surveillance. Les ajouts manuels et tâches récupérées utilisent aussi leurs propres dossiers et partages. Si un nouveau dossier nécessite une préparation, la file attend cette action avant conversion. Pour l’automatisation refusée : Réglages Système > Confidentialité et sécurité > Automatisation.
5. Lorsqu’un film est prêt à transférer, l’application tente une reconnexion au partage Movies avec les identifiants du Trousseau. En cas d’échec, une fenêtre native macOS peut demander l’utilisateur et le mot de passe. L’application ne reçoit et ne stocke aucun mot de passe.
6. Pour le lancement automatique, placer de préférence l’application dans /Applications, puis activer l’option dans ses réglages. Ne pas déplacer l’application après l’enregistrement du service.

La signature est ad hoc pour utilisation sur ce Mac, sans notarisation ni Developer ID. La recompilation peut conduire macOS à redemander des autorisations. Le projet n’utilise pas l’accessibilité pour piloter Subler.

Subler 1.9.5 est la version réellement testée. AVFoundation contrôle les MP4 ; ffprobe contrôle les pistes et la durée des MKV. ffprobe est déjà disponible sur ce Mac dans /opt/homebrew/bin. Sur un autre Mac sans ffprobe : `brew install ffmpeg` (seul ffprobe est appelé en production, jamais FFmpeg pour convertir).

## Utilisation

Déposer des MKV dans `~/Movies/Subler Automation/À convertir/`, ou utiliser Ajouter des films. Les fichiers ajoutés manuellement restent à leur emplacement d’origine. Surveillance non récursive, fichiers MKV seulement.

Avant traitement : au moins 10 secondes de taille et date inchangées après détection, et aucun descripteur ouvert en écriture détecté par lsof. Toute modification redémarre ce délai. Une copie peut théoriquement rester en pause plus longtemps que ce délai sans garder de descripteur ouvert : pour une garantie transactionnelle, copier avec une extension .part puis renommer en .mkv après la fin de copie. Le MKV est également vérifié et une modification pendant la conversion interdit le transfert.

Les films sont traités un par un. Les préférences de Subler, notamment fournisseur, langue et réglages audio/vidéo, ne sont pas modifiées. La sélection automatique exige une correspondance unique du titre normalisé et de l’année. Les titres alternatifs entre parenthèses ou crochets sont reconnus et les suffixes techniques connus placés avant l’année sont ignorés. Par exemple, un nom contenant le titre français et le titre original anglais peut être reconnu automatiquement. Un titre traduit sans titre alternatif, une année absente ou plusieurs correspondances nécessitent encore une confirmation : les choix titre/année sont directement visibles dans le panneau. Aucun premier résultat arbitraire n’est appliqué.

Réglages > Général > Présentation permet de choisir la barre des menus uniquement (par défaut, sans Dock) ou une application normale avec fenêtre et icône dans le Dock (sans icône dans la barre des menus). Les modes sont exclusifs et le changement conserve la file et les réglages. Une coche verte apparaît en haut à gauche de l’icône de barre des menus lorsque toutes les tâches sont terminées, sans travail en cours ni erreur.

Dans À vérifier, la corbeille retire uniquement la tâche après confirmation : tous les fichiers et la file Subler sont conservés. Un MKV retiré et inchangé n’est plus ajouté par la surveillance, même après redémarrage. Ajouter des films permet de le réinsérer explicitement. Les petits panneaux prennent leur hauteur naturelle ; seules les listes trop longues défilent. Le temps restant est affiché en secondes, minutes/secondes (`1m35s`) ou heures/minutes/secondes.

Une ancienne demande de métadonnées restée en attente est récupérée comme intervention, pas relancée automatiquement. La suppression reste possible si le fichier source a disparu. Réessayer explique alors le chemin manquant : remettre le MKV à cet emplacement permet une reprise ; sinon retirer la tâche. Aucun fichier absent n’est recréé par cette suppression.

La conversion reste locale dans `~/Movies/Subler Automation/Temp/<identifiant>/`. La barre des menus affiche une animation indéterminée pendant la conversion ; aucun pourcentage de conversion inventé. Le transfert affiche les octets effectivement écrits, la vitesse et l’estimation de durée restante. À 100 % des octets écrits, la vérification d’intégrité peut encore prendre du temps : le fichier n’est pas encore publié.

La pause arrête les nouveaux travaux après le film en cours ; elle ne stoppe jamais globalement la file de Subler. Un transfert peut être suspendu ; les copies originales et locales sont conservées. Quitter pendant une conversion ne tue pas Subler : au relancement, son élément de file est vérifié et ne sera jamais considéré terminé du seul fait qu’un MP4 existe.

## Serveur et intégrité

Par défaut : `smb://192.168.1.100/Movies`, utilisateur `adminMat`, chemin attendu `/Volumes/Movies`.

L’origine réelle smbfs est vérifiée, pas seulement le nom du dossier. Aucun dossier de remplacement n’est créé sous /Volumes. Les remontages essaient d’abord le Trousseau sans interface. Si cette tentative échoue pour un film validé en attente de transfert, macOS peut afficher sa fenêtre de connexion utilisateur/mot de passe. Aucune demande n’est lancée lorsque la file est inactive ou sans film prêt. Après un échec ou une annulation, les nouvelles tentatives automatiques restent silencieuses pour ce serveur/utilisateur pendant la session ; le bouton Connecter… permet de demander une nouvelle authentification. Une impossibilité de connexion laisse le MP4 local intact. Le montage et son origine sont relus avant tout transfert.

Classement : `Titre (Année)/Titre (Année).mp4`. Accents Unicode conservés, séparateurs et caractères problématiques nettoyés. Les appels POSIX emploient la normalisation Unicode NFD du montage macOS ; le titre affiché reste inchangé.

Sur votre serveur, le renommage exclusif de fichiers et les liens durs ne sont pas pris en charge. La copie par blocs utilise donc un dossier privé `.subler-<tâche>-<UUID>.staging` contenant le fichier `.part`. Le SHA-256 source est calculé pendant la copie et doit correspondre au digest de validation. Après synchronisation, le MP4 est renommé à l’intérieur du dossier privé, puis relu une seule fois par blocs de 8 Mio pour comparer son SHA-256 complet. La progression affiche les octets réellement vérifiés, la vitesse et le temps restant. Le même descripteur reste ouvert jusqu’à la publication atomique du dossier entier ; les identités, taille et dates sont contrôlées sans relecture intégrale redondante. Le renommage d’un dossier ne peut pas écraser un dossier concurrent non vide contenant un film. Un dossier cible préexistant, même vide, est signalé comme conflit avant publication ; dans l’ultime course système, seul un dossier vide pourrait être remplacé, jamais un film.

Les copies incomplètes ne sont pas publiées dans le dossier final du film. Après une coupure, le MP4 local est conservé et le transfert est relancé depuis zéro dans un nouveau staging privé, sans réencoder. Les staging abandonnés sont conservés par sécurité et peuvent être nettoyés manuellement ; aucun nettoyage récursif de fichiers inconnus n’est réalisé.

Un doublon doit être traité explicitement dans l’interface : Ignorer ou Remplacer avec confirmation. Aucun remplacement automatique. Sur SMB, un remplacement préserve le dossier existant entier (y compris ses sous-titres et autres fichiers) sous `.subler-<UUID>.backup` ; son chemin est enregistré dans la tâche et le journal. En cas d’échec de publication, une restauration est tentée sans écraser de film concurrent. Une destination contenant déjà exactement les mêmes octets est reconnue sans réécriture.

Les MKV originaux ne sont jamais supprimés. Le nettoyage des MP4 locaux est désactivé par défaut et ne peut intervenir qu’après réussite, sauvegarde persistante de l’état terminé et nouvelle vérification de propriété et d’intégrité du fichier temporaire.

## Persistance et récupération

État, réglages, verrou d’instance et journal : `~/Library/Application Support/Subler Automation/`.

- `jobs.json` : file persistante ; écritures atomiques.
- `jobs.json` contient désormais une enveloppe versionnée avec `jobs` et `dismissedFingerprints` ; les anciennes files sous forme de tableau sont migrées sans perdre leurs tâches.
- `settings.json` : réglages sans secrets.
- `permission-grant.json` : configurations et chemins préparés, sans identifiants ; cet état ne remplace jamais les décisions d’autorisation de macOS.
- `automation.log` : étapes et erreurs, chemins de fichiers uniquement.
- `instance.lock` : évite deux moteurs concurrents.

Une file illisible n’est pas remplacée silencieusement. Conversions interrompues : reprise prudente à partir de l’élément Subler correspondant à notre chemin local, validation obligatoire avant tout transfert. Les erreurs restent visibles avec Réessayer.

Ne pas démarrer simultanément des opérations manuelles dans la file partagée de Subler. L’application refuse de lancer des éléments prêts/actifs appartenant à d’autres workflows et ne les supprime pas.

## Développement et tests

`swift test` : tests déterministes avec fichiers temporaires, sans films personnels.

`./build.sh` : compilation release, génération de l’icône, création et signature de l’app.

`python3 scripts/app-smoke.py` : test réel du bundle compilé, avec surveillance et persistance isolées en pause. Aucun appel à Subler ni au serveur pendant ce test.

`python3 scripts/ui-layout-smoke.py` : compile les vraies vues dans une application de test native distincte, puis vérifie la hauteur intrinsèque des petits panneaux, le défilement unique des longues listes et le premier plan des réglages. État et fichiers synthétiques sous `~/.hermes/cache/scratch`, sans traitement de films personnels.

`python3 scripts/ui-layout-smoke.py --layout-only` : mêmes contrôles de hauteur et suppression, en excluant explicitement le premier plan lorsque la session macOS est verrouillée. `python3 scripts/presentation-ui-smoke.py` teste les modes de présentation et la coche native ; ces contrôles de premier plan exigent une session déverrouillée.

`python3 scripts/presentation-entrypoint-smoke.py` : véritable point d’entrée SwiftUI dans un bundle scratch, insertion/retrait natif du menu et bascules des modes. `python3 scripts/permission-core-tests.py` et `python3 scripts/permission-tests.py` : politiques, persistance, refus et révocation avec opérations injectées, compilation des API natives et nettoyage de la sonde locale. Les fixtures ne sollicitent jamais les permissions réelles de l’utilisateur.

Si Stage Manager empêche même une fenêtre AppKit minimale de passer en état miniaturisé, `python3 scripts/presentation-entrypoint-smoke.py --skip-miniaturization` vérifie les démarrages, modes exclusifs, focus des réglages et réouverture après fermeture, en signalant explicitement le seul contrôle exclu. Le test complet conserve son assertion ; aucune préférence système ni API privée de contournement n’est utilisée par l’application.

Un partage déjà monté est préparé sans reconnexion. S’il apparaît après la préparation, le transfert attend la préparation explicite de son accès plutôt que déclencher une demande de volume réseau pendant la copie. Un partage absent ne peut pas être préautorisé : son authentification reste à la demande d’un film prêt. macOS peut révoquer un accès ou le redemander après recompilation/déplacement de l’app ; aucune application ne peut garantir une autorisation irrévocable.

Lors d’un remplacement, une différence de taille entre l’ancien fichier et le nouveau suffit à exclure l’égalité : leurs lectures SHA-256 préalables sont alors évitées. Le nouveau flux copié et la relecture distante intégrale restent vérifiés. Cette optimisation ne réduit pas le contrôle après un transfert neuf. `scripts/transfer-benchmark.py` mesure ce cas sur des fixtures locales ; les résultats APFS ne sont pas des vitesses SMB.

Les essais de conversion doivent uniquement employer un MKV synthétique créé pour les tests. FFmpeg n’est jamais utilisé comme moteur de conversion de production : la conversion est exclusivement réalisée par Subler. Voir `TEST-RESULTS.md` pour les commandes réellement exécutées, résultats et blocages.

Pour isoler les essais de l’app de la file réelle, lancer l’exécutable avec `SUBLER_AUTOMATION_TEST_ROOT=/chemin/vers/un/dossier/de/test` : persistance, source et temporaires seront redirigés. Ne pas activer le lancement automatique pour une instance de test.
