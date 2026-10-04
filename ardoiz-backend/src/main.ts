import { NestFactory } from '@nestjs/core';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { APP_OPTIONS, configureApp } from './app.setup';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, APP_OPTIONS);
  configureApp(app);

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
