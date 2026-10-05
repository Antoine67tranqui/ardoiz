import { CURRENT_TERMS_VERSION } from '../src/common/legal';
import { NotificationsService } from '../src/notifications/notifications.service';
import { RetentionCron } from '../src/audit/retention.cron';
import { run as adminRun } from '../src/admin/cli';
import { randomUUID } from 'crypto';
import { bearer, createTestApp, freshIp, makePremium, resetDb, Session, signUp, TestContext } from './helpers';

const DAY = 86400000;

describe('Fournisseurs, caisse, tresorerie et conformite (e2e)', () => {
  let ctx: TestContext;
  let a: Session;
  let b: Session;

  const call = (method: 'get' | 'post' | 'patch' | 'delete', path: string, session: Session, body?: object) => {
    const req = ctx.http()[method](`/api/v1${path}`).set('X-Forwarded-For', freshIp()).set(bearer(session));
    return body ? req.send(body) : req;
  };

  beforeAll(async () => {
    ctx = await createTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
  });
  beforeEach(async () => {
    await resetDb(ctx.prisma);
    a = await signUp(ctx, '+2290167000301', 'Boutique A');
    b = await signUp(ctx, '+2290167000302', 'Boutique B');
  });

  describe('fournisseurs (ce que je dois)', () => {
    const newSupplier = (s: Session, name = 'Grossiste Dossou') => call('post', '/customers', s, { name, phone: '+229 05 55 12 34', kind: 'SUPPLIER' });

    it('cree un fournisseur, le distingue des clients et filtre la liste', async () => {
      await call('post', '/customers', a, { name: 'Aicha', phone: '+229 01 67 07 70 27' });
      const supplier = await newSupplier(a);
      expect(supplier.status).toBe(201);
      expect(supplier.body.kind).toBe('SUPPLIER');

      const all = await call('get', '/customers', a);
      const suppliers = await call('get', '/customers?kind=SUPPLIER', a);
      const clients = await call('get', '/customers?kind=CLIENT', a);
      expect(all.body).toHaveLength(2);
      expect(suppliers.body.map((c: any) => c.name)).toEqual(['Grossiste Dossou']);
      expect(clients.body.map((c: any) => c.name)).toEqual(['Aicha']);
      expect((await call('get', '/customers?kind=PIGEON', a)).status).toBe(400);
    });

    it('le type ne se modifie pas apres la creation', async () => {
      const supplier = await newSupplier(a);
      const res = await call('patch', `/customers/${supplier.body.id}`, a, { kind: 'CLIENT' });
      expect(res.status).toBe(400); // propriete interdite (whitelist)
      expect((await ctx.prisma.customer.findUniqueOrThrow({ where: { id: supplier.body.id } })).kind).toBe('SUPPLIER');
    });

    it('plan gratuit : 15 clients ET 15 fournisseurs, comptes separement', async () => {
      for (let i = 0; i < 15; i += 1) {
        expect((await call('post', '/customers', a, { name: `Client ${i}`, phone: '+229 01 67 07 70 27' })).status).toBe(201);
      }
      const sixteenthClient = await call('post', '/customers', a, { name: 'Client 16', phone: '+229 01 67 07 70 27' });
      expect(sixteenthClient.status).toBe(403);
      expect(sixteenthClient.body.message.message).toMatch(/clients/);

      // Les fournisseurs ont leur propre quota.
      expect((await newSupplier(a)).status).toBe(201);
      for (let i = 0; i < 14; i += 1) await newSupplier(a, `Fournisseur ${i}`);
      const sixteenthSupplier = await newSupplier(a, 'Fournisseur 16');
      expect(sixteenthSupplier.status).toBe(403);
      expect(sixteenthSupplier.body.message.message).toMatch(/fournisseurs/);
    });

    it('une dette fournisseur se rembourse comme une dette client, mais on ne relance ni ne demande de Mobile Money a un fournisseur', async () => {
      const supplier = await newSupplier(a);
      const debt = await call('post', '/debts', a, { customerId: supplier.body.id, amount: 10000 });
      expect(debt.status).toBe(201);
      const pay = await call('post', '/payments', a, { debtId: debt.body.id, amount: 4000, method: 'CASH' });
      expect(pay.status).toBe(201);
      expect((await ctx.prisma.debt.findUniqueOrThrow({ where: { id: debt.body.id } })).status).toBe('PARTIAL');

      const spy = jest.spyOn(ctx.app.get(NotificationsService), 'sendDebtReminder').mockResolvedValue(undefined);
      const reminder = await call('post', `/debts/${debt.body.id}/reminders`, a, {});
      expect(reminder.status).toBe(400);
      expect(spy).not.toHaveBeenCalled();
      spy.mockRestore();

      const momo = await call('post', '/payments/momo-request', a, { debtId: debt.body.id });
      expect(momo.status).toBe(400);
    });

    it("le tableau de bord (Premium) separe ce qu'on me doit de ce que je dois", async () => {
      await makePremium(ctx, a.userId);
      const client = await call('post', '/customers', a, { name: 'Aicha', phone: '+229 01 67 07 70 27' });
      await call('post', '/debts', a, { customerId: client.body.id, amount: 5000, dueDate: new Date(Date.now() + DAY).toISOString() });
      const supplier = await newSupplier(a);
      await call('post', '/debts', a, { customerId: supplier.body.id, amount: 8000, dueDate: new Date(Date.now() - 2 * DAY).toISOString() });
      const paid = await call('post', '/debts', a, { customerId: supplier.body.id, amount: 1000 });
      await call('post', '/payments', a, { debtId: paid.body.id, amount: 1000, method: 'CASH' });

      const res = await call('get', '/dashboard/summary', a);
      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        totalOutstanding: 5000, // clients seulement
        totalCustomers: 1,
        customersWithDebt: 1,
        totalPayable: 8000,
        payableOverdue: 8000,
        suppliersWithDebt: 1,
      });
      expect(res.body.overdueDebts).toHaveLength(0); // une dette fournisseur en retard n'est pas une creance en retard
    });

    it('le snapshot de synchronisation expose le type, l\'opposition et la caisse', async () => {
      const supplier = await newSupplier(a);
      await call('patch', `/customers/${supplier.body.id}`, a, { reminderOptOut: true });
      await call('post', '/cash', a, { type: 'SALE', amount: 1200, label: 'Vente du matin' });
      const snap = await call('get', '/sync/snapshot', a);
      expect(snap.body.customers[0]).toMatchObject({ kind: 'SUPPLIER', reminderOptOut: true });
      expect(snap.body.cashEntries).toHaveLength(1);
      expect(snap.body.cashEntries[0]).toMatchObject({ type: 'SALE', amount: 1200, category: 'Autre', label: 'Vente du matin' });
    });
  });

  describe("opposition d'un client aux relances", () => {
    it('aucune relance manuelle ni automatique pour un client qui s\'oppose', async () => {
      await makePremium(ctx, a.userId);
      const spy = jest.spyOn(ctx.app.get(NotificationsService), 'sendDebtReminder').mockResolvedValue(undefined);
      const client = await call('post', '/customers', a, { name: 'Aicha', phone: '+229 01 67 07 70 27', reminderOptOut: true });
      const debt = await call('post', '/debts', a, { customerId: client.body.id, amount: 1000, dueDate: new Date(Date.now() - 3 * DAY).toISOString() });

      const manual = await call('post', `/debts/${debt.body.id}/reminders`, a, {});
      expect(manual.status).toBe(409);
      expect(manual.body.message.code).toBe('REMINDER_OPT_OUT');

      await ctx.prisma.reminderRule.create({ data: { userId: a.userId, offsetDays: 3 } });
      const { RemindersService } = await import('../src/reminders/reminders.service');
      const result = await ctx.app.get(RemindersService).sendAutomaticReminders();
      expect(result.sent).toBe(0);
      expect(spy).not.toHaveBeenCalled();

      // Retrait de l'opposition : les relances redeviennent possibles.
      await call('patch', `/customers/${client.body.id}`, a, { reminderOptOut: false });
      expect((await call('post', `/debts/${debt.body.id}/reminders`, a, {})).status).toBe(201);
      spy.mockRestore();
    });
  });

  describe('journal de caisse', () => {
    it('cree (idempotent), liste, modifie, supprime ; isole entre commercants', async () => {
      const id = randomUUID();
      const first = await call('post', '/cash', a, { id, type: 'EXPENSE', amount: 2500, label: 'Transport', category: 'Transport' });
      const replay = await call('post', '/cash', a, { id, type: 'EXPENSE', amount: 2500, label: 'Transport', category: 'Transport' });
      expect(first.status).toBe(201);
      expect(replay.status).toBe(200);
      expect(await ctx.prisma.cashEntry.count()).toBe(1);

      // Le meme id chez un autre commercant : conflit, jamais un acces.
      expect((await call('post', '/cash', b, { id, type: 'SALE', amount: 1 })).status).toBe(409);

      expect((await call('get', '/cash', a)).body).toHaveLength(1);
      expect((await call('get', '/cash', b)).body).toHaveLength(0);
      expect((await call('patch', `/cash/${id}`, b, { amount: 1 })).status).toBe(404);
      expect((await call('delete', `/cash/${id}`, b)).status).toBe(404);

      const edit = await call('patch', `/cash/${id}`, a, { amount: 3000, label: '' });
      expect(edit.body).toMatchObject({ amount: 3000, label: null });
      expect((await call('patch', `/cash/${id}`, a, { type: 'SALE' })).status).toBe(400);

      expect((await call('delete', `/cash/${id}`, a)).status).toBe(200);
      expect(await ctx.prisma.cashEntry.count()).toBe(0);
    });

    it('valide les montants, la nature et les dates (bornees, pas dans le futur)', async () => {
      expect((await call('post', '/cash', a, { type: 'SALE', amount: 0 })).status).toBe(400);
      expect((await call('post', '/cash', a, { type: 'SALE', amount: -5 })).status).toBe(400);
      expect((await call('post', '/cash', a, { type: 'SALE', amount: 10.123 })).status).toBe(400);
      expect((await call('post', '/cash', a, { type: 'AUTRE', amount: 5 })).status).toBe(400);
      expect((await call('post', '/cash', a, { type: 'SALE', amount: 1e12 })).status).toBe(400);

      const future = await call('post', '/cash', a, { type: 'SALE', amount: 5, occurredAt: new Date(Date.now() + 30 * DAY).toISOString() });
      expect(new Date(future.body.occurredAt).getTime()).toBeLessThanOrEqual(Date.now() + 1000);
      const old = await call('post', '/cash', a, { type: 'SALE', amount: 5, occurredAt: '2001-01-01T00:00:00Z' });
      expect(new Date(old.body.occurredAt).getTime()).toBeGreaterThan(Date.now() - 400 * DAY);
    });

    it('filtre par periode et par nature', async () => {
      const day = (n: number) => new Date(Date.now() - n * DAY).toISOString();
      await call('post', '/cash', a, { type: 'SALE', amount: 100, occurredAt: day(10) });
      await call('post', '/cash', a, { type: 'SALE', amount: 200, occurredAt: day(2) });
      await call('post', '/cash', a, { type: 'EXPENSE', amount: 50, occurredAt: day(2) });

      const recent = await call('get', `/cash?from=${encodeURIComponent(day(5))}`, a);
      expect(recent.body.map((e: any) => e.amount).sort((x: number, y: number) => x - y)).toEqual([50, 200]);
      const sales = await call('get', '/cash?type=SALE', a);
      expect(sales.body).toHaveLength(2);
      expect((await call('get', '/cash?limit=2000', a)).status).toBe(400);
    });

    it("la tresorerie compte l'argent reellement entre et sorti (ventes + remboursements recus, depenses + paiements fournisseurs)", async () => {
      const client = await call('post', '/customers', a, { name: 'Aicha', phone: '+229 01 67 07 70 27' });
      const supplier = await call('post', '/customers', a, { name: 'Grossiste', phone: '+229 05 55 12 34', kind: 'SUPPLIER' });
      const clientDebt = await call('post', '/debts', a, { customerId: client.body.id, amount: 5000 });
      const supplierDebt = await call('post', '/debts', a, { customerId: supplier.body.id, amount: 9000 });
      await call('post', '/payments', a, { debtId: clientDebt.body.id, amount: 2000, method: 'CASH' }); // entree
      await call('post', '/payments', a, { debtId: supplierDebt.body.id, amount: 3000, method: 'CASH' }); // sortie
      await call('post', '/cash', a, { type: 'SALE', amount: 10000 });
      await call('post', '/cash', a, { type: 'EXPENSE', amount: 1500, category: 'Transport' });
      await call('post', '/cash', a, { type: 'EXPENSE', amount: 500, category: 'Loyer' });
      // Autre commercant : n'interfere pas.
      await call('post', '/cash', b, { type: 'SALE', amount: 777777 });

      const from = new Date(Date.now() - DAY).toISOString();
      const to = new Date(Date.now() + DAY).toISOString();
      const res = await call('get', `/cash/summary?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`, a);

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        sales: 10000,
        collected: 2000,
        cashIn: 12000,
        expenses: 2000,
        paidToSuppliers: 3000,
        cashOut: 5000,
        net: 7000,
        creditGranted: 5000, // dette accordee: pas de mouvement de caisse
        creditReceived: 9000,
      });
      expect(res.body.expensesByCategory).toEqual([
        { category: 'Transport', total: 1500 },
        { category: 'Loyer', total: 500 },
      ]);

      expect((await call('get', `/cash/summary?from=${encodeURIComponent(to)}&to=${encodeURIComponent(from)}`, a)).status).toBe(400);
      expect((await call('get', '/cash/summary', a)).status).toBe(400);
    });

    it('exporte le journal de caisse en CSV', async () => {
      await call('post', '/cash', a, { type: 'SALE', amount: 1500, label: 'Riz', category: 'Alimentation' });
      const res = await call('get', '/export/cash', a);
      expect(res.status).toBe(200);
      expect(res.text).toContain('Date,Nature,Montant (FCFA),Categorie,Libelle');
      expect(res.text).toContain('Vente,1500.00,Alimentation,Riz');
    });
  });

  describe('exports CSV sans injection de formule', () => {
    it("neutralise les cellules commencant par = + - @ (nom d'un client malveillant)", async () => {
      const evil = await call('post', '/customers', a, { name: '=HYPERLINK("http://evil","clic")', phone: '+229 01 67 07 70 27' });
      await call('post', '/debts', a, { customerId: evil.body.id, amount: 100, reason: '@SUM(A1)' });
      const res = await call('get', '/export/history', a);
      expect(res.text).toContain(`"'=HYPERLINK(""http://evil"",""clic"")"`);
      expect(res.text).toContain("'@SUM(A1)");
      expect(res.text).not.toMatch(/(^|,)=HYPERLINK/m);
      expect(res.text).toContain('Type,Nom,Telephone');
      expect(res.text).toContain('Client,');
    });
  });

  describe('consentement', () => {
    it("l'inscription exige la version en vigueur ; l'ancienne version est refusee sans consommer la session OTP", async () => {
      const phone = '+2290167000310';
      const ip = freshIp();
      const otp = await ctx.http().post('/api/v1/auth/otp/request').set('X-Forwarded-For', ip).send({ phone });
      const verified = await ctx.http().post('/api/v1/auth/otp/verify').set('X-Forwarded-For', ip).send({ phone, code: otp.body.devCode });
      const setup = (termsVersion?: string) =>
        ctx.http().post('/api/v1/auth/pin/setup').set('X-Forwarded-For', freshIp()).send({ otpSessionToken: verified.body.otpSessionToken, businessName: 'Neuve', pin: '1234', termsVersion });

      expect((await setup()).status).toBe(400);
      const old = await setup('2020-01-01');
      expect(old.status).toBe(400);
      expect(old.body.message.code).toBe('TERMS_VERSION_MISMATCH');
      expect(await ctx.prisma.consentRecord.count({ where: { user: { phone } } })).toBe(0);

      // La session OTP n'a pas ete consommee : on peut reessayer avec la bonne version.
      const ok = await setup(CURRENT_TERMS_VERSION);
      expect(ok.status).toBe(201);
      const user = await ctx.prisma.user.findUniqueOrThrow({ where: { phone } });
      expect(await ctx.prisma.consentRecord.findMany({ where: { userId: user.id } })).toHaveLength(1);
    });

    it('/auth/me indique si la version en vigueur est acceptee ; re-consentement apres une nouvelle version', async () => {
      const me = await call('get', '/auth/me', a);
      expect(me.body).toMatchObject({ termsVersion: CURRENT_TERMS_VERSION, termsAccepted: true });

      await ctx.prisma.consentRecord.deleteMany({ where: { userId: a.userId } }); // comme si les conditions avaient change
      expect((await call('get', '/auth/me', a)).body.termsAccepted).toBe(false);

      expect((await call('post', '/auth/consent', a, { termsVersion: 'ancienne' })).status).toBe(400);
      const accepted = await call('post', '/auth/consent', a, { termsVersion: CURRENT_TERMS_VERSION });
      expect(accepted.body.termsAccepted).toBe(true);
      await call('post', '/auth/consent', a, { termsVersion: CURRENT_TERMS_VERSION }); // idempotent
      expect(await ctx.prisma.consentRecord.count({ where: { userId: a.userId } })).toBe(1);
    });
  });

  describe("journal d'activite", () => {
    it('consigne connexion, changement de PIN, export, sans IP ni donnee du carnet', async () => {
      await ctx.http().post('/api/v1/auth/login').set('X-Forwarded-For', freshIp()).send({ phone: a.phone, pin: '1234' });
      await call('get', '/auth/export', a);
      await call('post', '/auth/pin/change', a, { currentPin: '1234', newPin: '5678' });

      // Le changement de PIN revoque les anciens jetons : on se reconnecte avec le nouveau PIN.
      const relogin = await ctx.http().post('/api/v1/auth/login').set('X-Forwarded-For', freshIp()).send({ phone: a.phone, pin: '5678' });
      const res = await call('get', '/auth/activity', { ...a, accessToken: relogin.body.accessToken });
      expect(res.status).toBe(200);
      const actions = res.body.map((e: any) => e.action);
      expect(actions).toEqual(expect.arrayContaining(['ACCOUNT_CREATED', 'CONSENT_ACCEPTED', 'LOGIN', 'DATA_EXPORT', 'PIN_CHANGED']));
      for (const entry of res.body) expect(Object.keys(entry).sort()).toEqual(['action', 'createdAt']);
      expect(JSON.stringify(res.body)).not.toMatch(/10\.\d+\.\d+\.\d+/);
    });

    it("n'expose jamais le journal d'un autre commercant", async () => {
      await ctx.http().post('/api/v1/auth/login').set('X-Forwarded-For', freshIp()).send({ phone: b.phone, pin: '1234' });
      const mine = await call('get', '/auth/activity', a);
      expect(mine.body.filter((e: any) => e.action === 'LOGIN')).toHaveLength(0);
    });

    it('la purge quotidienne supprime le journal de plus de 12 mois et les codes SMS expires', async () => {
      await ctx.prisma.auditLog.create({ data: { userId: a.userId, action: 'LOGIN', createdAt: new Date(Date.now() - 400 * DAY) } });
      await ctx.prisma.auditLog.create({ data: { userId: a.userId, action: 'LOGIN', createdAt: new Date(Date.now() - 10 * DAY) } });
      await ctx.prisma.user.update({ where: { id: a.userId }, data: { otpCode: 'abc', otpExpiresAt: new Date(Date.now() - 3 * DAY) } });
      await ctx.prisma.user.update({ where: { id: b.userId }, data: { otpCode: 'def', otpExpiresAt: new Date(Date.now() + 60_000) } });

      const result = await ctx.app.get(RetentionCron).run();

      expect(result).toEqual({ auditLogs: 1, otpResidues: 1 });
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: a.userId } })).otpCode).toBeNull();
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: b.userId } })).otpCode).toBe('def');
      expect(await ctx.prisma.auditLog.count({ where: { createdAt: { lt: new Date(Date.now() - 365 * DAY) } } })).toBe(0);
    });
  });

  describe('export des donnees (acces et portabilite)', () => {
    it('renvoie TOUT ce que Carne conserve sur le commercant, sans le PIN ni les secrets', async () => {
      const client = await call('post', '/customers', a, { name: 'Aicha', phone: '+229 01 67 07 70 27', creditLimit: 20000 });
      const debt = await call('post', '/debts', a, { customerId: client.body.id, amount: 5000, reason: 'Riz' });
      await call('post', '/payments', a, { debtId: debt.body.id, amount: 1000, method: 'CASH' });
      await call('post', '/cash', a, { type: 'SALE', amount: 300 });
      await call('post', '/customers', b, { name: 'Client de B', phone: '+229 01 67 07 70 28' });

      const res = await call('get', '/auth/export', a);

      expect(res.status).toBe(200);
      expect(res.headers['content-disposition']).toMatch(/attachment; filename="carne-mes-donnees-\d{4}-\d{2}-\d{2}\.json"/);
      const data = JSON.parse(res.text);
      expect(data.format).toBe('carne-export-v1');
      expect(data.account).toMatchObject({ phone: a.phone, businessName: 'Boutique A' });
      expect(data.customers).toHaveLength(1);
      expect(data.customers[0]).toMatchObject({ name: 'Aicha', creditLimit: 20000, kind: 'CLIENT' });
      expect(data.customers[0].debts[0]).toMatchObject({ amount: 5000, reason: 'Riz' });
      expect(data.customers[0].debts[0].payments[0]).toMatchObject({ amount: 1000, method: 'CASH' });
      expect(data.cashEntries).toHaveLength(1);
      expect(data.consents[0].version).toBe(CURRENT_TERMS_VERSION);
      const raw = res.text;
      expect(raw).not.toMatch(/pinHash|otpCode|tokenVersion|\$2[aby]\$/);
      expect(raw).not.toContain('Client de B');
    });

    it("exporte les donnees d'un seul client (demande d'acces de cette personne), jamais celles d'un autre commercant", async () => {
      const client = await call('post', '/customers', a, { name: 'Aicha', phone: '+229 01 67 07 70 27' });
      const other = await call('post', '/customers', b, { name: 'Client de B', phone: '+229 01 67 07 70 28' });
      await call('post', '/debts', a, { customerId: client.body.id, amount: 100 });

      const mine = await call('get', `/auth/export/customers/${client.body.id}`, a);
      expect(mine.status).toBe(200);
      expect(mine.body).toMatchObject({ format: 'carne-customer-export-v1', name: 'Aicha' });
      expect(mine.body.debts).toHaveLength(1);
      expect((await call('get', `/auth/export/customers/${other.body.id}`, a)).status).toBe(404);
      expect((await ctx.http().get(`/api/v1/auth/export/customers/${client.body.id}`).set('X-Forwarded-For', freshIp())).status).toBe(401);
    });

    it("limite l'export complet a 5 par heure (429)", async () => {
      const statuses: number[] = [];
      for (let i = 0; i < 6; i += 1) statuses.push((await call('get', '/auth/export', a)).status);
      expect(statuses.slice(0, 5).every((s) => s === 200)).toBe(true);
      expect(statuses[5]).toBe(429);
    });
  });

  describe('administration (pilote)', () => {
    it('accorde, prolonge puis retire Premium par numero, sans route HTTP', async () => {
      expect(await adminRun(['grant-premium', a.phone, '30'], ctx.prisma as any)).toMatch(/Premium jusqu'au/);
      const first = (await ctx.prisma.user.findUniqueOrThrow({ where: { id: a.userId } })).planExpiresAt!;
      expect((await call('get', '/auth/me', a)).body.plan).toBe('PREMIUM');

      await adminRun(['grant-premium', a.phone, '30'], ctx.prisma as any);
      const second = (await ctx.prisma.user.findUniqueOrThrow({ where: { id: a.userId } })).planExpiresAt!;
      expect(Math.round((second.getTime() - first.getTime()) / DAY)).toBe(30); // prolonge, pas de jours perdus

      await adminRun(['revoke-premium', a.phone], ctx.prisma as any);
      expect((await call('get', '/auth/me', a)).body.plan).toBe('FREE');
      expect(JSON.parse(await adminRun(['show', a.phone], ctx.prisma as any))).toMatchObject({ plan: 'FREE', customers: 0, suppliers: 0 });
    });

    it('refuse les arguments invalides et les comptes inconnus', async () => {
      await expect(adminRun(['grant-premium', a.phone, '0'], ctx.prisma as any)).rejects.toThrow(/entre 1 et 730/);
      await expect(adminRun(['grant-premium', a.phone, 'abc'], ctx.prisma as any)).rejects.toThrow();
      await expect(adminRun(['grant-premium', '+22900000000', '30'], ctx.prisma as any)).rejects.toThrow(/Aucun compte/);
      await expect(adminRun(['detruire', a.phone], ctx.prisma as any)).rejects.toThrow(/Commande inconnue/);
    });
  });
});
