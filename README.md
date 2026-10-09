# Carné

Le carnet de crédit de votre commerce : gestion digitale de l'ardoise (crédit informel) pour les commerçants d'Afrique de l'Ouest. Anciennement « Ardoiz ».

Principe directeur : **hors ligne d'abord**. Chaque saisie est enregistrée immédiatement sur le téléphone, dans une base chiffrée, puis envoyée au serveur dès que le réseau le permet, sans doublon ni perte.

## Contenu du dépôt

| Dossier | Rôle |
| --- | --- |
| `ardoiz-app/` | Application mobile Flutter (Android) |
| `ardoiz-backend/` | API NestJS, Prisma, PostgreSQL |
| `ardoiz-web/` | Vitrine statique (sans JavaScript), pages légales, et **client web en ligne** (`app/`, JavaScript natif sans outil de build) |
| `deploy/` | Production : Docker Compose, Caddy (HTTPS), sauvegardes chiffrées, scripts de contrôle |
| `docs/` | `guide-deploiement.md` (pas à pas) et `conformite/` (registre des traitements, procédures, dossier APDP) |
| `brand/` | Logo (SVG) et script de génération des icônes (`node brand/render.mjs`) |
| `.github/workflows/` | CI : backend (dont image Docker), Flutter, web (dont navigateur réel), release Android signée |

Carné est conçu et développé par **CIVORA CONSEIL ET SOLUTIONS**.

Les noms de dossiers `ardoiz-*` sont conservés pour ne pas casser l'historique ; la marque est Carné.

## Fonctions de l'application

- Compte par numéro de téléphone : code SMS, puis code PIN à 4 chiffres (verrouillage après 5 erreurs).
- Clients (plafond de crédit facultatif), **fournisseurs** (ce que je dois), **caisse** (ventes au comptant, dépenses, trésorerie), dettes (motif, catégorie, échéance), remboursements partiels ou totaux, statuts calculés (à payer, partielle, soldée, en retard).
- Relances : SMS envoyé par Carné (service SMS du serveur), ou SMS et WhatsApp ouverts depuis le téléphone avec un message prêt au bon montant.
- Tableau de bord Premium calculé sur le téléphone (retards, clients à surveiller, catégories, tendance sur 6 mois, taux de paiement à temps).
- Relances automatiques Premium, abonnement, export CSV, changement de PIN, suppression du compte.
- Vie privée : consentement explicite versionné, export complet (JSON) et par personne, journal d'activité du compte, opposition d'un client aux relances, suppression du compte.
- Carné en ligne (navigateur) : mêmes fonctions avec une connexion ; l'application Android reste la seule à fonctionner hors connexion.
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

### Site et client web

```bash
cd ardoiz-web
npm test        # site : CSP stricte, liens, accessibilité ; client : aucun innerHTML, unités, cohérence avec le serveur
npm start       # http://127.0.0.1:8081 : site + client en ligne, /api relayé vers le backend (127.0.0.1:3998)
npm run test:e2e   # navigateur réel (Playwright) contre un backend démarré hors production
```

Le test de bout en bout lit la variable `PLAYWRIGHT_PATH` (chemin de `playwright/index.mjs`), `DATABASE_URL` (pour simuler le temps qui passe) et utilise le CLI d'administration compilé du backend.

## Mise en production

Tout est dans **[docs/guide-deploiement.md](docs/guide-deploiement.md)** : domaine, serveur, configuration, SMS, paiement, Android et Google Play, APDP, pilote, exploitation, liste de contrôle. Points à retenir :

1. **Paiement Mobile Money (FedaPay)** : l'appel réel n'est pas écrit (FedaPay n'était pas joignable depuis l'environnement de développement). Tant que `MobileMoneyService.REAL_INTEGRATION_IMPLEMENTED` vaut `false`, l'abonnement et les demandes de paiement sont fermés en production et l'application l'indique. Le script `ardoiz-backend/scripts/fedapay-sandbox-check.mjs` vérifie l'accès au bac à sable ; son résultat servira à écrire l'intégration.
2. **SMS** : `SMS_USERNAME`, `SMS_API_KEY`, `SMS_SENDER_ID` (Africa's Talking). Écrit mais pas essayé sur un compte réel.
3. **Secrets** : jamais dans le dépôt (un test le vérifie). L'API refuse de démarrer avec les valeurs d'exemple.
4. **Signature Android** : produite par la CI (`release-android.yml`) à partir de secrets GitHub ; elle refuse une signature de débogage.
5. **Textes juridiques** : les passages `[à compléter]` et `[à confirmer]` sont volontairement visibles ; liste dans `docs/conformite/points-a-completer.md`.

## Limites connues

- Pas de synchronisation lorsque l'application est fermée (elle se fait à l'ouverture, au retour du réseau et toutes les minutes pendant l'usage).
- Les relances automatiques dont l'envoi échoue ne sont pas rejouées.
- Les numéros de clients sont acceptés dans un format large (8 à 20 caractères) ; WhatsApp exige un indicatif pays.
- L'application n'a pas pu être compilée pour Android dans l'environnement de développement utilisé (pas de SDK Android) : les tests Flutter s'exécutent sur la machine hôte avec le même SQLCipher, mais un essai sur un vrai téléphone reste à faire avant diffusion.
- Les anciennes données de la version « Ardoiz » ne sont pas migrées.
- Les images Docker et le fichier Caddy n'ont pas pu être exécutés dans l'environnement de développement (pas de moteur Docker) : la CI les construit et les valide, le premier déploiement est leur premier essai réel.
- Le logo de CIVORA est un PNG sur carte blanche ; une version vectorielle ou à fond transparent serait plus nette.
