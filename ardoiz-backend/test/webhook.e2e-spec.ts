import { DebtsService } from '../src/debts/debts.service';
import { bearer, createTestApp, freshIp, resetDb, Session, signBody, signUp, TestContext } from './helpers';

describe('Webhook Mobile Money (e2e)', () => {
  let ctx: TestContext;
  let session: Session;
  let debtId: string;

  const postWebhook = (rawBody: string, signature?: string, ip = freshIp()) => {
    const req = ctx
      .http()
      .post('/api/v1/webhooks/mobile-money')
      .set('X-Forwarded-For', ip)
      .set('Content-Type', 'application/json');
    if (signature !== undefined) req.set('x-momo-signature', signature);
    return req.send(rawBody);
  };

  // Corps volontairement non canonique (ordre des cles, espaces) : un vrai
  // agregateur signe ses propres octets, pas une re-serialisation du DTO.
  const bodyFor = (transactionRef: string, amount: number, id = debtId) =>
    `{ "transactionRef": "${transactionRef}",\n  "amount": ${amount}, "debtId": "${id}" }`;

  beforeAll(async () => {
    ctx = await createTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
  });
  beforeEach(async () => {
    await resetDb(ctx.prisma);
    session = await signUp(ctx);
    const customer = await ctx
      .http()
      .post('/api/v1/customers')
      .set('X-Forwarded-For', freshIp())
      .set(bearer(session))
      .send({ name: 'Aicha Traore', phone: '+229 01 67 07 70 27' });
    const debt = await ctx
      .http()
      .post('/api/v1/debts')
      .set('X-Forwarded-For', freshIp())
      .set(bearer(session))
      .send({ customerId: customer.body.id, amount: 5000 });
    debtId = debt.body.id;
  });

  const debtStatus = async () =>
    (await ctx.prisma.debt.findUniqueOrThrow({ where: { id: debtId } })).status;
  const paymentCount = () => ctx.prisma.payment.count();

  it('accepte une signature calculee sur le corps brut non canonique et enregistre le paiement', async () => {
    const raw = bodyFor('TX-1', 2000);
    const res = await postWebhook(raw, signBody(raw));

    expect(res.status).toBe(201);
    expect(await paymentCount()).toBe(1);
    expect(await debtStatus()).toBe('PARTIAL');
  });

  it('marque la dette PAID quand les paiements couvrent le montant', async () => {
    const first = bodyFor('TX-A', 3000);
    const second = bodyFor('TX-B', 2000);
    await postWebhook(first, signBody(first));
    await postWebhook(second, signBody(second));

    expect(await debtStatus()).toBe('PAID');
  });

  it('est idempotent : un rejeu avec la meme reference ne double-compte pas', async () => {
    const raw = bodyFor('TX-REPLAY', 2000);
    const first = await postWebhook(raw, signBody(raw));
    const replay = await postWebhook(raw, signBody(raw));

    expect(first.status).toBe(201);
    expect(replay.status).toBe(201);
    expect(replay.body.id).toBe(first.body.id);
    expect(await paymentCount()).toBe(1);
  });

  it('absorbe des livraisons concurrentes de la meme reference sans erreur 500', async () => {
    const raw = bodyFor('TX-RACE', 1000);
    const signature = signBody(raw);

    const responses = await Promise.all(
      Array.from({ length: 8 }, () => postWebhook(raw, signature)),
    );

    expect(responses.map((r) => r.status).filter((s) => s >= 500)).toEqual([]);
    expect(responses.every((r) => r.status === 201)).toBe(true);
    expect(new Set(responses.map((r) => r.body.id)).size).toBe(1);
    expect(await paymentCount()).toBe(1);
  });

  describe('rejets', () => {
    it('401 sans signature', async () => {
      const res = await postWebhook(bodyFor('TX-NOSIG', 1000));
      expect(res.status).toBe(401);
      expect(await paymentCount()).toBe(0);
    });

    it('401 avec une signature invalide', async () => {
      const res = await postWebhook(bodyFor('TX-BAD', 1000), 'deadbeef');
      expect(res.status).toBe(401);
      expect(await paymentCount()).toBe(0);
    });

    it('401 avec une signature calculee avec un autre secret', async () => {
      const raw = bodyFor('TX-OTHER', 1000);
      const res = await postWebhook(raw, signBody(raw, 'un-autre-secret'));
      expect(res.status).toBe(401);
      expect(await paymentCount()).toBe(0);
    });

    it('401 si la signature couvre le DTO re-serialise et non le corps brut (ancien bug)', async () => {
      const raw = bodyFor('TX-REser', 1000);
      const reserialized = JSON.stringify({ debtId, amount: 1000, transactionRef: 'TX-REser' });
      const res = await postWebhook(raw, signBody(reserialized));
      expect(res.status).toBe(401);
      expect(await paymentCount()).toBe(0);
    });

    it('401 si le corps est modifie apres signature (montant falsifie)', async () => {
      const signed = bodyFor('TX-TAMPER', 100);
      const tampered = bodyFor('TX-TAMPER', 5000);
      const res = await postWebhook(tampered, signBody(signed));
      expect(res.status).toBe(401);
      expect(await paymentCount()).toBe(0);
      expect(await debtStatus()).toBe('PENDING');
    });

    it('400 pour une dette inconnue, avec signature pourtant valide', async () => {
      const raw = bodyFor('TX-GHOST', 1000, '11111111-1111-4111-8111-111111111111');
      const res = await postWebhook(raw, signBody(raw));
      expect(res.status).toBe(400);
      expect(await paymentCount()).toBe(0);
    });

    it('400 pour un montant hors bornes avec signature valide (pas de 500 en base)', async () => {
      const raw = bodyFor('TX-HUGE', 1e12);
      const res = await postWebhook(raw, signBody(raw));
      expect(res.status).toBe(400);
      expect(await paymentCount()).toBe(0);
    });

    it('400 pour un corps invalide (debtId non UUID, montant negatif)', async () => {
      const raw = JSON.stringify({ debtId: 'pas-un-uuid', amount: -5, transactionRef: 'X' });
      const res = await postWebhook(raw, signBody(raw));
      expect(res.status).toBe(400);
    });
  });

  it('limite le webhook a 30 requetes par minute et par IP (429)', async () => {
    const ip = freshIp();
    const statuses: number[] = [];
    for (let i = 0; i < 31; i += 1) {
      const raw = bodyFor(`TX-RL-${i}`, 1);
      statuses.push((await postWebhook(raw, signBody(raw), ip)).status);
    }
    expect(statuses.slice(0, 30).every((s) => s === 201)).toBe(true);
    expect(statuses[30]).toBe(429);
  });

  it('calcule le statut en Decimal exact : 0,10 + 0,70 couvrent bien une dette de 0,80', async () => {
    // En flottant JS, 0.1 + 0.7 = 0.7999999999999999 < 0.8 (dette a tort PARTIAL).
    const customer = await ctx.prisma.customer.findFirstOrThrow();
    const tiny = await ctx.prisma.debt.create({
      data: { customerId: customer.id, amount: '0.80' },
    });
    await ctx.prisma.payment.createMany({
      data: [
        { debtId: tiny.id, amount: '0.10', method: 'CASH' },
        { debtId: tiny.id, amount: '0.70', method: 'CASH' },
      ],
    });

    const updated = await ctx.app.get(DebtsService).recomputeStatus(tiny.id);
    expect(updated.status).toBe('PAID');
  });
});
