# CameraLog

Application native iPhone de rapport caméra, locale et indépendante du réseau.

## Tester depuis Windows, sans Mac personnel

Le projet inclut une compilation GitHub Actions sur runner macOS standard pour dépôt public. Elle exécute les tests et produit un IPA non signé, à signer et installer sur l'iPhone avec Sideloadly et un compte Apple gratuit. Aucun secret Apple n'est nécessaire pour compiler. Voir [le guide Windows → iPhone](docs/INSTALL_IPHONE_WINDOWS.md).

## État réel

Le rapport caméra fonctionne par **fiches** : une fiche par scène/plan et par roll, sur laquelle on saisit l'identification, les réglages, les prises et le cerclage, sans écran séparé par plan. La liste du rapport regroupe automatiquement les fiches par roll.

[Run GitHub Actions de référence du 4 octobre 2026](https://github.com/moiteauximagery-netizen/CameraLog/actions/runs/37199328155) : 18 tests sur 18 réussis (16 unitaires, 2 d'interface) sur simulateur iPhone SE, iOS 26.2, compilation Release ARM64 et `CameraLog.ipa` (artefact **CameraLog-iPhone-unsigned**, conservé sept jours). Détail dans [le protocole de validation](docs/VALIDATION.md). Les tests tournent sur simulateur ; **aucune de ces fonctions n'a encore été éprouvée sur un véritable iPhone ni en conditions de tournage.**

## Ouvrir sur Mac

1. Copier ce dossier sur un Mac équipé d'une version stable de Xcode supportant iOS 17 et les macros Swift (Xcode 15 minimum ; utiliser un Xcode récent compatible avec le Mac et les appareils visés).
2. Ouvrir `CameraLog.xcodeproj` et sélectionner le schéma **CameraLog**.
3. Sélectionner un simulateur iPhone installé et lancer **Product → Run**.
4. Lancer **Product → Test** pour exécuter les tests unitaires et les tests d'interface.
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

- Créer une production, une journée et une caméra ; reprendre le rapport le plus récent depuis l'accueil.
- Dans le rapport (une caméra, une journée), toucher **Nouvelle fiche**. La fiche contient :
  - l'identification : scène, plan, **roll** (par exemple A010) ;
  - les réglages : objectif, diaph, filtres, ISO, température, FPS, shutter ;
  - la section **Takes**, son bouton **+** et le bouton **Cerclage** ;
  - un commentaire.
- La liste du rapport regroupe les fiches par roll, avec le nombre de clips de chaque carte. Toucher une fiche l'ouvre pour y travailler directement. Balayer une fiche permet de la supprimer, après affichage des clips renumérotés.
- Recherche par scène/plan (« 14A »), roll ou objectif.
- Charger volontairement LES OMBRES depuis l'écran vide. Les données d'exemple ne sont jamais injectées automatiquement.

### SmartFill : suggérer sans imposer

À l'ouverture d'une fiche, les valeurs de la fiche la plus récente de la même caméra et de la même journée apparaissent **en gris et en italique, dans une case entourée de pointillés**. La case reste réellement vide : une suggestion n'est jamais enregistrée tant qu'elle n'est pas acceptée.

- **Reprendre**, sous une case, accepte sa suggestion : la valeur passe en blanc et les pointillés disparaissent.
- Taper directement dans la case remplace la suggestion, sans rien effacer.
- Laisser la case vide enregistre « inconnu ».
- **Tout reprendre** accepte toutes les suggestions encore en attente, sans jamais remplacer une valeur déjà tapée.
- Un bandeau indique combien de valeurs sont seulement proposées ; l'en-tête indique « Rien d'enregistré », « Modifications non enregistrées » ou « Fiche enregistrée ».

Le plan n'est jamais suggéré. Le roll et la scène peuvent l'être.

### Roll/card automatique

La case **Roll** se remplit comme les autres. À l'enregistrement, la fiche est rattachée au roll de ce nom pour cette caméra et cette journée (sans tenir compte des majuscules), ou le roll est créé. Il n'y a plus de bouton « Nouveau roll ». Corriger A010 en A011 sur une fiche déplace la fiche et ses prises ; la liste des numéros de clips modifiés s'affiche avant confirmation. Les prises déplacées se placent à la fin de la nouvelle carte, dans leur ordre. Une même scène/plan peut exister sur deux rolls (changement de carte pendant le plan), mais pas deux fois sur le même roll.

### Takes, libellés et cerclage

- **+** crée la prise suivante de la fiche (T01, T02…) en un geste. Si la fiche n'est pas encore enregistrée, ou si elle a été modifiée, + l'enregistre d'abord.
- Chaque prise conserve un **instantané des réglages** de la fiche au moment de sa création. Modifier ensuite la fiche ne réécrit pas les prises existantes ; l'édition d'une prise affiche son instantané.
- En mode normal, toucher une prise ouvre une édition courte : libellé libre ou boutons **PU** / **FC**, statuts (MOS, VFX…), commentaire, suppression. Le libellé ne change ni le numéro de prise, ni le clip, ni Circle : « T03 · PU ».
- **FC** (faux clip) désigne un clip réellement créé sur la caméra mais inexploitable : c'est une entrée de la séquence, qui occupe donc un numéro de clip. Il n'a aucun lien avec Circle.
- Le bouton **Cerclage** active un mode où toucher une prise la cercle ou la décercle immédiatement. Le mode actif est signalé par le bouton orange plein, un bandeau orange « CERCLAGE ACTIF » et un cadre orange épais autour des prises. Toucher à nouveau Cerclage rend au toucher son rôle d'édition. Les prises cerclées sont orange, avec une coche.
- VoiceOver : le bouton est annoncé « Mode cerclage, activé/désactivé » ; chaque prise « Prise 3, clip C005, libellé PU, cerclée/non cerclée », avec une consigne qui dépend du mode. Les changements de mode et les ajouts de prise sont annoncés.

### Numéros de clips : règle retenue

Le numéro **Cxxx est calculé, jamais saisi** : c'est la position de l'entrée dans la séquence de sa carte (roll), tous plans confondus, en commençant à C001. Chaque roll a sa propre séquence.

Exemple sur A010 : 14A T01 → C001, 14A T02 → C002, 14B T01 → C003, 14B T02 · FC → C004, clip suivant → C005. Un nouveau roll A011 recommence à C001.

L'ordre de la carte est enregistré pour chaque prise (`cardOrder`) ; le numéro affiché en découle. Aucune case ne permet de modifier C016. Le nombre de clips et le dernier numéro de la carte s'affichent dans la section Takes et dans l'en-tête de chaque roll de la liste. Si la caméra compte plus de clips que CameraLog, une prise a pu être oubliée ou un faux clip créé : l'application ne peut pas savoir lequel sans connexion à la caméra et n'invente pas de diagnostic.

Les actions qui modifient des numéros déjà affichés montrent **avant confirmation** la liste « ancien → nouveau » :

- **Insérer une prise oubliée…** (section Takes) : choisir le numéro de prise et la position sur la carte (« Avant C004 · 14 / B · T02 »). La prise prend le numéro de cette position ; les clips suivants avancent d'un cran.
- Supprimer une prise ou une fiche : les clips suivants reculent d'un cran. Si le clip existe sur la caméra, mieux vaut le libeller FC.
- Changer le roll d'une fiche qui a des prises.

Aucune autre action ne renumérote l'historique.

## Données existantes et mise à jour

La version précédente stockait une entrée `TakeEntry` par prise, rattachée à un roll, avec un nom de clip libre. À la première ouverture de cette version :

1. SwiftData migre la base du schéma 1 au schéma 2 par une migration légère déclarée : ajout de l'entité fiche et de champs facultatifs uniquement. Aucune ligne n'est supprimée ; les identifiants UUID sont conservés.
2. L'application regroupe les anciennes prises en fiches par roll, scène et plan. Les réglages de la fiche sont ceux de la dernière prise du groupe ; chaque ancienne prise garde ses propres réglages historiques.
3. L'ordre de carte des anciennes prises suit leur date de création ; les Cxxx affichés en découlent. **L'ancien nom de clip saisi n'est ni effacé ni converti** : il reste visible dans l'édition de la prise, rubrique « Saisi avant la mise à jour », pour comparaison avec la carte.
4. Cette étape est idempotente. Si elle échoue, rien n'est enregistré et un écran d'erreur s'affiche, sans effacer de fichier.

Les anciennes prises n'avaient pas de libellé : il reste vide. Une base mise à jour ne peut plus être ouverte par l'ancienne version de l'app. Pour conserver les données, installer le nouvel IPA par-dessus l'ancien avec le même compte Apple dans Sideloadly, sans désinstaller l'app.

## Décisions et limites

- SwiftUI + SwiftData, iOS 17 minimum, mode de langage Swift 5. Les API utilisées sont natives ; aucune connexion ni synchronisation cloud.
- Interface sombre, commandes principales de 44–52 points, typographie système adaptable, libellés VoiceOver pour le cerclage et les prises. Les boutons « Reprendre » mesurent environ 30 points de haut pour garder la fiche compacte. Accessibilité et mise en page restent à vérifier sur appareil, notamment avec les tailles de texte maximales.
- La sauvegarde est explicite : bouton en bas de fiche, ou + qui enregistre la fiche avant d'ajouter la prise. Tant qu'une fiche est modifiée, le retour est remplacé par « Annuler ». En cas d'échec le repository annule les modifications non enregistrées et l'interface affiche une erreur.
- Les réglages des fiches sont du texte : objectif, diaph et filtres sont libres ; ISO et température sont des entiers positifs (« 5600K » devient 5600), FPS un nombre positif (« 23,976 » accepté), shutter un angle de 0 à 360°.
- Le numéro de prise suit le maximum de la fiche + 1, y compris après une entrée FC (T02 · FC puis T03). Il n'est choisi librement que lors d'une insertion tardive.
- Les identifiants UUID sont locaux et stables. Dates/révisions préparent une évolution, mais il n'existe pas encore de journal de synchronisation, de tombstones ou de résolution de conflits.
- Les rolls sans fiche (restés vides depuis la version précédente, ou vidés par un déplacement) ne sont plus affichés ; ils ne sont pas supprimés.
- Catalogue d'objectifs, presets, paramètres visibles configurables, clavier caméra spécialisé, saisie timecode, exports et partage restent à implémenter. Les champs TC, codec et LUT de la version précédente sont conservés en base mais ne sont plus affichés.
- Aucune performance de saisie n'a encore été mesurée sur iPhone avec un assistant caméra.

Voir [les décisions d'architecture et la roadmap](docs/ARCHITECTURE.md) et [le protocole de validation](docs/VALIDATION.md).
