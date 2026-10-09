import { bearer, createTestApp, freshIp, makePremium, resetDb, Session, signUp, TestContext } from './helpers';

describe('Logique metier (e2e)', () => {
  let ctx: TestContext;
  let a: Session;
  let b: Session;

  const call = (method: 'get' | 'post' | 'patch' | 'delete', path: string, session: Session, body?: object) => {
    const req = ctx.http()[method](`/api/v1${path}`).set('X-Forwarded-For', freshIp()).set(bearer(session));
    return body ? req.send(body) : req;
  };

  const newCustomer = async (session: Session, name = 'Aicha Traore', extra: object = {}) => {
    const res = await call('post', '/customers', session, { name, phone: '+229 01 67 07 70 27', ...extra });
    expect(res.status).toBe(201);
    return res.body as { id: string };
  };
  const newDebt = async (session: Session, customerId: string, amount: number, extra: object = {}) => {
    const res = await call('post', '/debts', session, { customerId, amount, ...extra });
    expect(res.status).toBe(201);
    return res.body as { id: string; creditLimitExceeded: boolean };
  };

  beforeAll(async () => {
    ctx = await createTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
  });
  beforeEach(async () => {
    await resetDb(ctx.prisma);
    a = await signUp(ctx, '+2290167000101', 'Boutique A');
    b = await signUp(ctx, '+2290167000102', 'Boutique B');
  });

  describe('isolation multi-tenant : un commercant ne touche jamais aux donnees d\'un autre', () => {
    let customerId: string;
    let debtId: string;

    beforeEach(async () => {
      customerId = (await newCustomer(a)).id;
      debtId = (await newDebt(a, customerId, 5000)).id;
    });

    it.each([
      ['lire le client', (s: Session) => call('get', `/customers/${customerId}`, s)],
      ['modifier le client', (s: Session) => call('patch', `/customers/${customerId}`, s, { name: 'Pirate' })],
      ['supprimer le client', (s: Session) => call('delete', `/customers/${customerId}`, s)],
      ['creer une dette sur ce client', (s: Session) => call('post', '/debts', s, { customerId, amount: 100 })],
      ['lire la dette', (s: Session) => call('get', `/debts/${debtId}`, s)],
      ['enregistrer un paiement sur la dette', (s: Session) => call('post', '/payments', s, { debtId, amount: 100, method: 'CASH' })],
      ['demander un paiement Mobile Money', (s: Session) => call('post', '/payments/momo-request', s, { debtId })],
      ['envoyer une relance', (s: Session) => call('post', `/debts/${debtId}/reminders`, s, {})],
    ])('B ne peut pas %s (403)', async (_label, action) => {
      const res = await action(b);
      expect(res.status).toBe(403);
    });

    it('les donnees de A restent intactes apres les tentatives de B', async () => {
      await call('patch', `/customers/${customerId}`, b, { name: 'Pirate' });
      await call('delete', `/customers/${customerId}`, b);
      await call('post', '/payments', b, { debtId, amount: 100, method: 'CASH' });

      const customer = await ctx.prisma.customer.findUniqueOrThrow({ where: { id: customerId } });
      expect(customer.name).toBe('Aicha Traore');
      expect(await ctx.prisma.payment.count()).toBe(0);
    });

    it('les listes, l\'export et le tableau de bord de B ne contiennent rien de A', async () => {
      await makePremium(ctx, b.userId);
      const customers = await call('get', '/customers', b);
      const debts = await call('get', '/debts', b);
      const exported = await call('get', '/export/history', b);
      const dashboard = await call('get', '/dashboard/summary', b);

      expect(customers.body).toEqual([]);
      expect(debts.body).toEqual([]);
      expect(exported.text).not.toContain('Aicha Traore');
      expect(dashboard.body.totalOutstanding).toBe(0);
      expect(dashboard.body.totalCustomers).toBe(0);
    });
  });

  describe('clients', () => {
    it('refuse un telephone invalide ou un nom trop court (400)', async () => {
      expect((await call('post', '/customers', a, { name: 'Aicha', phone: 'abc' })).status).toBe(400);
      expect((await call('post', '/customers', a, { name: 'A', phone: '+229 01 67 07 70 27' })).status).toBe(400);
    });

    it('limite le plan gratuit a 15 clients, sans limite en Premium', async () => {
      for (let i = 0; i < 15; i += 1) await newCustomer(a, `Client ${i + 1}`);
      const blocked = await call('post', '/customers', a, { name: 'Client 16', phone: '+229 01 67 07 70 27' });
      expect(blocked.status).toBe(403);
      expect(blocked.body.message.code).toBe('FREE_PLAN_LIMIT_REACHED');

      await makePremium(ctx, a.userId);
      expect((await call('post', '/customers', a, { name: 'Client 16', phone: '+229 01 67 07 70 27' })).status).toBe(201);
    });

    it('calcule solde, retard et depassement du plafond ; filtre, recherche et tri', async () => {
      const aicha = await newCustomer(a, 'Aicha Traore', { creditLimit: 6000 });
      const bako = await newCustomer(a, 'Bako Diallo');
      await newDebt(a, aicha.id, 4000);
      await newDebt(a, aicha.id, 3000, { dueDate: new Date(Date.now() - 5 * 86400000).toISOString() });
      await newDebt(a, bako.id, 1000);

      const list = (await call('get', '/customers?sortBy=balance&order=desc', a)).body;
      expect(list.map((c: any) => c.name)).toEqual(['Aicha Traore', 'Bako Diallo']);
      expect(list[0]).toMatchObject({ outstandingBalance: 7000, hasOverdueDebt: true, creditLimit: 6000, creditLimitExceeded: true });
      expect(list[1]).toMatchObject({ outstandingBalance: 1000, hasOverdueDebt: false, creditLimitExceeded: false });

      const overdue = (await call('get', '/customers?overdueOnly=true', a)).body;
      expect(overdue.map((c: any) => c.name)).toEqual(['Aicha Traore']);
      const search = (await call('get', '/customers?search=bako', a)).body;
      expect(search.map((c: any) => c.name)).toEqual(['Bako Diallo']);
      expect((await call('get', '/customers?sortBy=nimporte', a)).status).toBe(400);
    });

    it('la suppression d\'un client supprime ses dettes et paiements (cascade)', async () => {
      const customer = await newCustomer(a);
      const debt = await newDebt(a, customer.id, 1000);
      await call('post', '/payments', a, { debtId: debt.id, amount: 500, method: 'CASH' });

      expect((await call('delete', `/customers/${customer.id}`, a)).status).toBe(200);
      expect(await ctx.prisma.debt.count()).toBe(0);
      expect(await ctx.prisma.payment.count()).toBe(0);
    });
  });

  describe('dettes et paiements', () => {
    it('signale le depassement du plafond sans bloquer la creation', async () => {
      const customer = await newCustomer(a, 'Aicha Traore', { creditLimit: 5000 });
      expect((await newDebt(a, customer.id, 3000)).creditLimitExceeded).toBe(false);
      expect((await newDebt(a, customer.id, 2000)).creditLimitExceeded).toBe(false); // 5000 = plafond, pas au-dela
      expect((await newDebt(a, customer.id, 1)).creditLimitExceeded).toBe(true);
    });

    it('fait evoluer le statut PENDING -> PARTIAL -> PAID au fil des paiements manuels', async () => {
      const customer = await newCustomer(a);
      const debt = await newDebt(a, customer.id, 5000);
      const status = async () => (await call('get', `/debts/${debt.id}`, a)).body.status;

      expect(await status()).toBe('PENDING');
      await call('post', '/payments', a, { debtId: debt.id, amount: 2000, method: 'CASH' });
      expect(await status()).toBe('PARTIAL');
      await call('post', '/payments', a, { debtId: debt.id, amount: 3000, method: 'CASH' });
      expect(await status()).toBe('PAID');
    });

    it('valide les entrees : montant nul/negatif, client inexistant, methode inconnue (400/404)', async () => {
      const customer = await newCustomer(a);
      expect((await call('post', '/debts', a, { customerId: customer.id, amount: 0 })).status).toBe(400);
      expect((await call('post', '/debts', a, { customerId: customer.id, amount: -10 })).status).toBe(400);
      expect((await call('post', '/debts', a, { customerId: '11111111-1111-4111-8111-111111111111', amount: 10 })).status).toBe(404);

      const debt = await newDebt(a, customer.id, 1000);
      expect((await call('post', '/payments', a, { debtId: debt.id, amount: 10, method: 'BITCOIN' })).status).toBe(400);
    });

    it('refuse les montants hors bornes ou a trop de decimales (400, pas de 500 en base)', async () => {
      const customer = await newCustomer(a);
      const debt = await newDebt(a, customer.id, 1000);

      for (const amount of [10_000_000_000, 1e12, 100.123]) {
        expect((await call('post', '/debts', a, { customerId: customer.id, amount })).status).toBe(400);
        expect((await call('post', '/payments', a, { debtId: debt.id, amount, method: 'CASH' })).status).toBe(400);
      }
      expect((await call('post', '/customers', a, { name: 'Plafond', phone: '+229 01 67 07 70 27', creditLimit: 1e13 })).status).toBe(400);

      // Les bornes elles-memes sont acceptees (Decimal(12,2) : 9 999 999 999,99 au plus).
      expect((await call('post', '/debts', a, { customerId: customer.id, amount: 9_999_999_999 })).status).toBe(201);
      expect((await call('post', '/debts', a, { customerId: customer.id, amount: 1250.5 })).status).toBe(201);
    });

    it('borne et normalise les textes saisis (nom, motif, categorie)', async () => {
      const long = (n: number) => 'x'.repeat(n);
      expect((await call('post', '/customers', a, { name: long(101), phone: '+229 01 67 07 70 27' })).status).toBe(400);
      const trimmed = await call('post', '/customers', a, { name: '  Aicha Traore  ', phone: '+229 01 67 07 70 27' });
      expect(trimmed.body.name).toBe('Aicha Traore');

      const customerId = trimmed.body.id;
      expect((await call('post', '/debts', a, { customerId, amount: 100, reason: long(501) })).status).toBe(400);
      expect((await call('post', '/debts', a, { customerId, amount: 100, category: long(51) })).status).toBe(400);
      expect((await call('get', `/customers?search=${long(101)}`, a)).status).toBe(400);
    });

    it('filtre par statut et refuse un statut inconnu avec une 400 (pas une 500)', async () => {
      const customer = await newCustomer(a);
      const paid = await newDebt(a, customer.id, 1000);
      await newDebt(a, customer.id, 2000);
      await call('post', '/payments', a, { debtId: paid.id, amount: 1000, method: 'CASH' });

      const onlyPaid = await call('get', '/debts?status=PAID', a);
      expect(onlyPaid.body).toHaveLength(1);
      expect((await call('get', '/debts?status=NIMPORTEQUOI', a)).status).toBe(400);
    });
  });

  describe('tableau de bord (Premium)', () => {
    it('est reserve aux comptes Premium actifs (403 PREMIUM_REQUIRED), y compris un Premium expire', async () => {
      const free = await call('get', '/dashboard/summary', a);
      expect(free.status).toBe(403);
      expect(free.body.message.code).toBe('PREMIUM_REQUIRED');

      await ctx.prisma.user.update({
        where: { id: a.userId },
        data: { plan: 'PREMIUM', planExpiresAt: new Date(Date.now() - 1000) },
      });
      expect((await call('get', '/dashboard/summary', a)).status).toBe(403);
    });

    it('agrege correctement encours, categories, retards, recouvrement, clients a risque et tendance', async () => {
      await makePremium(ctx, a.userId);
      const day = 86400000;
      const c1 = await ctx.prisma.customer.create({ data: { userId: a.userId, name: 'Client 1', phone: '+229 01 67 07 70 27' } });
      const c2 = await ctx.prisma.customer.create({ data: { userId: a.userId, name: 'Client 2', phone: '+229 01 67 07 70 28' } });
      const mk = (customerId: string, amount: string, extra: object = {}) =>
        ctx.prisma.debt.create({ data: { customerId, amount, ...extra } });

      const d1 = await mk(c1.id, '10000', { category: 'Alimentation', status: 'PARTIAL', dueDate: new Date(Date.now() - 10 * day) });
      await mk(c1.id, '5000', { category: 'Alimentation', dueDate: new Date(Date.now() + 5 * day) });
      await mk(c2.id, '8000', { category: 'Boisson', dueDate: new Date(Date.now() - 3 * day) });
      const d4 = await mk(c2.id, '2000', { status: 'PAID', dueDate: new Date(Date.now() + day) }); // paye a temps
      const d5 = await mk(c2.id, '3000', { status: 'PAID', dueDate: new Date(Date.now() - 10 * day) }); // paye en retard
      await ctx.prisma.payment.createMany({
        data: [
          { debtId: d1.id, amount: '4000', method: 'CASH' },
          { debtId: d4.id, amount: '2000', method: 'MOMO' },
          { debtId: d5.id, amount: '3000', method: 'CASH' },
        ],
      });

      const res = await call('get', '/dashboard/summary', a);
      expect(res.status).toBe(200);
      const s = res.body;

      expect(s.totalOutstanding).toBe(19000); // 6000 + 5000 + 8000
      expect(s.totalCustomers).toBe(2);
      expect(s.customersWithDebt).toBe(2);
      expect(s.byCategory).toEqual([
        { category: 'Alimentation', totalOutstanding: 11000, count: 2 },
        { category: 'Boisson', totalOutstanding: 8000, count: 1 },
        { category: 'Autre', totalOutstanding: 0, count: 0 },
      ]);
      expect(s.overdueDebts.map((d: any) => [d.outstanding, d.daysOverdue])).toEqual([[6000, 10], [8000, 3]]);
      expect(s.recoveryRate).toBe(0.5);
      expect(s.atRiskCustomers.map((c: any) => [c.customerName, c.totalOverdueAmount, c.maxDaysOverdue])).toEqual([
        ['Client 1', 6000, 10],
        ['Client 2', 8000, 3],
      ]);
      expect(s.monthlyTrend).toHaveLength(6);
      const current = s.monthlyTrend[5];
      expect(current).toMatchObject({ amountGranted: 28000, amountRecovered: 9000 });
      expect(s.monthOverMonth).toEqual({ amountGrantedDelta: 28000, amountRecoveredDelta: 9000 });
    });
  });

  describe('export CSV', () => {
    it('produit un CSV avec BOM, en-tetes, valeurs exactes et echappement des virgules/guillemets', async () => {
      const customer = await newCustomer(a, 'Diallo, "le Grand"');
      const debt = await newDebt(a, customer.id, 5000, { reason: 'Riz, huile', category: 'Alimentation' });
      await call('post', '/payments', a, { debtId: debt.id, amount: 1500, method: 'CASH' });

      const res = await call('get', '/export/history', a);
      expect(res.status).toBe(200);
      expect(res.headers['content-type']).toContain('text/csv');
      expect(res.headers['content-disposition']).toMatch(/attachment; filename="carne-historique-\d{4}-\d{2}-\d{2}\.csv"/);

      expect(res.text.charCodeAt(0)).toBe(0xfeff);
      const lines = res.text.slice(1).split('\r\n');
      expect(lines[0]).toContain('Type,Nom,Telephone,Categorie,Motif,Montant initial (FCFA)');
      expect(lines[1]).toContain('Client,"Diallo, ""le Grand"""');
      expect(lines[1]).toContain('"Riz, huile"');
      expect(lines[1]).toContain(',5000.00,1500.00,3500.00,Partiellement remboursee,');
      expect(lines[1]).toContain(',CASH,0');
    });
  });
});
