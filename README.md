# CameraLog

Application native iPhone de rapport caméra, locale et indépendante du réseau.

## Tester depuis Windows, sans Mac personnel

Le projet inclut une compilation GitHub Actions sur runner macOS standard pour dépôt public. Elle exécute les tests et produit un IPA non signé, à signer et installer sur l'iPhone avec Sideloadly et un compte Apple gratuit. Aucun secret Apple n'est nécessaire pour compiler. Voir [le guide Windows → iPhone](docs/INSTALL_IPHONE_WINDOWS.md).

## État réel

Le rapport caméra fonctionne par **fiches** : une fiche par scène/plan et par roll, sur laquelle on saisit l'identification, les réglages, les prises et le cerclage, sans écran séparé par plan. La liste du rapport regroupe automatiquement les fiches par roll.

[Run GitHub Actions de référence du 4 octobre 2026](https://github.com/moiteauximagery-netizen/CameraLog/actions/runs/37216539824) (build 26) : 36 tests sur 36 réussis (32 unitaires, 4 d'interface) sur simulateur iPhone SE, iOS 26.2, compilation Release ARM64 et `CameraLog.ipa` (artefact **CameraLog-iPhone-unsigned**, conservé sept jours). Détail dans [le protocole de validation](docs/VALIDATION.md). Les tests tournent sur simulateur ; **aucune de ces fonctions n'a encore été éprouvée sur un véritable iPhone ni en conditions de tournage.**

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

- Créer une production, puis une journée : elle démarre avec CAM A. **Ajouter la caméra B** (puis C…) se fait en un toucher, sans formulaire. Reprendre le rapport le plus récent depuis l'accueil.
- Tout reste modifiable : **Réglages** d'une production (informations, séries d'objectifs, kit de filtres, listes LUT/ratio/format/résolution, cases affichées), **Modifier** une journée (numéro, date, lieu, unité, notes), balayer une caméra pour la modifier (nom, **couleur**, **ISO natif**, modèle, n° de série) ou la retirer de la journée, toucher l'en-tête d'un roll pour le renommer ou saisir magasin et reel.
- Chaque caméra a une couleur (A rouge, B bleue, C verte… par défaut, ou gris) affichée sur la journée, sur chaque fiche et dans le PDF.
- Chaque écran se met à jour immédiatement après une création ou une modification.
- Dans le rapport (une caméra, une journée), toucher **Nouvelle fiche**. La fiche contient :
  - l'identification : scène, plan, **roll** (la lettre de la caméra est imposée : sur CAM A on tape « 001 », « 1 » devient A001) et **MAG #** (le magasin, c'est-à-dire la carte du roll) ;
  - les réglages : objectif, diaph, filtres, ISO, température, FPS, shutter, LUT, ratio, format, résolution ;
  - le bloc **VFX** : son interrupteur affiche hauteur caméra, distance de mise au point et tilt ; les prises créées pendant qu'il est actif reçoivent le statut VFX ;
  - la section **Takes**, son bouton **+** et le bouton **Cerclage** ;
  - un commentaire.
- La liste du rapport regroupe les fiches par roll, avec le nombre de clips de chaque carte. Toucher une fiche l'ouvre pour y travailler directement. Balayer une fiche permet de la supprimer, après affichage des clips renumérotés.
- Recherche par scène/plan (« 14A »), roll ou objectif dans un rapport, et **recherche globale** sur la page de la production : texte libre et pastilles Jour · Caméra · Roll · Séquence · Statut (plusieurs choix par pastille), résultats par jour/caméra/roll avec compteur, interrupteur **Fiches / Prises** ; toucher un résultat ouvre la fiche.
- **Enregistrement automatique** : pas de bouton ; les réglages sont enregistrés ¾ de seconde après la dernière frappe, scène/plan/roll en quittant leur case. L'en-tête indique « Fiche enregistrée » ou ce qui manque ; tant qu'une fiche ne peut pas être enregistrée, « Abandonner » ou « Rétablir » remplace le retour.
- **Exporter** (journée ou rapport caméra) : PDF lisible, CSV compatible ZoeLog/Silverstack, JSON au format ZoeLog, partagés par la feuille de partage iOS (voir plus bas).
- Charger volontairement LES OMBRES depuis l'écran vide. Les données d'exemple ne sont jamais injectées automatiquement.

