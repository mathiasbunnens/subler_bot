# Préparation Apple TV — version 1.1.0

## Utilisation

Réglages → Apple TV → Choisir un fichier → consulter le diagnostic → choisir le mode → accepter le compromis → Préparer le MP4. Choisir une nouvelle destination sur un disque local ; copier ensuite le résultat vers le serveur si souhaité. Cet outil manuel n’ajoute rien à la file surveillée, ne recherche pas de métadonnées et ne pilote pas Subler. Il fonctionne aussi sur un MP4 déjà produit par le parcours automatique.

« Préserver la vidéo » est le défaut. Un refus n’entraîne jamais un encodage automatique. « Convertir pour Apple TV » est un vrai réencodage matériel FFmpeg/VideoToolbox, pas une simple modification d’extension ou d’étiquette de codec. Il nécessite un accord explicite, réinitialisé si le mode ou l’autorisation d’exclure des pistes change.

## Diagnostic du parcours existant

`SublerService.prepare/convert` importe un document dans Subler, choisit ses métadonnées, l’envoie à sa file et attend son état final. Il conserve les réglages natifs de Subler ; notre code n’y choisit pas d’encodeur vidéo. `MediaValidationService` contrôle conteneur, durée, nombre de pistes et titre/année, mais cela ne prouve pas que l’image est décodable. Le nouveau parcours ajoute donc sa propre analyse et une vérification d’image native.

La documentation officielle de Subler décrit du muxage et de l’édition de tags, pas une API d’encodeur vidéo extensible : https://subler.org/ . Le dictionnaire installé Subler 1.9.5 expose import/save/queue/métadonnées, sans commande d’installation de codec ou de sélection d’encodeur vidéo. Nous orchestrons FFmpeg dans notre application, sans modifier Subler tiers ; cela ne prétend pas prouver qu’aucune future modification du code amont serait possible.

Sans le fichier ayant présenté « audio seulement » dans QuickTime, sa cause reste inconnue : codec/profil vidéo, format des pixels, configuration Dolby Vision, marquage MP4 ou flux endommagé sont des pistes, pas un diagnostic établi. Le marquage `hvc1` ne transforme pas une vidéo incompatible en vidéo compatible. Le nouveau diagnostic donne codec/profil/pixels/dimensions/transfert/Dolby Vision par piste, puis une raison précise de refus ; une erreur d’exécution est volontairement expurgée des chemins et tags personnels.

## Profils conservateurs

Sources officielles consultées :

- Apple TV HD : https://support.apple.com/en-us/111928 — H.264 High/Main niveau ≤4.2, ≤1080p60 ; Baseline ≤3.0 ; AAC-LC stéréo ≤48 kHz.
- Apple TV 4K (3e génération) : https://support.apple.com/en-euro/111839 — AVC/HEVC Main/Main 10 ≤2160p60 ; Dolby Vision profil 5 et HDR10/HLG selon appareil/chaîne de lecture.

Notre sous-ensemble volontairement plus étroit :

| Mode | Vidéo | Cible / limites |
| --- | --- | --- |
| Préserver | H.264 8 bits 4:2:0 ; Main/High ≤4.2, Baseline ≤3.0 ; ≤1920×1080, ≤60 i/s | Copie sans réencodage, `avc1`, Apple TV HD/4K |
| Préserver | HEVC Main/Main 10, 4:2:0 8/10 bits, niveau ≤5.1 ; ≤3840×2160, ≤60 i/s | Copie sans réencodage, `hvc1`, cible annoncée Apple TV 4K |
| Convertir | Source SDR connue, ou source 8 bits non étiquetée interprétée SDR ; une seule vidéo | H.264 High 4.1 matériel, maximum 1080p30, débit cible 8 Mbit/s, AAC si nécessaire ; Apple TV HD/4K |

La conversion réduit résolution/cadence/profondeur si nécessaire, avec perte ; aucune garantie d’identité visuelle. Les sources anamorphiques ne sont pas converties afin de ne pas modifier silencieusement leurs proportions. Les sources 10 bits au transfert inconnu sont refusées en conversion.

Toutes les pistes audio sélectionnées sont copiées si elles sont AAC-LC stéréo ≤48 kHz ; sinon elles sont toutes réencodées en AAC-LC stéréo 256 kbit/s/48 kHz. Cela peut supprimer surround et Atmos : le résumé et l’accord l’indiquent. Sous-titres, données et pièces jointes sont refusés par défaut ; leur exclusion exige une autorisation séparée. Les chapitres et métadonnées de conteneur sont demandés en copie, sans garantie d’équivalence des tags propres à tous les conteneurs.

## HDR / Dolby Vision

