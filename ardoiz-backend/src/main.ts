import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';

async function bootstrap() {
  // rawBody: true conserve le corps brut de chaque requete (req.rawBody),
  // necessaire pour verifier la signature HMAC du webhook Mobile Money sur
  // les octets exacts envoyes par l'agregateur plutot que sur une
  // re-serialisation du DTO (voir MobileMoneyController).
  const app = await NestFactory.create(AppModule, { rawBody: true });

  app.use(helmet());

  // Liste blanche d'origines plutot qu'un CORS totalement ouvert : cette API
  // sert des donnees financieres (dettes, paiements), elle ne doit repondre
  // qu'aux clients connus (app web, site vitrine), pas a n'importe quel site.
  const corsOrigins = (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  app.enableCors({ origin: corsOrigins, credentials: true });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.useGlobalFilters(new HttpExceptionFilter());
  app.setGlobalPrefix('api/v1');

  const config = new DocumentBuilder()
    .setTitle('Ardoiz API')
    .setDescription(
      "API de gestion digitale du credit informel (l'ardoise) pour les commercants d'Afrique de l'Ouest",
    )
    .setVersion('0.1.0')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api/docs', app, document);

  const port = process.env.PORT ?? 3000;
  await app.listen(port);
}
bootstrap();
