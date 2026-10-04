# Diagnostic et architecture

## Diagnostic initial — 3 octobre 2026

Le dossier initial était un portfolio React 19, React Router, Tailwind et CRACO. Aucun modèle Swift, projet Xcode ou test iOS n'y a été trouvé. Les fichiers existants ont été conservés. CameraLog a été créé dans un dépôt indépendant, sans reprendre le site.

## Cible retenue

```text
App (composition du ModelContainer)
  → Features (vues SwiftUI et brouillons locaux)
  → Domain (CaptureSettings, TakeDraft, statuts, SmartFill)
  → Data (CameraLogRepository, entités SwiftData)
  → fichier local SwiftData
```

Les vues lisent les entités observables SwiftData ; toutes les écritures passent par le repository main actor. Les brouillons restent des valeurs non persistées jusqu'à validation. Il n'y a pas de singleton, de DTO doublant chaque entité ou de backend. Le moteur SmartFill ne dépend ni de SwiftUI ni de SwiftData. Une interface abstraite de repository sera justifiée lorsqu'un second stockage sera nécessaire.

### Graphe

`Production → ShootDay → CameraReport → Roll → TakeEntry`.

Une production possède aussi son parc `Camera`. Un rapport associe une caméra de ce parc à une journée. La caméra peut ainsi être réutilisée le lendemain sans confondre matériel et rapport. Les inverses SwiftData maintiennent les relations ; les propriétaires suppriment leurs enfants en cascade. Les tests vérifient ce graphe et les suppressions.

`CaptureSettings` est une valeur Codable stockée avec chaque prise. Les statuts sont stockés sous forme de chaînes, pour préserver les valeurs inconnues dans une évolution future. Circle est un statut parmi plusieurs, compatible avec VFX ou MOS.

### Minimum iOS

iOS 17 apporte SwiftData et l'intégration Observation dans SwiftUI : il constitue le minimum fonctionnel de la pile choisie. Aucune fonctionnalité de Phase 1 ne nécessite de relever ce seuil. La compatibilité doit néanmoins être testée sur le plus ancien runtime disponible et la version courante avant distribution.

Références Apple consultées :

- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [Observation et SwiftUI](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [Build an app with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10154/)

### Persistance et fiabilité

Un seul container et un seul contexte d'écriture pour cette première version. Autosave désactivé ; commit à chaque action utilisateur et rollback sur erreur. L'échec d'ouverture du stockage affiche un écran d'erreur, sans effacer les fichiers ni basculer vers un stockage volatil.

Le schéma est initial, sans migration historique. Avant toute évolution du modèle sur données déjà distribuées, introduire un VersionedSchema et un plan de migration testés sur une copie de base réelle. Ne pas transformer automatiquement les UUID uniques ou activer CloudKit : cela exige une conception de synchronisation dédiée.

## Roadmap et critères de sortie

1. **Foundation — compilée, neuf tests XCTest réussis sur Mac distant.** Exécuter les scénarios manuels sur iPhone, vérifier l'installation, l'interface et la persistance après fermeture. L'édition des prises et la liste compacte sont disponibles ; compléter l'édition des autres fiches avant usage de production.
2. **Plateau.** Catalogue d'objectifs et filtres, commandes numériques spécialisées, presets caméra, réglages de champs visibles et annulation maîtrisée. Mesurer le temps de saisie à une main sur appareils réels ; viser 2–3 secondes pour une prise déjà configurée.
3. **Report.** Exports PDF paginés, CSV échappé, JSON versionné et TXT, partage natif. Tests de contenu, encodage et pagination. Ajouter une restauration depuis une sauvegarde JSON validée.
4. **Professional.** Timecode typé et drop-frame, durée, métadonnées optiques avec unités/provenance, templates et données VFX. Adaptateurs hardware uniquement pour protocoles réellement documentés et matériel disponible.
5. **Sync.** Journal local durable, tombstones, transactions, versions par enregistrement, conflits explicites et reprise réseau. Puis seulement choix d'un service, comptes et collaboration.

Pas de cloud, d'export ou d'intégration hardware simulés.