Aucun tone mapping ni réencodage HDR/HLG/Dolby Vision : la préparation est bloquée plutôt que de fabriquer un SDR simplement réétiqueté. Dolby Vision est refusé, y compris le profil 5 pourtant documenté par Apple : préservation RPU/profil non validée ici. Pas de conversion avec perte HDR/DV proposée dans cette version.

Le planner accepte la copie HDR10 uniquement si HEVC Main 10/10 bits/PQ/BT.2020/BT.2020 non constant et présence de mastering metadata sont exposés par ffprobe au niveau du flux, puis revérifiés en sortie. Certains fichiers ne portent ces informations qu’au niveau des images : ils sont refusés. Ce contrôle vérifie la présence des caractéristiques, pas l’étalonnage ni toutes les valeurs de métadonnées dynamiques. HLG non validé est refusé. La préservation HDR10 sur une chaîne TV réelle n’a pas été certifiée ; ne pas confondre décodage d’images macOS et restitution HDR sur le téléviseur.

## Sûreté et limites opérationnelles

- Source jamais écrasée ; empreinte inode/taille/date avant analyse et avant publication. Liens symboliques directs et destinations existantes refusés.
- Cache exclusif aléatoire `.appletv-UUID` avec permissions 0700 dans le dossier de sortie ; nettoyage limité à son identité inode et au même parent. Aucun cache étranger n’est supprimé.
- Budget surveillé toutes les 50 ms : plus petite valeur entre 64 Gio, limite fournie et espace libre moins 512 Mio ; un dépassement de la dernière rafale d’écriture est possible. Pas de `-fs` qui pourrait produire un faux succès tronqué. Moins de 1 Gio libre au démarrage : refus.
- Les processus FFmpeg/ffprobe directs sont les seuls arrêtés lors d’une annulation ou d’un délai ; ni Subler ni sa file ne sont arrêtés. Quitter l’application attend l’annulation du worker.
- Analyse bornée à 60 s et 1 Mio JSON ; préparation bornée à 24 h ; vérification native bornée par une demande d’annulation à 30 s. La réponse effective du framework AVFoundation à cette demande dépend de macOS.
- Validation avant publication : une vidéo, même nombre de pistes audio, durée proche de la source, retour dans le profil conservateur, et trois images décodées par AVFoundation (début/milieu/fin). Ce n’est pas un décodage exhaustif de chaque image de chaque film.
- Publication atomique sans remplacement par lien dur sur disque local, même si une destination concurrente apparaît. Aucun résultat partiel n’est présenté comme réussi.
- Après arrêt brutal du processus ou coupure électrique, un cache peut subsister : ne pas le reprendre comme film terminé. Relancer une préparation complète, supprimer manuellement un cache ancien seulement après vérification qu’aucune tâche ne l’utilise. Aucun balayage destructif au lancement.
- Pas de validation sur Apple TV physique : dépend aussi du modèle, de tvOS, de l’application de lecture, du débit réseau et de la chaîne HDMI/TV.

## Dépendances et distribution

Installer séparément `brew install ffmpeg`. La découverte GUI cherche la paire exécutable `ffmpeg`/`ffprobe` dans `/opt/homebrew/bin`, puis `/usr/local/bin`, sans supposer le PATH du terminal. Un FFmpeg sans `h264_videotoolbox` ou un Mac sans encodeur matériel exploitable échoue sans publier ; aucun fallback logiciel silencieux. Les tests utilisent également libx264/libx265 pour créer leurs seules sources synthétiques.

FFmpeg n’est ni téléchargé automatiquement ni inclus dans le bundle. Sa licence dépend de sa compilation (Homebrew local testé : options GPL et version3) ; informations officielles : https://ffmpeg.org/legal.html . Toute future redistribution de binaires impose une revue de la configuration/licence et des obligations de distribution ; cette livraison ne les redistribue pas.

## Vérification reproductible, sans films personnels

- `swift test` : planner, profils HDR/DV refusés, non-écrasement, remux H.264/HEVC Main 10 avec SHA-256 des images décodées identiques, vrai MPEG-4/PCM → H.264 VideoToolbox/AAC, décodage AVFoundation et FFmpeg, annulation, budget/cleanup et redémarrage après échec.
- `python3 scripts/appletv-ui-contract.py` : câblage Réglages et arrêt propre ; contrat source, pas test d’interactions natives.
- `python3 scripts/appletv-smoke.py` : vraie vue SwiftUI hébergée en apparences claire/sombre et modèle réel ; analyse, blocage sans accord, conversion asynchrone, décodage et original inchangé. N’initialise pas la file automatique et n’envoie aucun Apple Event. Ce fixture n’automatise pas les panneaux natifs de choix de fichier et ne certifie pas visuellement tous les états.
- `./build.sh` puis `SUBLER_BUILD_APP="$PWD/dist/Subler Automation.app" python3 scripts/version-contract.py` : bundle release, version 1.1.0/build 4 et signature ad hoc. Pas de notarisation.
