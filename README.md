# Subler Automation

**Vos MKV → des MP4 identifiés et vérifiés → votre serveur SMB.**

Une application native pour macOS qui pilote [Subler](https://subler.org/) et traite vos films un par un. Utilisez-la dans la barre des menus ou dans une fenêtre avec une icône dans le Dock.

## Aperçu
 
| en pause  | en cours  |
| :---: | :---: |
| <img width="300" alt="Capture d’écran 2026-10-14 à 16 56 04" src="https://github.com/user-attachments/assets/20acd57a-0754-4084-8f0b-6a441a4c1db7" /> | <img width="300" alt="Capture d’écran 2026-10-14 à 18 23 20" src="https://github.com/user-attachments/assets/22d1b3e5-1d8e-4676-a02d-d26456b8a9f2" /> |

*Captures des vraies vues de l’application, avec des données de démonstration et une affiche fictive. Aucun film personnel n’est utilisé.*

## Ce que fait l’application

- Surveille un dossier de MKV, ou accepte des films ajoutés manuellement.
- Utilise Subler pour les métadonnées et la conversion en MP4, en conservant ses préférences.
- Demande votre confirmation si le titre ou l’année sont ambigus.
- Vérifie le MP4, puis le copie sur le serveur avec suivi du transfert et contrôle d’intégrité.
- Classe les films sous `Titre (Année)/Titre (Année).mp4`.
- Conserve la file après redémarrage et permet de réessayer les tâches en erreur.

## Installation

Prérequis : **macOS 14+**, les outils Swift/Xcode, **Subler** (version testée : 1.9.5) et **ffprobe** (`brew install ffmpeg`). La conversion est réalisée par Subler, pas par FFmpeg.

Depuis le dossier du projet :

```sh
./build.sh
open "dist/Subler Automation.app"
```

Le bundle est signé ad hoc, sans notarisation. macOS peut demander les autorisations à nouveau après une recompilation.

### Version de l’application

La source unique est `Sources/SublerAutomation/Resources/Info.plist` :
`CFBundleShortVersionString` pour la version publique (incrémenter le patch pour
un correctif, par exemple 1.0.1 → 1.0.2), `CFBundleVersion` pour le build
(entier strictement croissant à chaque nouvelle livraison, actuellement 2).
Modifier ces deux valeurs avant la livraison, puis relancer `./build.sh` ; aucun
incrément automatique au lancement ni à chaque compilation. Le script copie ce
plist tel quel dans le bundle signé, sans réutiliser un ancien binaire de `dist`.

Le pied du popover et des Réglages affiche la version lue dans `Bundle.main`,
en petit texte centré comme Quota Monitor ; l’infobulle donne aussi le build.
Sans bundle (`swift run` / tests), le texte indique explicitement « développement
(hors bundle) », sans prétendre identifier l’application installée.
Vérifier la cohérence avec `SUBLER_BUILD_APP="/chemin/vers/Subler Automation.app" python3 scripts/version-contract.py`
après compilation (plist, binaire release identique et signature ad hoc).

## Démarrer en 3 étapes

1. Dans **Réglages → Autorisations**, préparez le contrôle de Subler et l’accès aux dossiers.
2. Dans **Dossiers** et **Serveur**, choisissez la source, le cache temporaire et votre partage SMB. Le stockage local est conseillé, mais les emplacements réseau montés sont autorisés.
3. Déposez vos MKV dans `~/.../À convertir/`, ou cliquez sur **Ajouter…**, ou clique droit sur un MKV **Envoyer au serveur avec Subler Automation**, puis **Démarrer**.

Sans serveur configuré, les MP4 validés restent dans le dossier temporaire en attendant le transfert. Pour une copie longue, utilisez une extension `.part`, puis renommez en `.mkv` lorsque la copie est terminée.

## Compteur « Terminés »

Le compteur conserve les films terminés depuis la dernière remise à zéro manuelle, entre les lots et après redémarrage. Cliquez sur ↺ en haut à droite du compteur pour le remettre à zéro : l’historique des tâches reste intact. Les installations existantes commencent à zéro, sans recompter les anciens films.

## Vos fichiers restent protégés

- Les MKV originaux ne sont jamais supprimés.
- Aucun doublon n’est remplacé sans confirmation ; un remplacement conserve une sauvegarde.
- Le nettoyage des MP4 temporaires est désactivé par défaut.
- L’authentification SMB est gérée par macOS ; l’application ne stocke aucun mot de passe.
- Évitez les opérations manuelles simultanées dans la file partagée de Subler.

## Pour aller plus loin

[Guide technique et dépannage](docs/guide-technique.md)

Développement : `swift test`. Captures de démonstration isolées : `python3 scripts/render-ui.py`.
