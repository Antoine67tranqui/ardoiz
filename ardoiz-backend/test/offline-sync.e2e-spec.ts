import { randomUUID } from 'crypto';
import { bearer, createTestApp, freshIp, makePremium, resetDb, Session, signUp, TestContext } from './helpers';

const DAY = 86400000;

describe('API pour l\'offline-first (e2e)', () => {
  let ctx: TestContext;
  let a: Session;
  let b: Session;

  const call = (method: 'get' | 'post' | 'patch' | 'delete', path: string, session: Session, body?: object) => {
    const req = ctx.http()[method](`/api/v1${path}`).set('X-Forwarded-For', freshIp()).set(bearer(session));
    return body ? req.send(body) : req;
  };
  const customerBody = (extra: object = {}) => ({ name: 'Aicha Traore', phone: '+229 01 67 07 70 27', ...extra });

  const makeCustomer = async (session = a, extra: object = {}) => {
    const res = await call('post', '/customers', session, customerBody(extra));
    expect(res.status).toBe(201);
    return res.body.id as string;
  };
  const makeDebt = async (customerId: string, amount: number, session = a, extra: object = {}) => {
    const res = await call('post', '/debts', session, { customerId, amount, ...extra });
    expect(res.status).toBe(201);
    return res.body.id as string;
  };
  const debtOf = (id: string) => ctx.prisma.debt.findUniqueOrThrow({ where: { id } });

  beforeAll(async () => {
    ctx = await createTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
  });
  beforeEach(async () => {
    await resetDb(ctx.prisma);
    a = await signUp(ctx, '+2290167000401', 'Boutique A');
    b = await signUp(ctx, '+2290167000402', 'Boutique B');
  });

  describe('creation idempotente de clients', () => {
    it('201 puis 200 pour un meme id : jamais de doublon, l\'etat serveur fait foi', async () => {
      const id = randomUUID();
      const first = await call('post', '/customers', a, customerBody({ id }));
      const replay = await call('post', '/customers', a, customerBody({ id, name: 'Nom different' }));

      expect(first.status).toBe(201);
      expect(replay.status).toBe(200);
      expect(replay.body).toEqual(first.body);
      expect(first.body.id).toBe(id);
      expect(await ctx.prisma.customer.count()).toBe(1);
    });

    it('absorbe 8 envois simultanes du meme id sans erreur 500 ni doublon', async () => {
      const id = randomUUID();
      const responses = await Promise.all(Array.from({ length: 8 }, () => call('post', '/customers', a, customerBody({ id }))));

      expect(responses.filter((r) => r.status >= 500)).toEqual([]);
      expect(responses.filter((r) => r.status === 201)).toHaveLength(1);
      expect(responses.filter((r) => r.status === 200)).toHaveLength(7);
      expect(await ctx.prisma.customer.count()).toBe(1);
    });

    it('refuse (409) un id deja utilise par un autre commercant, sans rien reveler ni modifier', async () => {
      const id = randomUUID();
      await call('post', '/customers', a, customerBody({ id, name: 'Client de A' }));

      const res = await call('post', '/customers', b, customerBody({ id, name: 'Intrus' }));
      expect(res.status).toBe(409);
      expect(JSON.stringify(res.body)).not.toContain('Client de A');
      expect((await ctx.prisma.customer.findUniqueOrThrow({ where: { id } })).userId).toBe(a.userId);
    });

    it('un rejeu aboutit meme quand le plan gratuit est plein, une vraie creation est refusee', async () => {
      const lastId = randomUUID();
      for (let i = 0; i < 14; i += 1) await makeCustomer();
      expect((await call('post', '/customers', a, customerBody({ id: lastId }))).status).toBe(201); // 15e

      expect((await call('post', '/customers', a, customerBody({ id: lastId }))).status).toBe(200);
      expect((await call('post', '/customers', a, customerBody({ id: randomUUID() }))).status).toBe(403);
    });

    it("refuse un id qui n'est pas un UUID v4, et la modification de l'id d'un client (400)", async () => {
      expect((await call('post', '/customers', a, customerBody({ id: 'pas-un-uuid' }))).status).toBe(400);
      expect((await call('post', '/customers', a, customerBody({ id: '11111111-1111-1111-8111-111111111111' }))).status).toBe(400); // v1

      const id = await makeCustomer();
      expect((await call('patch', `/customers/${id}`, a, { id: randomUUID() })).status).toBe(400);
      expect((await call('patch', `/customers/${id}`, a, { name: 'Nouveau nom' })).status).toBe(200);
    });
  });

  describe('creation idempotente de dettes', () => {
    it('201 puis 200 pour un meme id, avec l\'alerte de plafond dans les deux cas', async () => {
      const customerId = await makeCustomer(a, { creditLimit: 1000 });
      const id = randomUUID();
      const first = await call('post', '/debts', a, { id, customerId, amount: 5000 });
      const replay = await call('post', '/debts', a, { id, customerId, amount: 5000 });

      expect(first.status).toBe(201);
      expect(replay.status).toBe(200);
      expect(first.body.creditLimitExceeded).toBe(true);
      expect(replay.body.creditLimitExceeded).toBe(true);
      expect(await ctx.prisma.debt.count()).toBe(1);
    });

    it('absorbe des envois simultanes, refuse un id deja pris (autre client, autre commercant)', async () => {
      const customerId = await makeCustomer();
      const id = randomUUID();
      const responses = await Promise.all(Array.from({ length: 8 }, () => call('post', '/debts', a, { id, customerId, amount: 1000 })));
      expect(responses.filter((r) => r.status >= 500)).toEqual([]);
      expect(await ctx.prisma.debt.count()).toBe(1);

      const otherCustomer = await makeCustomer();
      expect((await call('post', '/debts', a, { id, customerId: otherCustomer, amount: 1000 })).status).toBe(409);

      const bCustomer = await makeCustomer(b);
      expect((await call('post', '/debts', b, { id, customerId: bCustomer, amount: 1000 })).status).toBe(409);
    });

    it('conserve la date de saisie de l\'appareil, bornee a [maintenant - 366 jours ; maintenant]', async () => {
      const customerId = await makeCustomer();
      const threeDaysAgo = new Date(Date.now() - 3 * DAY);
      const kept = await debtOf(await makeDebt(customerId, 100, a, { createdAt: threeDaysAgo.toISOString() }));
      expect(kept.createdAt.getTime()).toBe(threeDaysAgo.getTime());

      const future = await debtOf(await makeDebt(customerId, 100, a, { createdAt: new Date(Date.now() + 30 * DAY).toISOString() }));
      expect(future.createdAt.getTime()).toBeLessThanOrEqual(Date.now());
      expect(future.createdAt.getTime()).toBeGreaterThan(Date.now() - 10000);

      const ancient = await debtOf(await makeDebt(customerId, 100, a, { createdAt: '2001-01-01T00:00:00.000Z' }));
      expect(Date.now() - ancient.createdAt.getTime()).toBeLessThanOrEqual(366 * DAY + 10000);
      expect(Date.now() - ancient.createdAt.getTime()).toBeGreaterThan(365 * DAY);
    });
  });

  describe('creation idempotente de paiements et sur-paiements', () => {
    it('un envoi rejoue ne credite jamais deux fois la dette', async () => {
      const debtId = await makeDebt(await makeCustomer(), 5000);
      const id = randomUUID();
      const first = await call('post', '/payments', a, { id, debtId, amount: 2000, method: 'CASH' });
      const replay = await call('post', '/payments', a, { id, debtId, amount: 2000, method: 'CASH' });

      expect(first.status).toBe(201);
      expect(replay.status).toBe(200);
      expect(replay.body.id).toBe(id);
      expect(await ctx.prisma.payment.count()).toBe(1);
      expect((await debtOf(debtId)).status).toBe('PARTIAL');
    });

    it('absorbe 8 envois simultanes du meme paiement : une seule ecriture, aucune erreur 500', async () => {
      const debtId = await makeDebt(await makeCustomer(), 5000);
      const id = randomUUID();
      const responses = await Promise.all(Array.from({ length: 8 }, () => call('post', '/payments', a, { id, debtId, amount: 1000, method: 'CASH' })));

      expect(responses.filter((r) => r.status >= 500)).toEqual([]);
      expect(await ctx.prisma.payment.count()).toBe(1);
    });

    it('refuse (409) un id de paiement deja utilise ailleurs, (403) une dette etrangere', async () => {
      const debtA = await makeDebt(await makeCustomer(), 5000);
      const id = randomUUID();
      await call('post', '/payments', a, { id, debtId: debtA, amount: 100, method: 'CASH' });

      const debtA2 = await makeDebt(await makeCustomer(), 5000);
      expect((await call('post', '/payments', a, { id, debtId: debtA2, amount: 100, method: 'CASH' })).status).toBe(409);
      expect((await call('post', '/payments', b, { id: randomUUID(), debtId: debtA, amount: 100, method: 'CASH' })).status).toBe(403);
    });

    it('refuse un paiement superieur au solde restant (400 OVERPAYMENT), accepte le solde exact', async () => {
      const debtId = await makeDebt(await makeCustomer(), 5000);
      await call('post', '/payments', a, { debtId, amount: 3000, method: 'CASH' });

      const over = await call('post', '/payments', a, { debtId, amount: 2001, method: 'CASH' });
      expect(over.status).toBe(400);
      expect(over.body.message.code).toBe('OVERPAYMENT');

      expect((await call('post', '/payments', a, { debtId, amount: 2000, method: 'CASH' })).status).toBe(201);
      expect((await debtOf(debtId)).status).toBe('PAID');
      expect((await call('post', '/payments', a, { debtId, amount: 1, method: 'CASH' })).status).toBe(400); // deja soldee
    });

    it('deux paiements simultanes ne peuvent pas depasser ensemble le solde (verrou)', async () => {
      const debtId = await makeDebt(await makeCustomer(), 5000);
      const responses = await Promise.all(
        Array.from({ length: 6 }, () => call('post', '/payments', a, { debtId, amount: 3000, method: 'CASH' })),
      );

      expect(responses.filter((r) => r.status === 201)).toHaveLength(1);
      expect(responses.filter((r) => r.status === 400)).toHaveLength(5);
      expect(responses.filter((r) => r.status >= 500)).toEqual([]);
      expect(await ctx.prisma.payment.count()).toBe(1);
    });

    it('conserve la date du paiement de l\'appareil (bornee), meme hors ligne depuis plusieurs jours', async () => {
      const debtId = await makeDebt(await makeCustomer(), 5000);
      const twoDaysAgo = new Date(Date.now() - 2 * DAY);
      const res = await call('post', '/payments', a, { debtId, amount: 100, method: 'CASH', paidAt: twoDaysAgo.toISOString() });
      expect(new Date(res.body.paidAt).getTime()).toBe(twoDaysAgo.getTime());
    });

    it('les paiements Mobile Money recus (webhook) restent acceptes au-dela du solde : l\'argent est bien arrive', async () => {
      const debtId = await makeDebt(await makeCustomer(), 1000);
      const raw = JSON.stringify({ transactionRef: 'TX-OVER', amount: 5000, debtId });
      const res = await ctx
        .http()
        .post('/api/v1/webhooks/mobile-money')
        .set('X-Forwarded-For', freshIp())
        .set('Content-Type', 'application/json')
        .set('x-momo-signature', require('crypto').createHmac('sha256', process.env.MOMO_WEBHOOK_SECRET as string).update(raw).digest('hex'))
        .send(raw);

      expect(res.status).toBe(201);
      expect((await debtOf(debtId)).status).toBe('PAID');
    });
  });

  describe('correction et suppression', () => {
    it('supprime un paiement : la dette retrouve son solde et son statut', async () => {
      const debtId = await makeDebt(await makeCustomer(), 5000);
      const pay = await call('post', '/payments', a, { debtId, amount: 5000, method: 'CASH' });
      expect((await debtOf(debtId)).status).toBe('PAID');

      expect((await call('delete', `/payments/${pay.body.id}`, a)).status).toBe(200);
      expect((await debtOf(debtId)).status).toBe('PENDING');
      expect((await call('delete', `/payments/${pay.body.id}`, a)).status).toBe(404);
    });

    it("interdit de supprimer le paiement d'un autre commercant (403) sans rien modifier", async () => {
      const debtId = await makeDebt(await makeCustomer(), 5000);
      const pay = await call('post', '/payments', a, { debtId, amount: 1000, method: 'CASH' });

      expect((await call('delete', `/payments/${pay.body.id}`, b)).status).toBe(403);
      expect(await ctx.prisma.payment.count()).toBe(1);
    });

    it('corrige une dette : montant, motif, categorie, echeance ; null efface motif et echeance', async () => {
      const debtId = await makeDebt(await makeCustomer(), 5000, a, { reason: 'Riz', dueDate: '2030-01-01' });

      const edited = await call('patch', `/debts/${debtId}`, a, { amount: 4500, reason: 'Riz + huile', category: 'Alimentation', dueDate: '2030-06-01' });
      expect(edited.status).toBe(200);
      expect(await debtOf(debtId)).toMatchObject({ reason: 'Riz + huile', category: 'Alimentation' });
      expect(Number((await debtOf(debtId)).amount)).toBe(4500);

      await call('patch', `/debts/${debtId}`, a, { reason: null, dueDate: null });
      expect(await debtOf(debtId)).toMatchObject({ reason: null, dueDate: null });
      await call('patch', `/debts/${debtId}`, a, { category: 'Boisson' });
      expect(await debtOf(debtId)).toMatchObject({ reason: null, category: 'Boisson' }); // champs omis intacts
    });

    it('recalcule le statut quand le montant change, refuse un montant inferieur aux paiements recus', async () => {
      const debtId = await makeDebt(await makeCustomer(), 5000);
      await call('post', '/payments', a, { debtId, amount: 3000, method: 'CASH' });

      const tooLow = await call('patch', `/debts/${debtId}`, a, { amount: 2999 });
      expect(tooLow.status).toBe(400);
      expect(tooLow.body.message.code).toBe('AMOUNT_BELOW_PAYMENTS');

      await call('patch', `/debts/${debtId}`, a, { amount: 3000 });
      expect((await debtOf(debtId)).status).toBe('PAID');
      await call('patch', `/debts/${debtId}`, a, { amount: 8000 });
      expect((await debtOf(debtId)).status).toBe('PARTIAL');
    });

    it("supprime une dette en cascade (paiements, relances) ; refuse celle d'un autre commercant ; 404 si inconnue", async () => {
      const debtId = await makeDebt(await makeCustomer(), 5000);
      await call('post', '/payments', a, { debtId, amount: 1000, method: 'CASH' });

      expect((await call('delete', `/debts/${debtId}`, b)).status).toBe(403);
      expect((await call('patch', `/debts/${debtId}`, b, { amount: 10 })).status).toBe(403);
      expect(await ctx.prisma.debt.count()).toBe(1);

      expect((await call('delete', `/debts/${debtId}`, a)).status).toBe(200);
      expect(await ctx.prisma.payment.count()).toBe(0);
      expect((await call('delete', `/debts/${debtId}`, a)).status).toBe(404);
      expect((await call('patch', `/debts/${debtId}`, a, { amount: 10 })).status).toBe(404);
    });
  });

  describe('solde client net des paiements', () => {
    it("un client qui a rembourse 4000 sur 5000 doit 1000, pas 5000", async () => {
      const customerId = await makeCustomer(a, { creditLimit: 2000 });
      const debtId = await makeDebt(customerId, 5000);
      await call('post', '/payments', a, { debtId, amount: 4000, method: 'CASH' });

      const [customer] = (await call('get', '/customers', a)).body;
      expect(customer).toMatchObject({ outstandingBalance: 1000, creditLimitExceeded: false });

      await makeDebt(customerId, 500); // 1000 + 500 = 1500 < 2000
      expect((await call('get', '/customers', a)).body[0]).toMatchObject({ outstandingBalance: 1500, creditLimitExceeded: false });
      const over = await call('post', '/debts', a, { customerId, amount: 600 }); // 2100 > 2000
      expect(over.body.creditLimitExceeded).toBe(true);
    });

    it('est coherent avec le tableau de bord Premium et l\'export CSV', async () => {
      await makePremium(ctx, a.userId);
      const debtId = await makeDebt(await makeCustomer(), 5000);
      await call('post', '/payments', a, { debtId, amount: 4000, method: 'CASH' });

      expect((await call('get', '/dashboard/summary', a)).body.totalOutstanding).toBe(1000);
      expect((await call('get', '/export/history', a)).text).toContain(',5000.00,4000.00,1000.00,');
    });
  });

  describe('instantane de synchronisation', () => {
    it('exige une authentification', async () => {
      expect((await ctx.http().get('/api/v1/sync/snapshot').set('X-Forwarded-For', freshIp())).status).toBe(401);
    });

    it('renvoie tout l\'etat du commercant, avec montants numeriques, et rien d\'un autre', async () => {
      const customerId = await makeCustomer(a, { creditLimit: 9000 });
      const debtId = await makeDebt(customerId, 1250.5, a, { reason: 'Riz', category: 'Alimentation', dueDate: '2030-01-01' });
      const pay = await call('post', '/payments', a, { debtId, amount: 250.5, method: 'MOMO' });
      await makeDebt(await makeCustomer(b), 777, b);

      const res = await call('get', '/sync/snapshot', a);
      expect(res.status).toBe(200);
      expect(new Date(res.body.serverTime).getTime()).toBeGreaterThan(Date.now() - 5000);
      expect(res.body.customers).toEqual([
        expect.objectContaining({ id: customerId, name: 'Aicha Traore', phone: '+229 01 67 07 70 27', creditLimit: 9000 }),
      ]);
      expect(res.body.debts).toEqual([
        expect.objectContaining({ id: debtId, customerId, amount: 1250.5, reason: 'Riz', category: 'Alimentation', status: 'PARTIAL' }),
      ]);
      expect(res.body.payments).toEqual([
        expect.objectContaining({ id: pay.body.id, debtId, amount: 250.5, method: 'MOMO' }),
      ]);
    });

    it('ne contient plus les entites supprimees (le mobile s\'en sert pour retirer sa copie locale)', async () => {
      const customerId = await makeCustomer();
      const debtId = await makeDebt(customerId, 1000);
      await call('post', '/payments', a, { debtId, amount: 100, method: 'CASH' });
      await call('delete', `/customers/${customerId}`, a);

      const res = await call('get', '/sync/snapshot', a);
      expect(res.body).toMatchObject({ customers: [], debts: [], payments: [] });
    });
  });
});
