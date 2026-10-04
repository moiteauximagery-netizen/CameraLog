# Validation de la fondation

## Ce qui peut être vérifié sous Windows

Le script `scripts/check_project.py` vérifie les références du projet Xcode, les cibles, l'appartenance des sources aux phases de compilation et le schéma partagé. Il ne compile aucun Swift et n'exécute pas SwiftData.

## Tests XCTest — huit réussites sur Mac distant

Le 3 octobre 2026, [l'exécution GitHub Actions n° 2](https://github.com/moiteauximagery-netizen/CameraLog/actions/runs/37148084250) a validé les huit tests avec zéro échec, sous Xcode 16.4 et simulateur iOS 26.2, puis la compilation Release pour iPhone. Cette exécution a ensuite échoué dans l'outil de préparation de l'IPA ; l'ordre des arguments de `lipo` a été corrigé séparément.

La [troisième exécution](https://github.com/moiteauximagery-netizen/CameraLog/actions/runs/37148475543) est entièrement réussie : huit tests, compilation pour iPhone ARM64 et création de `CameraLog.ipa`. Une copie locale de l'IPA non signé est dans `build/iphone/CameraLog.ipa` (SHA-256 `2156185CAAF1B4FE20BA9423823C118E53E719E67C7F67528412283EB5066E75`). L'installation et le lancement sur iPhone n'ont pas encore été vérifiés.

La première exécution avait révélé deux plantages à l'insertion : les tests libéraient le ModelContainer alors que le repository utilisait encore son contexte. Le repository conserve désormais le container pendant toute sa durée de vie ; les mêmes tests passent sans être désactivés ou affaiblis.

1. Création complète de la hiérarchie et relations uniques.
2. SmartFill : paramètres hérités, statuts/commentaires/média/timecode réinitialisés.
3. Changement de roll et isolation entre caméras.
4. Circle sans perte des autres statuts ; indépendance des réglages historiques.
5. Rejet des entrées invalides et doublons sans insertion supplémentaire.
6. Suppression d'une prise puis cascade d'une production.
7. Réouverture d'un stockage disque dans un nouveau container avec relations et paramètres conservés.
8. Cohérence des données d'exemple LES OMBRES.

Les tests d'export attendront l'implémentation des exports en Phase 3. Les scénarios de panne de disque/échec save doivent encore être couverts sur Apple ; le rollback n'a pas été testé avec injection d'erreur.

## Recette manuelle obligatoire

- Sur installation vierge, créer production, journée, caméra, roll et prise. Relancer l'application et vérifier chaque niveau.
- Charger LES OMBRES dans une installation vierge : DAY 12, CAM A, A004, quatre prises et un Circle.
- En mode avion, enregistrer dix prises consécutives. Mesurer le délai depuis + TAKE jusqu'à confirmation. Vérifier l'incrémentation et la reprise des réglages.
- Modifier scène/plan : numéro revenu à 1 ; les autres réglages restent présents. Tester une scène alphanumérique « 24A ».
- Changer de roll puis revenir au précédent ; vérifier le classement des prises et le roll choisi avant sauvegarde.
- Ajouter CAM B ; vérifier qu'aucun réglage de CAM A n'est repris.
- Activer Circle et VFX, quitter/revenir, retirer Circle : VFX demeure.
- Annuler un formulaire : aucune entrée ne doit être ajoutée.
- Tenter un doublon et des champs invalides : le formulaire reste ouvert avec une erreur lisible.
- Supprimer une prise puis une production, confirmer uniquement dans la boîte de dialogue et vérifier après relance.
- Avec VoiceOver, atteindre + TAKE, chaque champ et Circle. À taille de texte maximale, vérifier la lecture et l'accès au bouton d'enregistrement, clavier affiché et masqué.
- Vérifier petit iPhone, Pro Max, portrait et paysage. L'iPad utilise les vues adaptatives natives ; un layout professionnel spécifique est reporté.

## Critère de livraison

Compilation et tests unitaires sont validés. Ne pas déclarer « prêt plateau » ou « Phase 1 validée sur appareil » avant la recette manuelle sur iPhone. Les résultats `.xcresult` sont disponibles dans les artefacts de diagnostic GitHub Actions pendant leur durée de conservation.