### SmartFill : suggérer sans imposer

À l'ouverture d'une fiche, les valeurs de la fiche la plus récente de la même caméra et de la même journée apparaissent **en gris et en italique, dans une case entourée de pointillés**. La case reste réellement vide : une suggestion n'est jamais enregistrée tant qu'elle n'est pas acceptée.

- **Reprendre**, sous une case, accepte sa suggestion : la valeur passe en blanc et les pointillés disparaissent.
- Taper directement dans la case remplace la suggestion, sans rien effacer.
- Laisser la case vide enregistre « inconnu ».
- **Tout reprendre** accepte toutes les suggestions encore en attente, sans jamais remplacer une valeur déjà tapée.
- Un bandeau indique combien de valeurs sont seulement proposées ; l'en-tête indique « Rien d'enregistré », « Modifications non enregistrées » ou « Fiche enregistrée ».

Le plan proposé est le **plan suivant** : 2 → 3, 09 → 10, A → B, 14A → 14B. Il reste une suggestion grise, comme le roll et la scène.

### Objectifs, diaph et filtres en un toucher

- **Objectif** : dans les réglages du projet, créer des séries (nom court et focales : « S4 » · « 18, 25, 32, 50, 75 »). La flèche de la case OBJECTIF montre chaque série et ses focales ; la case reçoit « S4 50mm ». Toucher le texte de la case permet toujours une valeur libre. Sans série, pas de flèche.
- **LUT, ratio, format, résolution** : même principe avec les listes des réglages du projet.
- **ISO** : l'ISO natif de la caméra est proposé en gris quand aucune fiche précédente ne propose d'ISO.
- **Diaph** : la flèche de la case DIAPH ouvre les diaphs pleins (1 → 22), chacun suivi de ses tiers : « 2.8 », « 2.8 ⅓ », « 2.8 ⅔ ».
- **Filtres** : le projet a un kit de familles et de valeurs (par défaut ND et IRND 0.3 → 2.1, BPM, HBM et Glimmer 1/8 → 1, POLA), modifiable dans les réglages du projet. La flèche de la case FILTRES montre chaque famille avec ses valeurs : un toucher ajoute le filtre, une autre valeur de la même famille le remplace, toucher une valeur choisie la retire. Les filtres se combinent : « ND 0.9 + BPM 1/4 ».

### Roll/card automatique

La case **Roll** se remplit comme les autres. À l'enregistrement, la fiche est rattachée au roll de ce nom pour cette caméra et cette journée (sans tenir compte des majuscules), ou le roll est créé. Il n'y a plus de bouton « Nouveau roll ». Corriger A010 en A011 sur une fiche déplace la fiche et ses prises ; la liste des numéros de clips modifiés s'affiche avant confirmation. Les prises déplacées se placent à la fin de la nouvelle carte, dans leur ordre. Une même scène/plan peut exister sur deux rolls (changement de carte pendant le plan), mais pas deux fois sur le même roll.

### Takes, libellés et cerclage

