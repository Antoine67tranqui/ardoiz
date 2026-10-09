// NODE_ENV doit valoir "production" AVANT l'import de l'application : ConfigModule
// fige la configuration (validee) au chargement du module, comme au demarrage reel.
process.env.NODE_ENV = 'production';

import { spawnSync } from 'child_process';
import { JwtService } from '@nestjs/jwt';
import { NotificationsService } from '../src/notifications/notifications.service';
import { createTestApp, freshIp, resetDb, TestContext } from './helpers';

describe('Comportement en production (e2e)', () => {
  let ctx: TestContext;

  beforeAll(async () => {
    ctx = await createTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
  });
  beforeEach(async () => {
    await resetDb(ctx.prisma);
  });

  it("echoue explicitement (503) sans fournisseur SMS, sans renvoyer ni conserver le code", async () => {
    const res = await ctx
      .http()
      .post('/api/v1/auth/otp/request')
      .set('X-Forwarded-For', freshIp())
      .send({ phone: '+2290167000099' });

    expect(res.status).toBe(503);
    expect(JSON.stringify(res.body)).not.toMatch(/\d{6}/);
    const user = await ctx.prisma.user.findUniqueOrThrow({ where: { phone: '+2290167000099' } });
    expect(user.otpCode).toBeNull();
  });

  it('ne renvoie jamais le code OTP (devCode) meme quand le SMS part reellement', async () => {
    const spy = jest.spyOn(ctx.app.get(NotificationsService), 'sendOtp').mockResolvedValueOnce(undefined);
    const res = await ctx
      .http()
      .post('/api/v1/auth/otp/request')
      .set('X-Forwarded-For', freshIp())
      .send({ phone: '+2290167000098' });

    expect(res.status).toBe(201);
    expect(res.body.devCode).toBeUndefined();
    spy.mockRestore();
  });

  it('marque une relance FAILED (et non SENT) quand aucun fournisseur reel n\'est configure', async () => {
    const user = await ctx.prisma.user.create({ data: { phone: '+2290167000097', pinHash: 'x', businessName: 'Boutique Prod' } });
    const customer = await ctx.prisma.customer.create({ data: { userId: user.id, name: 'Aicha', phone: '+229 01 67 07 70 27' } });
    const debt = await ctx.prisma.debt.create({ data: { customerId: customer.id, amount: '1000' } });
    const accessToken = ctx.app.get(JwtService).sign({ sub: user.id, phone: user.phone, tokenVersion: 0 }, { secret: process.env.JWT_ACCESS_SECRET });

    const res = await ctx
      .http()
      .post(`/api/v1/debts/${debt.id}/reminders`)
      .set('X-Forwarded-For', freshIp())
      .set('Authorization', `Bearer ${accessToken}`)
      .send({});

    expect(res.status).toBe(201);
    expect(res.body.status).toBe('FAILED');
  });

  it("n'offre jamais Premium gratuitement quand aucun agregateur Mobile Money n'est configure (503)", async () => {
    const user = await ctx.prisma.user.create({
      data: { phone: '+2290167000299', pinHash: 'x', businessName: 'Boutique Prod' },
    });
    const accessToken = ctx.app
      .get(JwtService)
      .sign({ sub: user.id, phone: user.phone, tokenVersion: 0 }, { secret: process.env.JWT_ACCESS_SECRET });

    const res = await ctx
      .http()
      .post('/api/v1/subscription/upgrade')
      .set('X-Forwarded-For', freshIp())
      .set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(503);
    expect(res.body.message).toMatchObject({ code: 'FEATURE_UNAVAILABLE' });
    expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: user.id } })).plan).toBe('FREE');
  });

  it("ne simule jamais une demande de paiement Mobile Money : 503 explicite, rien n'est envoye", async () => {
    const user = await ctx.prisma.user.create({ data: { phone: '+2290167000296', pinHash: 'x', businessName: 'Boutique Prod' } });
    const customer = await ctx.prisma.customer.create({ data: { userId: user.id, name: 'Aicha', phone: '+229 01 67 07 70 27' } });
    const debt = await ctx.prisma.debt.create({ data: { customerId: customer.id, amount: '1000' } });
    const accessToken = ctx.app.get(JwtService).sign({ sub: user.id, phone: user.phone, tokenVersion: 0 }, { secret: process.env.JWT_ACCESS_SECRET });

    const res = await ctx
      .http()
      .post('/api/v1/payments/momo-request')
      .set('X-Forwarded-For', freshIp())
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ debtId: debt.id });

    expect(res.status).toBe(503);
    expect(res.body.message).toMatchObject({ code: 'FEATURE_UNAVAILABLE' });
    expect(res.body.simulated).toBeUndefined();
  });

  it("annonce au client que les paiements ne sont pas disponibles (paymentsAvailable = false)", async () => {
    const user = await ctx.prisma.user.create({ data: { phone: '+2290167000295', pinHash: 'x', businessName: 'Boutique Prod' } });
    const accessToken = ctx.app.get(JwtService).sign({ sub: user.id, phone: user.phone, tokenVersion: 0 }, { secret: process.env.JWT_ACCESS_SECRET });

    const res = await ctx.http().get('/api/v1/subscription/status').set('X-Forwarded-For', freshIp()).set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(200);
    expect(res.body.paymentsAvailable).toBe(false);
  });

  it('refuse de demarrer avec un secret copie de .env.example', () => {
    // Execute dans un processus a part : la validation s'execute a l'import du module.
    const run = (overrides: Record<string, string>) =>
      spawnSync(
        process.execPath,
        ['-r', 'ts-node/register/transpile-only', '-e', "require('./src/config/env.validation').validateEnv(process.env)"],
        { cwd: process.cwd(), env: { ...process.env, ...overrides }, encoding: 'utf8' },
      );

    const placeholder = run({ MOMO_WEBHOOK_SECRET: 'change-me-webhook-secret' });
    expect(placeholder.status).not.toBe(0);
    expect(placeholder.stderr).toMatch(/MOMO_WEBHOOK_SECRET contient encore la valeur d'exemple/);

    expect(run({}).status).toBe(0);
  });
});
