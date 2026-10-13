# Fichiers et architecture

- Sources/AutomationCore : services indépendants, modèles Codable, surveillance/stabilité, noms Unicode, preuve SHA-256 du MP4 généré, AppleScript, validation AVFoundation/ffprobe, montage NetFS, transfert.
- Sources/SublerAutomation/App : entrée SwiftUI MenuBarExtra et verrou d’instance.
- Sources/SublerAutomation/Models : réglages persistants sans secrets.
- Sources/SublerAutomation/Services : file séquentielle et notifications.
- Sources/SublerAutomation/Views : menu, progression réelle et réglages avec brouillon avant application.
- Sources/SublerAutomation/Resources : Info.plist avec LSUIElement et description Apple Events.
- Tests/AutomationCoreTests : tests XCTest, intégrations réelles opt-in et fixtures isolées.
- scripts/app-smoke.py : test de l’exécutable .app avec une file isolée et en pause.
- scripts/make-icon.swift : création native des rendus ICNS.
- build.sh : compilation release, bundle .app et signature locale.

Subler 1.9.5 annonce un identifiant de document dans son dictionnaire, mais son accès réel peut échouer : le service conserve donc un identifiant de fenêtre native et cible explicitement son document. Aucune référence au document courant de l’utilisateur n’est utilisée.

`fetch metadata` n’est volontairement pas utilisé : son implémentation sélectionne le premier résultat et applique les données de façon asynchrone. L’application utilise `fetch metadata candidates` et `fetch and set metadata candidate`, avec vérification des tags réellement écrits dans le MP4. Le fournisseur et la langue sont omis pour préserver les valeurs par défaut de Subler.

`send to queue` utilise les paramètres existants de Subler et ferme le document. `start queue and wait` existe mais ne suffit pas à prouver la réussite d’un film : le service lance la file uniquement lorsqu’aucun élément tiers n’est prêt ou actif, puis suit l’identifiant exact de son élément et exige son état completed. La validation du conteneur et des métadonnées reste obligatoire.

La validation emploie AVFoundation pour le MP4 et ffprobe pour les MKV non pris en charge par AVFoundation. ffprobe est déjà installé sur ce Mac ; sur une autre machine, installer ffprobe si nécessaire. Aucun transcodage FFmpeg/HandBrake n’est exécuté par l’application.

Les réglages de dossier temporaire, serveur et nettoyage sont figés par tâche au lancement de sa conversion. Le réglage de notifications reste global. Une sortie validée est identifiée par SHA-256, vérifiée à nouveau avant transfert, puis comparée au flux réellement copié avant publication. Une modification du MKV entre une conversion interrompue et sa reprise interdit de réutiliser l’ancien MP4.
