# Résultats des tests

## Environnement

Inspection réelle : macOS 26.6.2, Xcode 27.0, Swift 6.4, arm64. Subler installé : 1.9.5, org.galad.Subler. Dictionnaire lu directement dans /Applications/Subler.app/Contents/Resources/Subler.sdef et handlers comparés au code source de Subler.

## Résultat final

48 tests XCTest exécutés, 0 échec, 0 test ignoré lors de l’exécution avec toutes les intégrations activées. Compilation release réussie sans avertissement. Bundle dist/Subler Automation.app signé ad hoc, codesign --verify --deep --strict réussi. Icône ICNS générée ; image 512@2x vérifiée à 1024 × 1024 pixels.

Répartition : FolderWatcherTests (1), NamingTests (2), OutputSafetyTests (2), PersistenceTests (5), SublerServiceTests (14), TransferTests (24).

Journal complet de cette exécution : /Users/mathiasbunnens/.hermes/cache/scratch/final-all-enabled.log.

## Parcours complet réel

Le moteur réel JobQueueService et tous ses services ont été compilés dans un lanceur de test isolé (scripts/pipeline-smoke.swift), sans substituer Subler ou SMB par des réponses simulées.

Résultat : PIPELINE_PASS.

1. Détection de Amelie.2001.mkv synthétique par la surveillance.
2. Attente réelle de stabilité de 60 secondes.
3. Importation native Subler et embellissement audio.
4. Recherche des candidats avec fournisseur/langue par défaut de Subler.
5. Sélection automatique unique Amélie (2001).
6. Conversion dans la file native Subler ; état exact completed exigé.
7. Vérification du conteneur, durée, pistes vidéo/audio, titre et année réellement écrits.
8. Calcul et persistance SHA-256 du MP4 généré.
9. Montage SMB vérifié : //adminMat@192.168.1.100/Movies, /Volumes/Movies, smbfs.
10. Copie avec progression réelle, relecture SHA-256, publication atomique du dossier Amélie (2001) contenant Amélie (2001).mp4.
11. Vérification indépendante des octets distants et de l’état completed dans jobs.json.
12. Empreinte du MKV original inchangée ; MP4 local conservé.
13. Nettoyage du seul fichier synthétique et du dossier serveur créés par le test, après vérification de leur propriété et de leur empreinte.

File de preuve isolée : /Users/mathiasbunnens/.hermes/cache/scratch/subler-full-pipeline-E661AEDF-0D18-4286-B321-7A6AAA549669/jobs.json. Son chemin distant n’existe plus, car le test a volontairement nettoyé sa propre sortie synthétique.

## Contrôles Subler indépendants

- Version AppleScript retournée : 1.9.5 ; file initialement vide.
- MKV synthétique : une piste vidéo H.264, une piste AAC, environ une seconde ; aucun film personnel.
- MP4 réel : 933 052 octets, durée 1,005 s, titre Amélie, date 2001-04-25, une vidéo lisible et une piste audio. L’image de couverture est distincte d’une piste vidéo jouable.
- Atome trak/udta/name : Mono Audio. L’embellissement audio est effectivement écrit.
- Décodage FFmpeg indépendant de vérification : terminé sans erreur. FFmpeg ne réalise aucune conversion de production.
- Un MP4 de 1,005 s pour un MKV de 3,021 s est correctement refusé, même avec des métadonnées valides.
- Erreurs AppleScript, guillemets/Unicode, délais et annulation du worker : tests réussis.

Les éléments completed des conversions synthétiques restent dans la file de Subler. Aucun nettoyage global de la file n’est lancé, pour ne jamais risquer de supprimer des éléments utilisateur.

## Contrôles SMB réels et correctifs

- Reconnexion NetFS sans interface d’authentification, avec identifiants du Trousseau existant : réussie, origine relue.
- Copie réelle de 2 500 000 octets : SHA-256 égal, quatre échantillons de progression réelle ; fixture UUID nettoyée.
- Remplacement explicitement autorisé d’une fixture : ancien film et sous-titre préservés dans une sauvegarde du dossier entier ; fixtures nettoyées.
- Nom accentué NFC Amélie : publication et relecture réussies après normalisation NFD pour les appels POSIX.

Deux incompatibilités ont été découvertes et corrigées par les tests du vrai serveur :

1. renameatx_np(RENAME_EXCL) et les liens durs sont refusés avec ENOTSUP (45). La publication SMB utilise désormais un dossier staging privé puis un renommage atomique de dossier. Un film contenu dans une destination non vide ne peut pas être écrasé.
2. Les inodes synthétiques smbfs changent lors des renommages et diffèrent si les appels mélangent les noms NFC/NFD. Les descripteurs restent ouverts, l’identité est revalidée, les données sont rehashées après renommage, et tous les noms POSIX sont NFD. Les accents affichés restent conservés.

