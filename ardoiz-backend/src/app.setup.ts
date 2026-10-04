import { INestApplication, ValidationPipe } from '@nestjs/common';
import helmet from 'helmet';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';

// rawBody: true conserve le corps brut de chaque requete (req.rawBody),
// necessaire pour verifier la signature HMAC du webhook Mobile Money sur les
// octets exacts envoyes par l'agregateur (voir MobileMoneyController).
// Partage entre main.ts et les tests e2e pour qu'ils ne divergent pas.
export const APP_OPTIONS = { rawBody: true } as const;

/** Configuration HTTP commune a l'application reelle et aux tests e2e. */
export function configureApp(app: INestApplication): void {
  app.use(helmet());

  // Liste blanche d'origines plutot qu'un CORS totalement ouvert : cette API
  // sert des donnees financieres (dettes, paiements), elle ne doit repondre
  // qu'aux clients connus (app web, site vitrine), pas a n'importe quel site.
  const corsOrigins = (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  app.enableCors({ origin: corsOrigins, credentials: true });

  // Derriere un reverse proxy / tunnel, req.ip est l'adresse du proxy : sans
  // cette option, le rate limiting par IP traiterait tous les utilisateurs
  // comme un seul et les bloquerait ensemble. TRUST_PROXY = nombre de proxys
  // de confiance devant l'API (0 ou absent = aucun, X-Forwarded-For ignore).
  const trustProxyHops = Number(process.env.TRUST_PROXY ?? 0);
  if (trustProxyHops > 0) {
    app.getHttpAdapter().getInstance().set('trust proxy', trustProxyHops);
  }

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.useGlobalFilters(new HttpExceptionFilter());
  app.setGlobalPrefix('api/v1');
}
