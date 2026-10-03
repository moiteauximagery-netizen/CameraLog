# Validation de la fondation

## Ce qui peut être vérifié sous Windows

Le script `scripts/check_project.py` vérifie les références du projet Xcode, les cibles, l'appartenance des sources aux phases de compilation et le schéma partagé. Il ne compile aucun Swift et n'exécute pas SwiftData.

## Tests XCTest fournis — à exécuter sur Mac

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

Pas de déclaration « compilable », « tests réussis », « prêt plateau » ou « Phase 1 validée » tant que les résultats Xcode et la recette sur appareil ne sont pas obtenus. Conserver le fichier `.xcresult` de la première exécution.