Tests locaux complémentaires : doublons, destinations vides/concurrentes, symlinks, traversée de chemins, remplacement avec rollback, backup conservée si rollback impossible, mutation après checksum, source identique au part, intégrité attendue, annulation et reprise sans toucher aux autres fichiers.

## Bundle et persistance

scripts/app-smoke.py a été réexécuté contre le vrai bundle release : surveillance MKV, file persistante, déduplication, verrou d’instance, relancement et récupération d’un état converting, préservation de l’original : APP_SMOKE_PASS.

Preuve isolée finale, après la dernière recompilation du bundle livré : /Users/mathiasbunnens/.hermes/cache/scratch/subler-app-smoke-ukjwu6zw.

L’application normale a été lancée via LaunchServices. Son identifiant, son exécutable et sa politique accessory ont été relus. Les journaux AppKit confirment la création d’une NSStatusItemScene et de ses vues NSStatusItemView. Aucune fenêtre principale permanente n’est créée. Le dossier source par défaut est prêt et la file utilisateur initiale est vide.

Molec et Quota Monitor : git status inchangé et propre après les travaux.

## Limites et permissions non validées automatiquement

- Les interactions visuelles dans le menu/réglages et l’affichage des notifications ne sont pas testés graphiquement : computer_use n’a pas pu démarrer, System Events refuse l’accès d’aide (-25211), et la capture d’écran est refusée. Cela n’affecte pas l’automatisation AppleScript de Subler, qui ne demande pas l’accessibilité.
- Le premier contrôle de Subler depuis le nouveau bundle peut demander votre autorisation macOS Automation. Les essais du moteur et des services ont été exécutés depuis le terminal ; aucune boîte de permission n’a été acceptée automatiquement.
- Notifications et lancement à l’ouverture de session sont implémentés, mais leur autorisation/activation et le redémarrage réel du Mac n’ont pas été forcés pendant les tests.
- Coupure réseau et changement de montage : tests par injection de perte de vérification et remplacement de racine. Votre serveur n’a pas été volontairement déconnecté ou démonté.
- La validation de production contrôle conteneur, durée, pistes vidéo/audio et métadonnées ; elle ne décode pas exhaustivement chaque image de tous les films et ne valide pas toutes les pistes de sous-titres. Le décodage intégral concerne la fixture synthétique seulement.
- Stabilité de copie : 60 s sans changement et absence de descripteur ouvert en écriture. Pour garantir la fin d’une copie qui pourrait rester longtemps en pause, employer .part puis renommer en .mkv après copie.
- Reprise SMB : relance depuis zéro, pas reprise à l’octet. Les staging abandonnés sont conservés par sécurité.
- Application arm64 locale, signature ad hoc, sans Developer ID ni notarisation. ffprobe est nécessaire pour inspecter les MKV et est déjà installé sur ce Mac.

Tous les fichiers de test créés sur le NAS pendant les essais ont été vérifiés et nettoyés. Aucun film personnel ni préférence existante de Subler n’a été modifié.

## Optimisation de la vérification SHA-256

Nouvelle exécution `SUBLER_TEST_SMB=1 swift test` : 50 cas, 5 intégrations Subler ignorées car non activées dans cette exécution, 0 échec. Les 26 tests de transfert ont tous réussi, dont les trois essais réels SMB (copie, accents, remplacement avec sauvegarde du dossier entier).

Deux régressions ajoutées : une seule passe SHA-256 distante avec compteur de lecture monotone jusqu’à la taille complète ; corruption du fichier distant pendant cette passe refusée sans publication.

Le SHA-256 source est calculé pendant la copie. Le fichier distant est relu une seule fois par blocs de 8 Mio après son renommage privé. Le même descripteur et le snapshot vérifié sont conservés jusqu’à la publication ; taille, dates et identités contrôlées remplacent les relectures complètes redondantes. Les premiers essais ont montré que smbfs modifie les timestamps à la fermeture/réouverture : garder le descripteur ouvert résout ce problème sans supprimer les protections.

Build release et vérification codesign réussis. APP_SMOKE_PASS sur le nouveau bundle : surveillance, déduplication, persistance, verrou, récupération après relancement et préservation du fichier source. Preuve : `/Users/mathiasbunnens/.hermes/cache/scratch/subler-app-smoke-73394bmw`. Journaux : `fast-integrity-final.log` et `fast-integrity-build.log` dans le même dossier scratch.

Le bundle utilisateur a été remplacé et relancé seulement après confirmation que le transfert réel avait terminé et que la tâche restante était en pause. L’ancien bundle est conservé sous `dist/.previous-35e96443-84b2-4977-9e97-d7c19a4f8db5`.

Le gain de durée sur un film complet n’a pas encore été mesuré avec cette version. Le volume de relecture distante passe de quatre passes complètes à une ; le débit reste dépendant du NAS et du réseau. L’affichage graphique de la nouvelle progression n’a pas été validé par capture d’écran.
