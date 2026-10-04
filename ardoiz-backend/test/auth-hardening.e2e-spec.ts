import * as crypto from 'crypto';
import { NotificationsService } from '../src/notifications/notifications.service';
import { bearer, createTestApp, freshIp, resetDb, signUp, TestContext } from './helpers';

// Le filtre d'exceptions renvoie soit une chaine (HttpException(message)), soit l'objet Nest.
const messageOf = (res: { body: { message: unknown } }): string => {
  const m = res.body.message as string | { message: string };
  return typeof m === 'string' ? m : m.message;
};

describe('Durcissement de l\'authentification (e2e)', () => {
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

  const requestOtp = (phone: string, ip = freshIp()) =>
    ctx.http().post('/api/v1/auth/otp/request').set('X-Forwarded-For', ip).send({ phone });
  const verifyOtp = (phone: string, code: string, ip = freshIp()) =>
    ctx.http().post('/api/v1/auth/otp/verify').set('X-Forwarded-For', ip).send({ phone, code });
  const setupPin = (otpSessionToken: string, pin = '1234', businessName = 'Boutique') =>
    ctx.http().post('/api/v1/auth/pin/setup').set('X-Forwarded-For', freshIp()).send({ otpSessionToken, businessName, pin });
  const login = (phone: string, pin: string) =>
    ctx.http().post('/api/v1/auth/login').set('X-Forwarded-For', freshIp()).send({ phone, pin });

  describe('codes OTP', () => {
    const phone = '+2290167000301';

    it('ne stocke jamais le code en clair (empreinte HMAC liee au numero)', async () => {
      const { body } = await requestOtp(phone);
      const user = await ctx.prisma.user.findUniqueOrThrow({ where: { phone } });

      expect(user.otpCode).not.toBe(body.devCode);
      expect(user.otpCode).toMatch(/^[0-9a-f]{64}$/);
      const secret = process.env.JWT_OTP_SECRET as string;
      expect(user.otpCode).toBe(crypto.createHmac('sha256', secret).update(`${phone}:${body.devCode}`).digest('hex'));
    });

    it('genere des codes a 6 chiffres', async () => {
      const codes = new Set<string>();
      for (let i = 0; i < 5; i += 1) {
        const p = `+22901670031${i}`;
        const { body } = await requestOtp(`${p}0`);
        expect(body.devCode).toMatch(/^\d{6}$/);
        codes.add(body.devCode);
      }
      expect(codes.size).toBeGreaterThan(1);
    });

    it('invalide le code apres 5 essais errones, meme si le bon code est ensuite fourni', async () => {
      const { body } = await requestOtp(phone);
      const wrong = body.devCode === '000000' ? '111111' : '000000';

      for (let i = 0; i < 4; i += 1) {
        const res = await verifyOtp(phone, wrong);
        expect(res.status).toBe(400);
        expect(messageOf(res)).toMatch(/invalide/);
      }
      const fifth = await verifyOtp(phone, wrong);
      expect(fifth.status).toBe(400);
      expect(messageOf(fifth)).toMatch(/Trop d'essais/);

      const correctButBurnt = await verifyOtp(phone, body.devCode);
      expect(correctButBurnt.status).toBe(400);
      expect(messageOf(correctButBurnt)).toMatch(/Aucun code OTP en attente/);
    });

    it('ne laisse pas des essais repartis sur plusieurs IP contourner la limite par compte', async () => {
      const { body } = await requestOtp(phone);
      const wrong = body.devCode === '000000' ? '111111' : '000000';
      for (let i = 0; i < 5; i += 1) await verifyOtp(phone, wrong, freshIp()); // 5 IP differentes

      expect((await verifyOtp(phone, body.devCode, freshIp())).status).toBe(400);
    });

    it('un code ne valide qu\'une fois', async () => {
      const { body } = await requestOtp(phone);
      expect((await verifyOtp(phone, body.devCode)).status).toBe(201);
      expect((await verifyOtp(phone, body.devCode)).status).toBe(400);
    });

    it('applique un delai de 60 s entre deux envois pour un meme numero, meme depuis des IP differentes (429)', async () => {
      expect((await requestOtp(phone, freshIp())).status).toBe(201);
      const again = await requestOtp(phone, freshIp());
      expect(again.status).toBe(429);
      expect(messageOf(again)).toMatch(/Patientez 60 secondes/);
    });

    it('autorise un nouvel envoi une fois le delai ecoule, et le nouveau code remplace l\'ancien', async () => {
      const first = await requestOtp(phone);
      // Simule un code emis il y a 61 s (expiration dans 5 min - 61 s).
      await ctx.prisma.user.update({ where: { phone }, data: { otpExpiresAt: new Date(Date.now() + (300 - 61) * 1000) } });

      const second = await requestOtp(phone);
      expect(second.status).toBe(201);
      if (second.body.devCode !== first.body.devCode) {
        expect((await verifyOtp(phone, first.body.devCode)).status).toBe(400);
      }
      expect((await verifyOtp(phone, second.body.devCode)).status).toBe(201);
    });

    it('gere deux premieres demandes simultanees pour un nouveau numero sans erreur 500', async () => {
      const responses = await Promise.all([requestOtp(phone), requestOtp(phone), requestOtp(phone)]);
      const statuses = responses.map((r) => r.status).sort();
      expect(statuses.filter((s) => s >= 500)).toEqual([]);
      expect(statuses.filter((s) => s === 201)).toHaveLength(1);
      expect(await ctx.prisma.user.count({ where: { phone } })).toBe(1);
    });

    it('renvoie 503 et permet de reessayer immediatement quand le SMS ne part pas', async () => {
      const spy = jest.spyOn(ctx.app.get(NotificationsService), 'sendOtp').mockRejectedValueOnce(new Error('SMS KO'));
      const failed = await requestOtp(phone);
      expect(failed.status).toBe(503);
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { phone } })).otpCode).toBeNull();

      const retry = await requestOtp(phone); // pas de delai de 60 s apres un echec d'envoi
      expect(retry.status).toBe(201);
      spy.mockRestore();
    });
  });

  describe('session OTP et PIN', () => {
    const phone = '+2290167000320';

    const otpSession = async () => {
      const { body } = await requestOtp(phone);
      return (await verifyOtp(phone, body.devCode)).body.otpSessionToken as string;
    };

    it('la session OTP est a usage unique (un jeton vole ne peut pas rejouer la definition du PIN)', async () => {
      const token = await otpSession();
      expect((await setupPin(token, '1234')).status).toBe(201);
      expect((await setupPin(token, '9999')).status).toBe(401);

      expect((await login(phone, '1234')).status).toBe(201);
      expect((await login(phone, '9999')).status).toBe(401);
    });

    it('la reinitialisation du PIN par OTP deverrouille le compte et revoque les sessions ouvertes', async () => {
      const first = await otpSession();
      const tokens = (await setupPin(first, '1234')).body;
      for (let i = 0; i < 5; i += 1) await login(phone, '0000'); // verrouille le compte
      expect((await login(phone, '1234')).status).toBe(401);

      await ctx.prisma.user.update({ where: { phone }, data: { otpExpiresAt: null, otpCode: null } });
      const reset = await otpSession();
      expect((await setupPin(reset, '5678')).status).toBe(201);

      expect((await login(phone, '5678')).status).toBe(201); // deverrouille, nouveau PIN actif
      const oldRefresh = await ctx.http().post('/api/v1/auth/refresh').set('X-Forwarded-For', freshIp()).send({ refreshToken: tokens.refreshToken });
      expect(oldRefresh.status).toBe(401);
      const oldAccess = await ctx.http().get('/api/v1/customers').set('X-Forwarded-For', freshIp()).set('Authorization', `Bearer ${tokens.accessToken}`);
      expect(oldAccess.status).toBe(401);
    });

    it('valide et normalise le nom de la boutique (espaces retires, longueur bornee)', async () => {
      const token = await otpSession();
      expect((await setupPin(token, '1234', '   ')).status).toBe(400);
      expect((await setupPin(token, '1234', 'x'.repeat(101))).status).toBe(400);

      const ok = await setupPin(token, '1234', '  Boutique Fatou  ');
      expect(ok.status).toBe(201);
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { phone } })).businessName).toBe('Boutique Fatou');
    });
  });

  describe('revocation immediate des jetons d\'acces', () => {
    it('un jeton d\'acces ne fonctionne plus des la deconnexion (sans attendre son expiration)', async () => {
      const session = await signUp(ctx, '+2290167000330');
      const get = () => ctx.http().get('/api/v1/customers').set('X-Forwarded-For', freshIp()).set(bearer(session));

      expect((await get()).status).toBe(200);
      await ctx.http().post('/api/v1/auth/logout').set('X-Forwarded-For', freshIp()).set(bearer(session));
      expect((await get()).status).toBe(401);
    });

    it('un changement de PIN revoque les jetons d\'acces des autres appareils', async () => {
      const session = await signUp(ctx, '+2290167000331', 'Boutique', '1234');
      const other = (await login(session.phone, '1234')).body; // second appareil
      await ctx.http().post('/api/v1/auth/pin/change').set('X-Forwarded-For', freshIp()).set(bearer(session)).send({ currentPin: '1234', newPin: '5678' });

      const res = await ctx.http().get('/api/v1/customers').set('X-Forwarded-For', freshIp()).set('Authorization', `Bearer ${other.accessToken}`);
      expect(res.status).toBe(401);
    });
  });

  describe('limitation de debit par utilisateur', () => {
    it('donne a chaque utilisateur connecte son propre compteur, meme derriere une IP partagee', async () => {
      const a = await signUp(ctx, '+2290167000340');
      const b = await signUp(ctx, '+2290167000341');
      const sharedIp = freshIp();
      const hit = (s: typeof a) => ctx.http().get('/api/v1/customers').set('X-Forwarded-For', sharedIp).set(bearer(s));

      const statusesA: number[] = [];
      for (let i = 0; i < 61; i += 1) statusesA.push((await hit(a)).status);
      expect(statusesA.slice(0, 60).every((s) => s === 200)).toBe(true);
      expect(statusesA[60]).toBe(429);

      expect((await hit(b)).status).toBe(200);
    });

    it('ne permet pas d\'echapper a la limite avec des jetons forges (retombe sur l\'IP)', async () => {
      const ip = freshIp();
      const forged = (sub: string) => {
        const part = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
        const signature = crypto.createHmac('sha256', 'pas-le-bon-secret').update(`${part({ alg: 'HS256', typ: 'JWT' })}.${part({ sub })}`).digest('base64url');
        return `${part({ alg: 'HS256', typ: 'JWT' })}.${part({ sub })}.${signature}`;
      };

      let last = 0;
      for (let i = 0; i < 61; i += 1) {
        last = (await ctx.http().get('/api/v1/customers').set('X-Forwarded-For', ip).set('Authorization', `Bearer ${forged(`faux-${i}`)}`)).status;
      }
      expect(last).toBe(429);
    });
  });
});
