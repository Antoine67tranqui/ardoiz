import { createTestApp, freshIp, resetDb, signUp, bearer, TestContext } from './helpers';

describe('Auth (e2e)', () => {
  const login = (phone: string, pin: string) =>
    ctx.http().post('/api/v1/auth/login').set('X-Forwarded-For', freshIp()).send({ phone, pin });

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

  it('parcours complet : OTP, verification, PIN, connexion', async () => {
    const phone = '+2290167000010';
    const session = await signUp(ctx, phone, 'Boutique Fatou', '4321');
    expect(session.accessToken).toBeDefined();
    expect(session.refreshToken).toBeDefined();

    const login = await ctx
      .http()
      .post('/api/v1/auth/login')
      .set('X-Forwarded-For', freshIp())
      .send({ phone, pin: '4321' });
    expect(login.status).toBe(201);
    expect(login.body.accessToken).toBeDefined();

    // Le PIN n'est jamais stocke en clair.
    const user = await ctx.prisma.user.findUniqueOrThrow({ where: { phone } });
    expect(user.pinHash).not.toContain('4321');
    expect(user.businessName).toBe('Boutique Fatou');
  });

  it('rejette un code OTP errone et un numero invalide', async () => {
    const phone = '+2290167000011';
    const ip = freshIp();
    await ctx.http().post('/api/v1/auth/otp/request').set('X-Forwarded-For', ip).send({ phone });

    const wrong = await ctx
      .http()
      .post('/api/v1/auth/otp/verify')
      .set('X-Forwarded-For', ip)
      .send({ phone, code: '000000' });
    expect(wrong.status).toBe(400);

    const invalid = await ctx
      .http()
      .post('/api/v1/auth/otp/request')
      .set('X-Forwarded-For', freshIp())
      .send({ phone: 'pas-un-numero' });
    expect(invalid.status).toBe(400);
  });

  it('rejette un OTP expire', async () => {
    const phone = '+2290167000012';
    const ip = freshIp();
    const otp = await ctx.http().post('/api/v1/auth/otp/request').set('X-Forwarded-For', ip).send({ phone });
    await ctx.prisma.user.update({ where: { phone }, data: { otpExpiresAt: new Date(Date.now() - 1000) } });

    const res = await ctx
      .http()
      .post('/api/v1/auth/otp/verify')
      .set('X-Forwarded-For', ip)
      .send({ phone, code: otp.body.devCode });
    expect(res.status).toBe(400);
  });

  it("n'accepte pas un jeton d'acces comme jeton de session OTP (secrets distincts)", async () => {
    const session = await signUp(ctx, '+2290167000013');
    const res = await ctx
      .http()
      .post('/api/v1/auth/pin/setup')
      .set('X-Forwarded-For', freshIp())
      .send({ otpSessionToken: session.accessToken, businessName: 'Pirate', pin: '9999' });
    expect(res.status).toBe(401);
  });

  describe('refresh tokens', () => {
    it('renouvelle les jetons avec un refresh token valide', async () => {
      const session = await signUp(ctx, '+2290167000020');
      const res = await ctx
        .http()
        .post('/api/v1/auth/refresh')
        .set('X-Forwarded-For', freshIp())
        .send({ refreshToken: session.refreshToken });
      expect(res.status).toBe(201);
      expect(res.body.accessToken).toBeDefined();
    });

    it('un refresh token ne fonctionne plus apres la deconnexion', async () => {
      const session = await signUp(ctx, '+2290167000021');

      const logout = await ctx
        .http()
        .post('/api/v1/auth/logout')
        .set('X-Forwarded-For', freshIp())
        .set(bearer(session));
      expect(logout.status).toBe(201);

      const res = await ctx
        .http()
        .post('/api/v1/auth/refresh')
        .set('X-Forwarded-For', freshIp())
        .send({ refreshToken: session.refreshToken });
      expect(res.status).toBe(401);
    });

    it('un changement de PIN invalide les refresh tokens existants', async () => {
      const session = await signUp(ctx, '+2290167000022', 'Boutique', '1234');

      const change = await ctx
        .http()
        .post('/api/v1/auth/pin/change')
        .set('X-Forwarded-For', freshIp())
        .set(bearer(session))
        .send({ currentPin: '1234', newPin: '5678' });
      expect(change.status).toBe(201);

      const stale = await ctx
        .http()
        .post('/api/v1/auth/refresh')
        .set('X-Forwarded-For', freshIp())
        .send({ refreshToken: session.refreshToken });
      expect(stale.status).toBe(401);

      // Le nouveau PIN fonctionne, l'ancien non.
      const ok = await ctx
        .http()
        .post('/api/v1/auth/login')
        .set('X-Forwarded-For', freshIp())
        .send({ phone: session.phone, pin: '5678' });
      expect(ok.status).toBe(201);
      const ko = await ctx
        .http()
        .post('/api/v1/auth/login')
        .set('X-Forwarded-For', freshIp())
        .send({ phone: session.phone, pin: '1234' });
      expect(ko.status).toBe(401);
    });

    it('un PIN actuel incorrect renvoie 400 (et non 401, reserve a la session) sans rien modifier', async () => {
      const session = await signUp(ctx, '+2290167000024', 'Boutique', '1234');
      const res = await ctx
        .http()
        .post('/api/v1/auth/pin/change')
        .set('X-Forwarded-For', freshIp())
        .set(bearer(session))
        .send({ currentPin: '0000', newPin: '5678' });
      expect(res.status).toBe(400);

      const stillValid = await ctx.http().get('/api/v1/auth/me').set('X-Forwarded-For', freshIp()).set(bearer(session));
      expect(stillValid.status).toBe(200);
      expect((await login(session.phone, '1234')).status).toBe(201);
    });

    it('rejette un refresh token forge ou un jeton d\'acces', async () => {
      const session = await signUp(ctx, '+2290167000023');
      const forged = await ctx
        .http()
        .post('/api/v1/auth/refresh')
        .set('X-Forwarded-For', freshIp())
        .send({ refreshToken: 'abc.def.ghi' });
      expect(forged.status).toBe(401);

      const withAccess = await ctx
        .http()
        .post('/api/v1/auth/refresh')
        .set('X-Forwarded-For', freshIp())
        .send({ refreshToken: session.accessToken });
      expect(withAccess.status).toBe(401);
    });
  });

  describe('verrouillage et limitation de debit', () => {
    it('verrouille le compte apres 5 PIN errones, meme ensuite avec le bon PIN', async () => {
      const session = await signUp(ctx, '+2290167000030', 'Boutique', '1234');
      for (let i = 0; i < 5; i += 1) {
        const res = await ctx
          .http()
          .post('/api/v1/auth/login')
          .set('X-Forwarded-For', freshIp())
          .send({ phone: session.phone, pin: '0000' });
        expect(res.status).toBe(401);
      }
      const locked = await ctx
        .http()
        .post('/api/v1/auth/login')
        .set('X-Forwarded-For', freshIp())
        .send({ phone: session.phone, pin: '1234' });
      expect(locked.status).toBe(401);
      expect(JSON.stringify(locked.body.message)).toMatch(/tentatives/);
    });

    it('limite les demandes d\'OTP a 10 par 5 minutes et par IP (429)', async () => {
      const ip = freshIp();
      const statuses: number[] = [];
      for (let i = 0; i < 11; i += 1) {
        const res = await ctx
          .http()
          .post('/api/v1/auth/otp/request')
          .set('X-Forwarded-For', ip)
          .send({ phone: `+22901670010${String(i).padStart(2, '0')}` });
        statuses.push(res.status);
      }
      expect(statuses.slice(0, 10).every((s) => s === 201)).toBe(true);
      expect(statuses[10]).toBe(429);
    });

    it('limite les tentatives de connexion a 10 par minute et par IP (429)', async () => {
      const ip = freshIp();
      let lastStatus = 0;
      for (let i = 0; i < 11; i += 1) {
        const res = await ctx
          .http()
          .post('/api/v1/auth/login')
          .set('X-Forwarded-For', ip)
          .send({ phone: `+229016700005${i % 10}`, pin: '0000' });
        lastStatus = res.status;
      }
      expect(lastStatus).toBe(429);
    });
  });

  describe('profil', () => {
    it('renvoie le profil du commercant connecte, avec le plan reellement actif', async () => {
      const session = await signUp(ctx, '+2290167000060', 'Boutique Fatou');
      const get = () => ctx.http().get('/api/v1/auth/me').set('X-Forwarded-For', freshIp()).set(bearer(session));

      expect((await get()).body).toEqual({
        id: session.userId,
        phone: session.phone,
        businessName: 'Boutique Fatou',
        plan: 'FREE',
        planExpiresAt: null,
      });

      await ctx.prisma.user.update({ where: { id: session.userId }, data: { plan: 'PREMIUM', planExpiresAt: new Date(Date.now() + 86400000) } });
      expect((await get()).body.plan).toBe('PREMIUM');
      await ctx.prisma.user.update({ where: { id: session.userId }, data: { planExpiresAt: new Date(Date.now() - 1000) } });
      expect((await get()).body).toMatchObject({ plan: 'FREE', planExpiresAt: null });
    });

    it('modifie le nom de la boutique (valide, normalise) et exige un jeton', async () => {
      const session = await signUp(ctx, '+2290167000061', 'Ancien nom');
      const patch = (body: object) =>
        ctx.http().patch('/api/v1/auth/me').set('X-Forwarded-For', freshIp()).set(bearer(session)).send(body);

      expect((await patch({ businessName: '  Nouveau nom  ' })).body.businessName).toBe('Nouveau nom');
      expect((await patch({ businessName: '   ' })).status).toBe(400);
      expect((await patch({ businessName: 'x'.repeat(101) })).status).toBe(400);
      expect((await patch({ businessName: 'Ok', plan: 'PREMIUM' })).status).toBe(400); // pas d'auto-promotion
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: session.userId } })).plan).toBe('FREE');

      expect((await ctx.http().get('/api/v1/auth/me').set('X-Forwarded-For', freshIp())).status).toBe(401);
    });
  });

  it('exige un jeton valide sur les routes protegees', async () => {
    const none = await ctx.http().get('/api/v1/customers').set('X-Forwarded-For', freshIp());
    expect(none.status).toBe(401);
    const bad = await ctx
      .http()
      .get('/api/v1/customers')
      .set('X-Forwarded-For', freshIp())
      .set('Authorization', 'Bearer n.importe.quoi');
    expect(bad.status).toBe(401);
  });
});
