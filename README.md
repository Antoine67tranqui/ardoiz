# Ardoiz

Gestion digitale du credit informel ("l'ardoise") pour les commercants d'Afrique de l'Ouest.

## Structure du depot

- `ardoiz-backend/` — API NestJS + Prisma + PostgreSQL
- `ardoiz-app/` — application mobile Flutter (offline-first)
- `.github/workflows/backend-ci.yml` — CI (lint, build, tests) sur le backend

## Backend

```bash
cd ardoiz-backend
cp .env.example .env
npm install
docker compose up -d db
npm run prisma:migrate
npm run start:dev
```

API disponible sur `http://localhost:3000/api/v1`, documentation Swagger sur `http://localhost:3000/api/docs`.

Tests unitaires :

```bash
npm test
```

## Application mobile

Necessite le [Flutter SDK](https://docs.flutter.dev/get-started/install) (non installe dans cet environnement).

```bash
cd ardoiz-app
flutter pub get
flutter run --dart-define=ARDOIZ_API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Tests :

```bash
flutter test
```

## Parcours fonctionnel MVP

1. Le commercant s'inscrit avec son numero de telephone (OTP par SMS) puis cree un PIN.
2. Il ajoute ses clients et enregistre une "ardoise" (dette) par client, avec fonctionnement 100% hors ligne (synchronisation automatique au retour du reseau).
3. Le client recoit une relance automatique (SMS/WhatsApp) a l'approche ou au depassement de l'echeance.
4. Le remboursement est encaisse en especes ou via Mobile Money (webhook d'un agregateur type CinetPay/PayDunya), ce qui met a jour automatiquement le statut de la dette.
