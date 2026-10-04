import { NotificationsService } from '../src/notifications/notifications.service';
import { RemindersService } from '../src/reminders/reminders.service';
import { bearer, createTestApp, freshIp, makePremium, resetDb, Session, signUp, TestContext } from './helpers';

const DAY = 86400000;

describe('Relances, regles et abonnement (e2e)', () => {
  let ctx: TestContext;
  let a: Session;
  let sendSpy: jest.SpyInstance;

  const call = (method: 'get' | 'post' | 'delete', path: string, session: Session, body?: object) => {
    const req = ctx.http()[method](`/api/v1${path}`).set('X-Forwarded-For', freshIp()).set(bearer(session));
    return body ? req.send(body) : req;
  };

  // Echeance a midi, `offset` jours apres aujourd'hui (le cron raisonne en jours calendaires locaux).
  const dueIn = (offset: number) => {
    const d = new Date();
    d.setHours(12, 0, 0, 0);
    d.setDate(d.getDate() + offset);
    return d;
  };

  const customerFor = (userId: string, name = 'Aicha Traore') =>
    ctx.prisma.customer.create({ data: { userId, name, phone: '+229 01 67 07 70 27' } });
  const debtFor = (customerId: string, amount: string, dueOffset: number | null, extra: object = {}) =>
    ctx.prisma.debt.create({
      data: { customerId, amount, dueDate: dueOffset === null ? undefined : dueIn(dueOffset), ...extra },
    });

  beforeAll(async () => {
    ctx = await createTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
  });
  beforeEach(async () => {
    await resetDb(ctx.prisma);
    a = await signUp(ctx, '+2290167000201', 'Boutique A');
    sendSpy = jest.spyOn(ctx.app.get(NotificationsService), 'sendDebtReminder').mockResolvedValue(undefined);
  });
  afterEach(() => sendSpy.mockRestore());

  describe('relance manuelle', () => {
    it('refuse un canal inconnu avec une 400 (DTO valide)', async () => {
      const customer = await customerFor(a.userId);
      const debt = await debtFor(customer.id, '1000', null);
      const res = await call('post', `/debts/${debt.id}/reminders`, a, { channel: 'PIGEON' });
      expect(res.status).toBe(400);
      expect(await ctx.prisma.reminder.count()).toBe(0);
    });

    it('envoie par SMS par defaut ou par le canal demande, et journalise la relance', async () => {
      const customer = await customerFor(a.userId);
      const debt = await debtFor(customer.id, '1500', null);

      const sms = await call('post', `/debts/${debt.id}/reminders`, a, {});
      const whatsapp = await call('post', `/debts/${debt.id}/reminders`, a, { channel: 'WHATSAPP' });

      expect(sms.status).toBe(201);
      expect(sms.body).toMatchObject({ channel: 'SMS', status: 'SENT' });
      expect(whatsapp.body).toMatchObject({ channel: 'WHATSAPP', status: 'SENT' });
      expect(sendSpy).toHaveBeenCalledWith(expect.objectContaining({ amount: '1500', customerName: 'Aicha Traore', businessName: 'Boutique A' }));
    });

    it("marque la relance FAILED (sans erreur 500) quand le fournisseur d'envoi echoue", async () => {
      sendSpy.mockRejectedValueOnce(new Error('fournisseur SMS indisponible'));
      const customer = await customerFor(a.userId);
      const debt = await debtFor(customer.id, '1000', null);

      const res = await call('post', `/debts/${debt.id}/reminders`, a, {});
      expect(res.status).toBe(201);
      expect(res.body.status).toBe('FAILED');
    });
  });

  describe('regles de relance', () => {
    it('initialise 3 etapes par defaut (J-3 courtois, J0 neutre, J+7 ferme)', async () => {
      const res = await call('get', '/reminders/rules', a);
      expect(res.body.map((r: any) => [r.offsetDays, r.tone])).toEqual([[-3, 'GENTLE'], [0, 'NEUTRAL'], [7, 'FIRM']]);
    });

    it('cree/met a jour une etape, valide les bornes, et refuse de supprimer la regle d\'un autre (404)', async () => {
      const created = await call('post', '/reminders/rules', a, { offsetDays: 14, channel: 'WHATSAPP', tone: 'FIRM' });
      expect(created.body).toMatchObject({ offsetDays: 14, channel: 'WHATSAPP' });
      const updated = await call('post', '/reminders/rules', a, { offsetDays: 14, enabled: false });
      expect(updated.body).toMatchObject({ id: created.body.id, enabled: false, channel: 'WHATSAPP' });

      expect((await call('post', '/reminders/rules', a, { offsetDays: 999 })).status).toBe(400);
      expect((await call('post', '/reminders/rules', a, { offsetDays: 1, tone: 'RAGE' })).status).toBe(400);

      const b = await signUp(ctx, '+2290167000202', 'Boutique B');
      expect((await call('delete', `/reminders/rules/${created.body.id}`, b)).status).toBe(404);
      expect(await ctx.prisma.reminderRule.count({ where: { id: created.body.id } })).toBe(1);
    });
  });

  describe('cron des relances automatiques', () => {
    const run = () => ctx.app.get(RemindersService).sendAutomaticReminders();
    const stages = async () =>
      (await ctx.prisma.reminder.findMany({ orderBy: { stageOffsetDays: 'asc' } })).map((r) => [r.stageOffsetDays, r.status]);

    beforeEach(async () => {
      await makePremium(ctx, a.userId);
      await call('get', '/reminders/rules', a); // initialise J-3 / J0 / J+7
    });

    it('relance exactement les dettes dont l\'echeance tombe sur une etape, avec le bon ton', async () => {
      const c = await customerFor(a.userId);
      await debtFor(c.id, '1000', 3); // J-3
      await debtFor(c.id, '2000', 0); // J0
      await debtFor(c.id, '3000', -7); // J+7
      await debtFor(c.id, '4000', 2); // aucune etape
      await debtFor(c.id, '5000', -1); // aucune etape

      expect(await run()).toEqual({ sent: 3 });
      expect(await stages()).toEqual([[-3, 'SENT'], [0, 'SENT'], [7, 'SENT']]);

      const tones = Object.fromEntries(sendSpy.mock.calls.map(([p]) => [p.amount, p.tone]));
      expect(tones).toEqual({ '1000': 'GENTLE', '2000': 'NEUTRAL', '3000': 'FIRM' });
    });

    it('ne relance jamais deux fois la meme etape pour une meme dette', async () => {
      const c = await customerFor(a.userId);
      await debtFor(c.id, '1000', 0);

      expect(await run()).toEqual({ sent: 1 });
      expect(await run()).toEqual({ sent: 0 });
      expect(await ctx.prisma.reminder.count()).toBe(1);
    });

    it('ignore les dettes soldees, les etapes desactivees, les comptes gratuits et les Premium expires', async () => {
      const c = await customerFor(a.userId);
      await debtFor(c.id, '1000', 0, { status: 'PAID' });
      await ctx.prisma.reminderRule.updateMany({ where: { userId: a.userId, offsetDays: 7 }, data: { enabled: false } });
      await debtFor(c.id, '3000', -7);

      const free = await signUp(ctx, '+2290167000203', 'Gratuit');
      await ctx.prisma.reminderRule.create({ data: { userId: free.userId, offsetDays: 0 } });
      await debtFor((await customerFor(free.userId)).id, '1000', 0);

      const expired = await signUp(ctx, '+2290167000204', 'Expire');
      await ctx.prisma.user.update({ where: { id: expired.userId }, data: { plan: 'PREMIUM', planExpiresAt: new Date(Date.now() - DAY) } });
      await ctx.prisma.reminderRule.create({ data: { userId: expired.userId, offsetDays: 0 } });
      await debtFor((await customerFor(expired.userId)).id, '1000', 0);

      expect(await run()).toEqual({ sent: 0 });
      expect(await ctx.prisma.reminder.count()).toBe(0);
    });

    it("n'envoie qu'aux dettes de la regle de leur propre commercant", async () => {
      const b = await signUp(ctx, '+2290167000205', 'Boutique B');
      await makePremium(ctx, b.userId);
      await ctx.prisma.reminderRule.create({ data: { userId: b.userId, offsetDays: 30 } });
      const c = await customerFor(a.userId);
      await debtFor(c.id, '1000', -30); // echeance J+30 : regle de B seulement, la dette est a A

      expect(await run()).toEqual({ sent: 0 });
    });

    it("ne compte comme 'envoyee' que les relances reellement envoyees, et isole les echecs", async () => {
      const c = await customerFor(a.userId);
      await debtFor(c.id, '1000', 0);
      await debtFor(c.id, '2000', 0);
      sendSpy.mockRejectedValueOnce(new Error('fournisseur SMS indisponible'));

      const result = await run();
      const statuses = (await ctx.prisma.reminder.findMany()).map((r) => r.status).sort();

      expect(statuses).toEqual(['FAILED', 'SENT']);
      expect(result).toEqual({ sent: 1 });
    });
  });

  describe('abonnement', () => {
    it('affiche le plan gratuit puis Premium apres activation (mode test, hors production)', async () => {
      const before = await call('get', '/subscription/status', a);
      expect(before.body).toMatchObject({ plan: 'FREE', customerLimit: 15 });

      const upgrade = await call('post', '/subscription/upgrade', a);
      expect(upgrade.body).toMatchObject({ activated: true, simulated: true });

      const after = await call('get', '/subscription/status', a);
      expect(after.body).toMatchObject({ plan: 'PREMIUM', customerLimit: null });
    });
  });
});

describe('Abonnement en production (e2e)', () => {
  let ctx: TestContext;
  const previousEnv = process.env.NODE_ENV;

  beforeAll(async () => {
    process.env.NODE_ENV = 'production';
    ctx = await createTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
    process.env.NODE_ENV = previousEnv;
  });

  it("n'offre jamais Premium gratuitement quand aucun agregateur Mobile Money n'est configure (503)", async () => {
    await resetDb(ctx.prisma);
    // En production devCode n'est pas renvoye : on cree le compte directement.
    const user = await ctx.prisma.user.create({
      data: { phone: '+2290167000299', pinHash: 'x', businessName: 'Boutique Prod' },
    });
    const accessToken = ctx.app.get(require('@nestjs/jwt').JwtService).sign(
      { sub: user.id, phone: user.phone },
      { secret: process.env.JWT_ACCESS_SECRET },
    );

    const res = await ctx
      .http()
      .post('/api/v1/subscription/upgrade')
      .set('X-Forwarded-For', freshIp())
      .set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(503);
    const after = await ctx.prisma.user.findUniqueOrThrow({ where: { id: user.id } });
    expect(after.plan).toBe('FREE');
  });
});
