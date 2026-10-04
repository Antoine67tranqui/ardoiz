import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as crypto from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { APP_OPTIONS, configureApp } from '../src/app.setup';
import { PrismaService } from '../src/prisma/prisma.service';

export interface TestContext {
  app: INestApplication;
  prisma: PrismaService;
  http: () => ReturnType<typeof request>;
}

let ipCounter = 0;
/** Adresse IP fictive unique : chaque scenario a son propre compteur de rate limiting. */
export const freshIp = () => `10.${Math.floor(ipCounter / 65025) % 255}.${Math.floor(ipCounter / 255) % 255}.${(ipCounter++ % 255) + 1}`;

export async function createTestApp(): Promise<TestContext> {
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
  const app = moduleRef.createNestApplication(APP_OPTIONS);
  configureApp(app);
  await app.init();
  return {
    app,
    prisma: app.get(PrismaService),
    http: () => request(app.getHttpServer()),
  };
}

export async function resetDb(prisma: PrismaService): Promise<void> {
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE "payments", "reminders", "reminder_rules", "debts", "customers", "users" RESTART IDENTITY CASCADE',
  );
}

export interface Session {
  userId: string;
  phone: string;
  accessToken: string;
  refreshToken: string;
}

/** Parcours complet OTP -> setup PIN, renvoie une session authentifiee. */
export async function signUp(
  ctx: TestContext,
  phone = '+2290167000001',
  businessName = 'Boutique Test',
  pin = '1234',
): Promise<Session> {
  const ip = freshIp();
  const otp = await ctx.http().post('/api/v1/auth/otp/request').set('X-Forwarded-For', ip).send({ phone });
  const verified = await ctx
    .http()
    .post('/api/v1/auth/otp/verify')
    .set('X-Forwarded-For', ip)
    .send({ phone, code: otp.body.devCode });
  const tokens = await ctx
    .http()
    .post('/api/v1/auth/pin/setup')
    .set('X-Forwarded-For', ip)
    .send({ otpSessionToken: verified.body.otpSessionToken, businessName, pin });
  const user = await ctx.prisma.user.findUniqueOrThrow({ where: { phone } });
  return { userId: user.id, phone, ...tokens.body };
}

export async function makePremium(ctx: TestContext, userId: string): Promise<void> {
  await ctx.prisma.user.update({
    where: { id: userId },
    data: { plan: 'PREMIUM', planExpiresAt: new Date(Date.now() + 30 * 24 * 3600 * 1000) },
  });
}

export const bearer = (session: Session) => ({ Authorization: `Bearer ${session.accessToken}` });

export const signBody = (rawBody: string, secret = process.env.MOMO_WEBHOOK_SECRET as string) =>
  crypto.createHmac('sha256', secret).update(rawBody).digest('hex');
