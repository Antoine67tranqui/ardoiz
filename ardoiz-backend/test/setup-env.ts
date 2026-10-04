// Variables d'environnement des tests e2e. DATABASE_URL doit pointer vers une
// base dediee aux tests (elle est videe entre les tests).
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL =
  process.env.TEST_DATABASE_URL ??
  'postgresql://ardoiz:ardoiz@localhost:5432/ardoiz_test?schema=public';
process.env.JWT_ACCESS_SECRET = 'e2e-access-secret';
process.env.JWT_REFRESH_SECRET = 'e2e-refresh-secret';
process.env.JWT_OTP_SECRET = 'e2e-otp-secret';
process.env.MOMO_WEBHOOK_SECRET = 'e2e-webhook-secret';
process.env.CORS_ORIGINS = 'http://allowed.example';
// Un seul proxy de confiance : chaque test choisit son "IP" via X-Forwarded-For,
// ce qui isole les compteurs de rate limiting entre scenarios.
process.env.TRUST_PROXY = '1';
delete process.env.SMS_API_KEY;
delete process.env.SMS_USERNAME;