- **+** crée la prise suivante de la fiche (1, 2, 3…) en un geste. Si la fiche n'est pas encore enregistrée, ou si elle a été modifiée, + l'enregistre d'abord.
- Chaque prise conserve un **instantané des réglages** de la fiche au moment de sa création. Modifier ensuite la fiche ne réécrit pas les prises existantes ; l'édition d'une prise affiche son instantané.
- En mode normal, toucher une prise **transforme sa case en champ de saisie**, curseur après le texte : taper « PU » sur « 4 » donne « 4PU » ; on peut aussi tout réécrire, numéro compris. Raccourcis au-dessus du clavier : **PU** (garde le numéro), **FC** (retire le numéro), Effacer, Détails.
- **Appui long** sur une prise : PU, FC, Effacer le libellé, Détails… (statuts, commentaire, réglages enregistrés) et Supprimer, après confirmation montrant les clips renumérotés.
- **FC** (faux clip) désigne un clip réellement créé sur la caméra mais inexploitable : c'est une entrée de la séquence, qui occupe donc un numéro de clip, mais **pas de numéro de prise** : la prise suivante reprend le numéro libéré. Un numéro déjà utilisé dans la fiche est refusé. FC n'a aucun lien avec Circle.
- Le bouton **Cerclage** active un mode où toucher une prise la cercle ou la décercle immédiatement. Le mode actif est signalé par le bouton orange plein, un bandeau orange « CERCLAGE ACTIF » et un cadre orange épais autour des prises. Toucher à nouveau Cerclage rend au toucher son rôle d'édition. Les prises cerclées sont orange, avec une coche.
- VoiceOver : le bouton est annoncé « Mode cerclage, activé/désactivé » ; chaque prise « Prise 3, clip C005, libellé PU, cerclée/non cerclée », avec une consigne qui dépend du mode. Les changements de mode et les ajouts de prise sont annoncés. Les flèches des cases sont annoncées « Choisir objectif/diaphragme/filtres dans la liste ».

### Numéros de clips : règle retenue

Le numéro **Cxxx est calculé, jamais saisi** : c'est la position de l'entrée dans la séquence de sa carte (roll), tous plans confondus, en commençant à C001. Chaque roll a sa propre séquence.

Exemple sur A010 : 14A T01 → C001, 14A T02 → C002, 14B T01 → C003, 14B T02 · FC → C004, clip suivant → C005. Un nouveau roll A011 recommence à C001.

L'ordre de la carte est enregistré pour chaque prise (`cardOrder`) ; le numéro affiché en découle. Aucune case ne permet de modifier C016. Le nombre de clips et le dernier numéro de la carte s'affichent dans la section Takes et dans l'en-tête de chaque roll de la liste. Si la caméra compte plus de clips que CameraLog, une prise a pu être oubliée ou un faux clip créé : l'application ne peut pas savoir lequel sans connexion à la caméra et n'invente pas de diagnostic.

Les actions qui modifient des numéros déjà affichés montrent **avant confirmation** la liste « ancien → nouveau » :

- **Insérer une prise oubliée…** (section Takes) : choisir le numéro de prise et la position sur la carte (« Avant C004 · 14 / B · 2 »). La prise prend le numéro de cette position ; les clips suivants avancent d'un cran.
- Supprimer une prise ou une fiche : les clips suivants reculent d'un cran. Si le clip existe sur la caméra, mieux vaut le libeller FC.
- Changer le roll d'une fiche qui a des prises.

Aucune autre action ne renumérote l'historique.

### Export : PDF, CSV Silverstack, JSON

Les fichiers CSV et JSON reprennent exactement ceux de ZoeLog, relevés sur de vrais exports le 4 octobre 2026 : 26 colonnes (`Scene, Date, Camera, Roll, Take, Clip, Circled, Lens, Filters, Stop, Focus, Lens Height, Color Temp, FPS, Shutter, ISO, Time Code, Tilt, Lut, Aspect Ratio, Format, Resolution, Description, Notes, Origin Date, Take Origin`), valeurs avec unités (`50mm`, `T2.8 1/3`, `5600K`, `23.976fps`, `172.8 degrees`, `800EI`), Circled `true`/`false`, clip entier par carte (FC compris), fins de ligne CRLF. Une ligne par prise dans l'ordre de la carte, avec l'instantané de réglages de la prise. Scène et plan sont réunis : « 14A », ou « 24/3 » quand le plan est un nombre.

Dans Silverstack (Import → ZoeLog CSV…), apparier par **Camera + Clip** : il faut que la séquence CameraLog corresponde à la carte, FC compris. Le timecode n'est pas saisi ; Origin Date et Take Origin sont les heures de saisie, pas d'enregistrement. **L'import dans un vrai Silverstack n'a pas encore été essayé.**

