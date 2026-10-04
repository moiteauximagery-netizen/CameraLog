# Validation

## Ce qui peut être vérifié sous Windows

Le script `scripts/check_project.py` vérifie les références du projet Xcode, les trois cibles (app, tests unitaires, tests d'interface), l'appartenance des sources aux phases de compilation et le schéma partagé. Il ne compile aucun Swift et n'exécute pas SwiftData.

## Ce que vérifie GitHub Actions

Chaque run du workflow `iOS - Tests et IPA pour iPhone` :

1. Écrit une base de données avec le **code réellement livré** avant les fiches (commit 241fd6e, celui de l'IPA du run 7), via `ci/legacy/LegacyFixtureWriter.swift` : deux rolls, quatre prises, un nom de clip saisi, Circle, VFX, une scène/plan sur deux rolls.
2. Exécute les tests unitaires et les tests d'interface de la version courante sur un simulateur iPhone, en leur donnant cette base.
3. Compile l'app en Release ARM64 pour iPhone et prépare `CameraLog.ipa`, non signé.
4. Publie la liste des tests exécutés dans une annotation « Tests exécutés » du run, et les captures d'écran des tests d'interface dans l'artefact **CameraLog-diagnostics** (dossier `screenshots`).

Le run de référence est indiqué dans le README. Les tests ont tourné sur **iPhone SE (3e génération), iOS 26.2** (le plus petit écran disponible sur le runner). Aucun runtime iOS 17 n'est installé sur ce runner : la compatibilité iOS 17 repose sur la cible de déploiement et les API utilisées, pas sur une exécution.

## Tests unitaires (16)

| Test | Vérifie |
| --- | --- |
| `testSuggestionIsDisplayedButNeverSaved` | Suggestions de 14A visibles sur 14B, cases vides, rien d'enregistré, prise sans réglage inventé, suggestion toujours grise à la réouverture |
| `testAcceptingASuggestionAndTypingAnotherValue` | Reprendre, taper 85 mm à la place de 50 mm, case laissée vide, Tout reprendre sans écraser une valeur tapée |
| `testRollIsCreatedAutomaticallyAndSheetCanMove` | Création automatique du roll, réutilisation, doublon refusé, A010 → A011 avec prévisualisation, prises déplacées sans perte (identifiant, PU, Circle, note), même plan sur deux rolls |
| `testTakesIncrementWithinASheet` | T01, T02, T03 ; une autre fiche recommence à T01 |
| `testClipSequenceAcrossSheetsAndRestartOnNewRoll` | Exemple exact : 14A T1 C001, T2 C002, 14B T1 C003, FC C004, suivant C005 ; A011 recommence à C001 |
| `testFalseClipKeepsItsPlaceAndIsIndependentFromCircle` | FC occupe son clip, libellé et Circle indépendants, numéro de prise inchangé |
| `testLateInsertionShowsAndAppliesRenumbering` | Prévisualisation exacte des clips décalés, rien ne change avant confirmation, numéro de prise en double refusé, résultat conforme à la prévisualisation |
| `testTapEditsInNormalModeAndCirclesInCircleMode` | Toucher : édition en mode normal, bascule de Circle en mode cerclage, retour à l'édition, libellé et statuts conservés |
| `testTakeSnapshotsAreNotRewrittenBySheetEdits` | Modifier la fiche ne réécrit pas les réglages des prises existantes |
| `testValidationDoesNotInsertInvalidRecords` | Champs obligatoires et numériques invalides : aucun roll ni fiche créés ; normalisation 5600K, 23,976, 172.8° |
| `testDeletionPreviewAndCascade` | Prévisualisation de la renumérotation à la suppression, cascade de la production |
| `testDiskPersistenceAcrossContainers` | Fiche, libellé, Circle et instantané relus après réouverture du fichier |
| `testOpeningAStoreCreatedByThePreviousVersion` | Base créée avec la copie figée `SchemaV1` : migration, identifiants, anciens noms de clips conservés, ordre de carte par date, idempotence |
| `testOpeningAStoreWrittenByTheShippedVersion` | Base écrite par le commit 241fd6e : même contrôle sur une vraie base, puis nouvelle prise et réouverture en schéma 2 |
| `testHierarchyAndCreation`, `testSampleData` | Graphe complet et données LES OMBRES |

## Tests d'interface (2)

Ils pilotent la vraie interface sur le simulateur, avec LES OMBRES en mémoire.

- `testTapEditsInNormalModeAndCirclesInCircleMode` : ouvre le rapport puis la fiche 24/03 ; un toucher en mode normal ouvre l'édition T01, où FC est appliqué ; en mode Cerclage, deux touchers cerclent puis décerclent T01 sans ouvrir l'édition, et le libellé FC reste ; hors cerclage, le toucher rouvre l'édition ; + crée T04, annoncé comme clip C005 ; T04 est ensuite supprimée depuis son édition, après confirmation.
- `testNewSheetShowsSuggestionsWithoutFillingFields` : une nouvelle fiche affiche « Rien d'enregistré » et des suggestions ; Reprendre remplit l'objectif (35mm) ; Tout reprendre accepte le reste.

Ces tests utilisent les valeurs d'accessibilité (« cerclée », « activé »), donc vérifient aussi ce que VoiceOver annonce. Ils ne vérifient pas le rendu visuel : les captures sont à relire dans l'artefact.

## Non vérifié

- Installation par Sideloadly et mise à jour par-dessus l'IPA du run 7 sur un vrai iPhone, avec de vraies données.
- Usage plateau : rapidité, lisibilité en extérieur, saisie à une main.
- VoiceOver réel, tailles de texte maximales, paysage, iPad.
- Échec disque pendant une sauvegarde (le rollback n'est pas testé par injection d'erreur).
- Exécution sur un runtime iOS 17.

## Recette manuelle sur iPhone

- Avant mise à jour, noter quelques prises existantes (scène, plan, numéro, Circle, nom de clip). Installer par-dessus, ouvrir le rapport : retrouver chaque prise dans une fiche, avec son nom de clip saisi dans « Saisi avant la mise à jour ».
- Créer 14A sur A010 avec 50 mm, ISO 800, 5600, ND 0.6, deux prises. Nouvelle fiche : vérifier les gris, taper 85 mm, Reprendre l'ISO, laisser K vide, + : la fiche 14B ne contient que 85 mm et 800.
- Créer une entrée FC, vérifier C004 puis C005. Comparer le total avec le compteur de la caméra.
- Insérer une prise oubliée au milieu de la carte ; lire la liste des renumérotations avant de confirmer.
- Changer A010 en A011 sur une fiche avec prises ; vérifier le message puis le regroupement dans la liste.
- Activer Cerclage, cercler trois prises rapidement, quitter le mode, toucher une prise : l'édition s'ouvre.
- En mode avion, enregistrer dix prises consécutives avec + ; mesurer le délai.
- Avec VoiceOver, atteindre Cerclage, + et chaque prise ; à taille de texte maximale, vérifier la fiche, clavier affiché et masqué.
- Fermer l'app de force, relancer, vérifier fiches, libellés, Circle et compteurs.

## Critère de livraison

Compilation, tests unitaires et tests d'interface sur simulateur sont validés. Ne pas déclarer « prêt plateau » avant la recette manuelle sur iPhone. Les résultats `.xcresult` et les captures restent disponibles dans les artefacts de diagnostic pendant trois jours.
