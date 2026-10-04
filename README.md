# CameraLog

Application native iPhone de rapport caméra, locale et indépendante du réseau.

## Tester depuis Windows, sans Mac personnel

Le projet inclut une compilation GitHub Actions sur runner macOS standard pour dépôt public. Elle exécute les tests et produit un IPA non signé, à signer et installer sur l'iPhone avec Sideloadly et un compte Apple gratuit. Aucun secret Apple n'est nécessaire pour compiler. Voir [le guide Windows → iPhone](docs/INSTALL_IPHONE_WINDOWS.md).

## État réel

La fondation de Phase 1 est écrite : projet Xcode, stockage SwiftData, parcours production → journée → caméra → roll → prise, formulaires de création, exemple LES OMBRES et tests XCTest. SmartFill initial et Circle sont anticipés pour vérifier le modèle de prise.

**Compilation et huit tests XCTest validés sur Mac distant** via GitHub Actions le 3 octobre 2026 (Xcode 16.4, simulateur iOS 26.2). La compilation Release ARM64 et la préparation de l'IPA pour appareil physique réussissent également. Le [run GitHub Actions n° 3](https://github.com/moiteauximagery-netizen/CameraLog/actions/runs/37148475543) contient le fichier à télécharger. Une copie se trouve sur le PC dans `build/iphone/CameraLog.ipa`. L'installation, la présentation et la saisie sur un véritable iPhone restent à vérifier ; ces tests ne constituent pas une validation plateau.

## Ouvrir sur Mac

1. Copier ce dossier sur un Mac équipé d'une version stable de Xcode supportant iOS 17 et les macros Swift (Xcode 15 minimum ; utiliser un Xcode récent compatible avec le Mac et les appareils visés).
2. Ouvrir `CameraLog.xcodeproj` et sélectionner le schéma **CameraLog**.
3. Sélectionner un simulateur iPhone installé et lancer **Product → Run**.
4. Lancer **Product → Test** pour exécuter les huit tests de fondation.
5. Pour un iPhone physique, sélectionner sa propre équipe dans **Signing & Capabilities**, puis adapter le bundle identifier si nécessaire. Aucune équipe ni clé n'est intégrée au projet.

Commandes de validation sur Mac :

```sh
xcodebuild -list -project CameraLog.xcodeproj
xcodebuild -showdestinations -scheme CameraLog -project CameraLog.xcodeproj
# Remplacer SIMULATOR_UUID par un identifiant retourné ci-dessus.
xcodebuild test -project CameraLog.xcodeproj -scheme CameraLog \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -resultBundlePath CameraLogTests.xcresult
```

Le projet Xcode est fourni, sans dépendance à XcodeGen, CocoaPods ou un package tiers. Après ajout/retrait de sources : `python3 scripts/generate_project.py` régénère sa configuration et le schéma partagé. Les réglages ajoutés manuellement au projet seront remplacés lors de cette régénération ; modifier le générateur pour conserver des réglages permanents.

## Parcours disponible

- Créer une production avec client, réalisation, direction photo, dates, numéro et notes.
- Créer une journée avec date, lieu et unité.
- Créer une caméra libre ou réutiliser une caméra de la production sur une autre journée.
- Créer et sélectionner un roll, avec card et reel distincts.
- Ajouter une prise : scène et plan alphanumériques, compteur de prise, objectif, filtres combinés, T-stop, commentaire, statuts et réglages caméra dépliables.
- Réutiliser les réglages de la dernière prise de la même caméra/journée. Une nouvelle scène ou un nouveau plan remet le compteur à 1 dans le formulaire.
- Activer/désactiver Circle en un geste dans le rapport, sans effacer les autres statuts.
- Supprimer une prise ou une production avec confirmation ; supprimer une production supprime sa hiérarchie.
- Charger volontairement LES OMBRES depuis l'écran vide. Les données d'exemple ne sont jamais injectées automatiquement.

## Décisions et limites

- SwiftUI + SwiftData, iOS 17 minimum, mode de langage Swift 5. Les API utilisées sont natives ; aucune connexion ni synchronisation cloud.
- Interface sombre, commandes de 44–52 points, typographie système adaptable, libellés VoiceOver pour Circle. Accessibilité et mise en page restent à vérifier avec les tailles de texte maximales sur appareil.
- Les prises contiennent un instantané des réglages. Modifier des valeurs par défaut ne doit pas réécrire l'historique.
- La sauvegarde est explicite ; un formulaire ne se ferme qu'après réussite. En cas d'échec le repository annule les modifications non enregistrées et l'interface affiche une erreur.
- Le choix du roll est explicite ; SmartFill ne change pas silencieusement le support. Le numéro de prise continue après changement de roll et reste modifiable.
- La numérotation est contrôlée par roll ; un même triplet scène/plan/prise peut exister sur deux rolls. Les rapports sont isolés par caméra et journée.
- Les identifiants UUID sont locaux et stables. Dates/révisions des prises préparent une évolution, mais il n'existe pas encore de journal de synchronisation, de tombstones ou de résolution de conflits.
- Les créations caméra et rapport sont deux sauvegardes distinctes. Si la seconde échoue, la caméra créée reste disponible dans « Caméras de la production » pour réessayer.
- Édition des fiches existantes, catalogue d'objectifs, presets, recherche, paramètres visibles configurables, saisie timecode, exports et partage restent à implémenter. Aucun bouton inactif ne les présente comme disponibles.
- Les champs de métadonnées optiques et timecode existent dans le modèle ; aucune acquisition hardware ni calcul de durée n'est annoncé.
- Aucune performance de saisie de 2–3 secondes n'a encore été mesurée. Elle devra être vérifiée sur iPhone avec un assistant caméra.

Voir [les décisions d'architecture et la roadmap](docs/ARCHITECTURE.md) et [le protocole de validation](docs/VALIDATION.md).