Le PDF (A4 paysage) a sa propre mise en page : en-tête production/DAY/date/lieu/équipe, un bloc par caméra (couleur, boîtier) et par roll (clips, magasin, reel), une ligne par prise (clip, scène, prise entourée si cerclée, objectif, diaph, filtres, ISO, K, FPS, shutter, notes avec VFX et réglages d'image), FC grisés, cerclées par scène.

## Données existantes et mise à jour

La version précédente stockait une entrée `TakeEntry` par prise, rattachée à un roll, avec un nom de clip libre. À la première ouverture de cette version :

1. SwiftData migre la base du schéma 1 au schéma 2 par une migration légère déclarée : ajout de l'entité fiche et de champs facultatifs uniquement. Aucune ligne n'est supprimée ; les identifiants UUID sont conservés.
2. L'application regroupe les anciennes prises en fiches par roll, scène et plan. Les réglages de la fiche sont ceux de la dernière prise du groupe ; chaque ancienne prise garde ses propres réglages historiques.
3. L'ordre de carte des anciennes prises suit leur date de création ; les Cxxx affichés en découlent. **L'ancien nom de clip saisi n'est ni effacé ni converti** : il reste visible dans l'édition de la prise, rubrique « Saisi avant la mise à jour », pour comparaison avec la carte.
4. Cette étape est idempotente. Si elle échoue, rien n'est enregistré et un écran d'erreur s'affiche, sans effacer de fichier.

Les anciennes prises n'avaient pas de libellé : il reste vide.

Les versions suivantes n'ajoutent que des champs facultatifs : le schéma 3 (builds 16 à 22) la série d'objectifs et le kit de filtres de chaque production ; le schéma 4 (build 25) les séries d'objectifs, les listes LUT/ratio/format/résolution et les cases affichées du projet, la couleur et l'ISO natif des caméras. Les nouvelles cases de la fiche (MAG #, LUT, VFX…) sont rangées dans les réglages existants et la carte du roll, sans migration. Une base de la build 15 s'ouvre sans conversion de données : la série d'objectifs est vide et le kit de filtres est le kit standard, jusqu'à modification dans les réglages du projet. Une base mise à jour ne peut plus être ouverte par l'ancienne version de l'app. Pour conserver les données, installer le nouvel IPA par-dessus l'ancien avec le même compte Apple dans Sideloadly, sans désinstaller l'app.

## Décisions et limites

- SwiftUI + SwiftData, iOS 17 minimum, mode de langage Swift 5. Les API utilisées sont natives ; aucune connexion ni synchronisation cloud.
- Interface sombre, commandes principales de 44–52 points, typographie système adaptable, libellés VoiceOver pour le cerclage et les prises. Les boutons « Reprendre » mesurent environ 30 points de haut pour garder la fiche compacte. Accessibilité et mise en page restent à vérifier sur appareil, notamment avec les tailles de texte maximales.
- La sauvegarde est explicite : bouton en bas de fiche, ou + qui enregistre la fiche avant d'ajouter la prise. Tant qu'une fiche est modifiée, le retour est remplacé par « Annuler ». En cas d'échec le repository annule les modifications non enregistrées et l'interface affiche une erreur.
- Les réglages des fiches sont du texte : objectif, diaph et filtres sont libres ; ISO et température sont des entiers positifs (« 5600K » devient 5600), FPS un nombre positif (« 23,976 » accepté), shutter un angle de 0 à 360°.
- Le numéro de prise suit le maximum de la fiche + 1, y compris après une entrée FC (2FC puis 3). Il n'est choisi librement que lors d'une insertion tardive.
- Les identifiants UUID sont locaux et stables. Dates/révisions préparent une évolution, mais il n'existe pas encore de journal de synchronisation, de tombstones ou de résolution de conflits.
- Les rolls sans fiche (restés vides depuis la version précédente, ou vidés par un déplacement) ne sont plus affichés ; ils ne sont pas supprimés.
- Catalogue d'objectifs, presets, paramètres visibles configurables, clavier caméra spécialisé, saisie timecode, exports et partage restent à implémenter. Les champs TC, codec et LUT de la version précédente sont conservés en base mais ne sont plus affichés.
- Aucune performance de saisie n'a encore été mesurée sur iPhone avec un assistant caméra.

Voir [les décisions d'architecture et la roadmap](docs/ARCHITECTURE.md) et [le protocole de validation](docs/VALIDATION.md).
