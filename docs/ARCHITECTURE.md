# Diagnostic et architecture

## Diagnostic initial — 3 octobre 2026

Le dossier initial était un portfolio React 19, React Router, Tailwind et CRACO. Aucun modèle Swift, projet Xcode ou test iOS n'y a été trouvé. Les fichiers existants ont été conservés. CameraLog a été créé dans un dépôt indépendant, sans reprendre le site.

## Cible retenue

```text
App (composition du ModelContainer)
  → Features (vues SwiftUI et brouillons locaux)
  → Domain (SheetDraft, SmartFill, ClipSequence, statuts, validation)
  → Data (CameraLogRepository, entités SwiftData)
  → fichier local SwiftData
```

Les vues lisent les entités observables SwiftData ; toutes les écritures passent par le repository main actor. Les brouillons restent des valeurs non persistées jusqu'à validation. Il n'y a pas de singleton, de DTO doublant chaque entité ou de backend. Le moteur SmartFill ne dépend ni de SwiftUI ni de SwiftData. Une interface abstraite de repository sera justifiée lorsqu'un second stockage sera nécessaire.

### Graphe

`Production → ShootDay → CameraReport → Roll → ShotSheet → TakeEntry`, et `Roll → TakeEntry`.

Une production possède aussi son parc `Camera`. Un rapport associe une caméra de ce parc à une journée. La caméra peut ainsi être réutilisée le lendemain sans confondre matériel et rapport. Les inverses SwiftData maintiennent les relations ; les propriétaires suppriment leurs enfants en cascade.

- `ShotSheet` (la fiche) : scène, plan, réglages courants (texte JSON par champ, une clé absente signifie « inconnu »), commentaire. Unique par roll pour une scène/plan donnée.
- `Roll` : créé automatiquement à partir de la case Roll d'une fiche, retrouvé par nom (sans casse) dans le rapport caméra/journée.
- `TakeEntry` : appartient à sa fiche et à son roll (toujours le même roll que la fiche). Elle porte son numéro de prise, son libellé libre (PU, FC…), ses statuts (dont Circle), un instantané JSON des réglages pris à sa création et `cardOrder`, l'ordre de l'entrée sur la carte.
- Le numéro de clip Cxxx n'est pas stocké : c'est le rang de l'entrée dans `Roll.clipSequence` (tri par `cardOrder`, puis date de création, puis identifiant). Les opérations qui changent ce rang (insertion tardive, suppression, changement de roll) ont une fonction de prévisualisation testée qui produit la liste « ancien → nouveau » affichée avant confirmation.

Le moteur SmartFill (`SmartFill`, `SheetDraft`) ne dépend ni de SwiftUI ni de SwiftData. Un `SheetDraft` distingue les valeurs saisies ou acceptées (`values`, seules enregistrées) des suggestions (`suggestions`, jamais enregistrées). Le comportement du toucher sur une prise passe par `CameraLogRepository.tap(_:mode:)` : `.edit` ouvre l'édition, `.circle` bascule Circle.

### Minimum iOS

iOS 17 apporte SwiftData et l'intégration Observation dans SwiftUI : il constitue le minimum fonctionnel de la pile choisie. Aucune fonctionnalité de Phase 1 ne nécessite de relever ce seuil. La compatibilité doit néanmoins être testée sur le plus ancien runtime disponible et la version courante avant distribution.

Références Apple consultées :

- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [Observation et SwiftUI](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [Build an app with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10154/)

### Persistance et fiabilité

Un seul container et un seul contexte d'écriture. Autosave désactivé ; commit à chaque action utilisateur et rollback sur erreur. L'échec d'ouverture du stockage affiche un écran d'erreur, sans effacer les fichiers ni basculer vers un stockage volatil.

### Versions du schéma

- `SchemaV1` (`Data/SchemaV1.swift`) est la copie figée du modèle livré jusqu'au run 7 (commit 241fd6e). Il ne doit plus être modifié : SwiftData reconnaît une base existante en comparant ces définitions. `CaptureSettings` fait partie de ce schéma et reste donc figé lui aussi.
- `SchemaV2` ajoute `ShotSheet`, la relation `Roll.sheets`, et sur `TakeEntry` les champs facultatifs `label`, `cardOrder`, `snapshotData` et `sheet`. Ces ajouts sont compatibles avec une migration légère, déclarée dans `CameraLogMigrationPlan`.
- Après ouverture, `migrateLegacyTakes()` rattache les prises sans fiche et leur attribue un ordre de carte selon leur date de création. Elle ne modifie ni identifiants, ni réglages historiques, ni statuts, ni noms de clips saisis. Elle est idempotente.
- Le champ `settings` (`CaptureSettings`) des prises reste celui des anciennes prises ; les nouvelles prises utilisent `snapshotData`. `TakeEntry.snapshot` lit l'un ou l'autre.
- `SchemaV2` (`Data/SchemaV2.swift`) est la copie figée du modèle de la build 15 (commit 20df5d9). `SchemaV3`, le modèle courant, ajoute sur `Production` les champs facultatifs `lensKitData` (série d'objectifs) et `filterKitData` (kit de filtres). Un kit de filtres absent signifie « kit standard » ; un kit vidé reste vide.

Trois tests couvrent la migration : l'un recrée une base avec `SchemaV1` ; les deux autres ouvrent des bases écrites en CI par le code réellement livré, celui de l'IPA du run 7 (commit 241fd6e, `ci/legacy/LegacyFixtureWriter.swift`) et celui de la build 15 (commit 20df5d9, `ci/legacy/Build15FixtureWriter.swift`). Toute évolution future doit figer le schéma courant dans un `SchemaVn`, ajouter une étape au plan de migration, ajouter un écrivain de base pour la dernière build livrée et conserver ces tests.

### Rafraîchissement des écrans

Les tableaux de relations remplis par un inverse SwiftData (les caméras d'une journée, par exemple) ne déclenchent pas toujours la mise à jour des vues. Le repository est `@Observable` et incrémente `revision` à chaque commit ; les écrans qui affichent des listes lisent cette valeur et se recalculent après chaque écriture.

Ne pas transformer automatiquement les UUID uniques ou activer CloudKit : cela exige une conception de synchronisation dédiée.

## Roadmap et critères de sortie

1. **Foundation et fiches — compilées et testées sur simulateur (voir VALIDATION).** Exécuter les scénarios manuels sur iPhone, vérifier l'installation par-dessus la version précédente, l'interface et la persistance après fermeture. Compléter l'édition des productions, journées et caméras avant usage de production.
2. **Plateau.** Catalogue d'objectifs et filtres, commandes numériques spécialisées, presets caméra, réglages de champs visibles et annulation maîtrisée. Mesurer le temps de saisie à une main sur appareils réels ; viser 2–3 secondes pour une prise déjà configurée.
3. **Report.** Exports PDF paginés, CSV échappé, JSON versionné et TXT, partage natif. Tests de contenu, encodage et pagination. Ajouter une restauration depuis une sauvegarde JSON validée.
4. **Professional.** Timecode typé et drop-frame, durée, métadonnées optiques avec unités/provenance, templates et données VFX. Adaptateurs hardware uniquement pour protocoles réellement documentés et matériel disponible.
5. **Sync.** Journal local durable, tombstones, transactions, versions par enregistrement, conflits explicites et reprise réseau. Puis seulement choix d'un service, comptes et collaboration.

Pas de cloud, d'export ou d'intégration hardware simulés.
