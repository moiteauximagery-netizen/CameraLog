# Tester CameraLog sur iPhone depuis Windows

## Compilation gratuite

Le workflow `.github/workflows/ios.yml` utilise une machine macOS **standard** GitHub Actions et refuse de s'exécuter si le dépôt est privé. Les machines standard des dépôts publics sont gratuites selon la [documentation GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). Il n'utilise ni TestFlight, ni abonnement Apple Developer, ni certificat ou mot de passe Apple dans GitHub.

Chaque push sur `main` ou lancement manuel depuis **Actions → iOS - Tests et IPA pour iPhone → Run workflow** lance :

1. Le contrôle de structure et la validation du fichier Xcode.
2. Les tests XCTest sur un simulateur iPhone installé sur le runner.
3. Une compilation Release ARM64 pour appareil physique.
4. La création d'un fichier IPA non signé, uniquement si les tests et la compilation réussissent.

Le résultat se télécharge sur la page du run réussi, rubrique **Artifacts → CameraLog-iPhone-unsigned**. Extraire le ZIP téléchargé pour obtenir `CameraLog.ipa`. Ne pas décompresser l'IPA lui-même. L'artefact est conservé sept jours ; relancer le workflow si nécessaire.

Un échec ne produit pas une prétendue app fonctionnelle : consulter l'étape rouge et l'artefact **CameraLog-diagnostics**. L'installation et l'usage sur un iPhone réel restent à vérifier après compilation.

## Installation gratuite sur iPhone 13 Pro

Prérequis : iOS 17 ou supérieur, câble USB et compte Apple gratuit.

1. Télécharger Sideloadly uniquement depuis son [site officiel](https://sideloadly.io/). Installer les composants Apple pour Windows recommandés sur ce site si demandés.
2. Brancher l'iPhone au PC, le déverrouiller et accepter « Faire confiance à cet ordinateur ».
3. Ouvrir Sideloadly, sélectionner l'iPhone et glisser `CameraLog.ipa` dans la fenêtre.
4. Saisir soi-même son compte Apple dans Sideloadly et effectuer l'authentification demandée. Ne publier aucun identifiant Apple dans le dépôt ni dans une conversation.
5. Lancer l'installation. Sideloadly signe l'application pour cet appareil.
6. Si iOS le demande, activer **Réglages → Confidentialité et sécurité → Mode développeur**, redémarrer et confirmer. Valider également le profil développeur dans **Réglages → Général → VPN et gestion de l'appareil** si demandé.
7. Ouvrir CameraLog et commencer avec « LES OMBRES — exemple ».

Avec un compte gratuit, la signature expire après **sept jours**. Le renouvellement proposé par Sideloadly nécessite que ses conditions de connexion et d'exécution soient réunies. Il faut renouveler la signature, pas acheter un abonnement. Conserver le même compte Apple et le même identifiant de bundle lors des mises à jour ; ne pas désinstaller l'app pour renouveler la signature, car cela effacerait ses données locales. Les exports/sauvegardes applicatives ne sont pas encore implémentés : utiliser des données de test.

Références : [FAQ Sideloadly](https://sideloadly.io/faq.html), [compte développeur gratuit Apple et expiration des profils](https://developer.apple.com/help/account/basics/about-your-developer-account).
