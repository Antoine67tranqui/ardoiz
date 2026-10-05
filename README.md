# Carné

Le carnet de crédit de votre commerce : gestion digitale de l'ardoise (crédit informel) pour les commerçants d'Afrique de l'Ouest. Anciennement « Ardoiz ».

Principe directeur : **hors ligne d'abord**. Chaque saisie est enregistrée immédiatement sur le téléphone, dans une base chiffrée, puis envoyée au serveur dès que le réseau le permet, sans doublon ni perte.

## Contenu du dépôt

| Dossier | Rôle |
| --- | --- |
| `ardoiz-app/` | Application mobile Flutter (Android) |
| `ardoiz-backend/` | API NestJS, Prisma, PostgreSQL |
| `ardoiz-web/` | Vitrine statique (sans JavaScript) et politique de confidentialité |
| `brand/` | Logo (SVG) et script de génération des icônes (`node brand/render.mjs`) |
| `.github/workflows/` | CI : backend, Flutter (analyse, tests, intégration réelle), site |

Les noms de dossiers `ardoiz-*` sont conservés pour ne pas casser l'historique ; la marque est Carné.

## Fonctions de l'application

- Compte par numéro de téléphone : code SMS, puis code PIN à 4 chiffres (verrouillage après 5 erreurs).
- Clients (plafond de crédit facultatif), dettes (motif, catégorie, échéance), remboursements partiels ou totaux, statuts calculés (à payer, partielle, soldée, en retard).
- Relances : SMS envoyé par Carné (service SMS du serveur), ou SMS et WhatsApp ouverts depuis le téléphone avec un message prêt au bon montant.
- Tableau de bord Premium calculé sur le téléphone (retards, clients à surveiller, catégories, tendance sur 6 mois, taux de paiement à temps).
- Relances automatiques Premium, abonnement, export CSV, changement de PIN, suppression du compte.
- Synchronisation : file d'envoi persistante, ids générés sur le téléphone (envois rejouables sans doublon), conflits expliqués à l'utilisateur (modifications refusées, à réessayer ou abandonner).

## Architecture en bref

- **Données locales** : SQLite chiffré par SQLCipher (AES-256). La clé (256 bits aléatoires) vit dans le coffre sécurisé du système. Si SQLCipher est indisponible, l'application refuse de démarrer plutôt que de stocker en clair. Sauvegardes Android désactivées.
- **Argent** : entiers en centimes côté application, `Decimal(12,2)` côté serveur, jamais de flottant.
- **Serveur** : jetons d'accès et de rafraîchissement révocables (`tokenVersion`), codes SMS stockés sous forme d'empreinte, limites de débit, verrouillage du PIN y compris pour les actions sensibles, verrou de ligne contre les sur-paiements concurrents, en-têtes de sécurité, configuration validée au démarrage.
- **Paiements** : le serveur ne simule jamais un paiement en production (erreur explicite `FEATURE_UNAVAILABLE`).

## Lancer en développement

### Backend

```bash
cd ardoiz-backend
cp .env.example .env          # remplacer les secrets d'exemple
npm ci
docker compose up -d db
npm run prisma:migrate
npm run start:dev
```

API sur `http://localhost:3000/api/v1`, documentation Swagger sur `/api/docs`. Hors production, les codes SMS et les paiements sont simulés (le code de vérification est renvoyé dans la réponse `devCode`).

```bash
npm test             # unitaires
npm run test:e2e     # bout en bout sur une vraie base PostgreSQL de test
```

### Application mobile

Prérequis : Flutter 3.47 ou plus récent (Dart 3.12).

```bash
cd ardoiz-app
flutter pub get
flutter run --dart-define=CARNE_API_BASE_URL=http://10.0.2.2:3000/api/v1   # émulateur Android
flutter analyze
flutter test
```

Test d'intégration contre un vrai backend démarré hors production :

```bash
CARNE_BACKEND_URL=http://localhost:3000/api/v1 flutter test test/integration
```

Une version de production exige une adresse **HTTPS** (`--dart-define=CARNE_API_BASE_URL=https://...`).

### Site

```bash
cd ardoiz-web
npm test       # sécurité (aucun script, CSP stricte), liens, accessibilité de base, cohérence des prix avec le backend
npm start      # http://localhost:8080
```

## Avant une mise en production

À faire par l'éditeur : ces points ne peuvent pas être réglés par le code seul.

1. **Paiement Mobile Money** : l'appel réel à l'agrégateur (CinetPay ou PayDunya) n'est pas écrit, faute de contrat d'API et d'identifiants. Tant que `MobileMoneyService.REAL_INTEGRATION_IMPLEMENTED` vaut `false`, l'abonnement et les demandes de paiement sont désactivés en production, et l'application l'indique. Le webhook de confirmation (`/webhooks/mobile-money`) est prêt mais devra être aligné sur le format réel de l'agrégateur.
2. **SMS** : renseigner `SMS_USERNAME`, `SMS_API_KEY`, `SMS_SENDER_ID` (Africa's Talking). L'intégration est écrite mais n'a pas été essayée sur un compte réel. Sans fournisseur, la production refuse d'envoyer un code plutôt que de le simuler.
3. **WhatsApp automatique** par le serveur : non implémenté (les relances WhatsApp se font depuis le téléphone).
4. **Secrets** : trois secrets JWT distincts de 32 caractères ou plus, secret de webhook, `TRUST_PROXY` égal au nombre de proxys devant l'API, base PostgreSQL sauvegardée. L'API refuse de démarrer avec les valeurs d'exemple.
5. **Signature Android** : créer `ardoiz-app/android/key.properties` (jamais versionné) avec `keyAlias`, `keyPassword`, `storeFile`, `storePassword`. Sans ce fichier, la version release est signée avec la clé de débogage et ne doit pas être publiée.
6. **Identité légale** : compléter les passages `[à compléter]` de `ardoiz-web/confidentialite.html` (éditeur, hébergeur, contact, durées) et la faire relire par un juriste.
7. **Hébergement du site** : appliquer les en-têtes de `ardoiz-web/_headers` (ou leur équivalent) et ajouter le lien de téléchargement quand l'application est publiée.

## Limites connues

- Pas de synchronisation lorsque l'application est fermée (elle se fait à l'ouverture, au retour du réseau et toutes les minutes pendant l'usage).
- Les relances automatiques dont l'envoi échoue ne sont pas rejouées.
- Les numéros de clients sont acceptés dans un format large (8 à 20 caractères) ; WhatsApp exige un indicatif pays.
- L'application n'a pas pu être compilée pour Android dans l'environnement de développement utilisé (pas de SDK Android) : les tests Flutter s'exécutent sur la machine hôte avec le même SQLCipher, mais un essai sur un vrai téléphone reste à faire avant diffusion.
- Les anciennes données de la version « Ardoiz » ne sont pas migrées.
