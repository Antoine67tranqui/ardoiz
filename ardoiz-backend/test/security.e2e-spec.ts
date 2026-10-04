import { createTestApp, freshIp, TestContext } from './helpers';

describe('Securite HTTP (e2e)', () => {
  let ctx: TestContext;

  beforeAll(async () => {
    ctx = await createTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
  });

  const preflight = (origin: string) =>
    ctx
      .http()
      .options('/api/v1/auth/login')
      .set('X-Forwarded-For', freshIp())
      .set('Origin', origin)
      .set('Access-Control-Request-Method', 'POST');

  it('CORS : autorise une origine de la liste blanche', async () => {
    const res = await preflight('http://allowed.example');
    expect(res.headers['access-control-allow-origin']).toBe('http://allowed.example');
  });

  it("CORS : n'autorise aucune origine inconnue", async () => {
    const res = await preflight('http://evil.example');
    expect(res.headers['access-control-allow-origin']).toBeUndefined();
  });

  it('pose les en-tetes de securite Helmet', async () => {
    const res = await ctx.http().get('/api/v1/health').set('X-Forwarded-For', freshIp());
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['x-powered-by']).toBeUndefined();
  });

  it('expose /health sans authentification et sans limitation de debit', async () => {
    const ip = freshIp();
    const statuses: number[] = [];
    for (let i = 0; i < 70; i += 1) {
      statuses.push((await ctx.http().get('/api/v1/health').set('X-Forwarded-For', ip)).status);
    }
    expect(new Set(statuses)).toEqual(new Set([200]));
  });

  it('applique la limite globale de 60 requetes par minute aux autres routes (429)', async () => {
    const ip = freshIp();
    let last = 0;
    for (let i = 0; i < 61; i += 1) {
      last = (await ctx.http().get('/api/v1/customers').set('X-Forwarded-For', ip)).status;
    }
    expect(last).toBe(429);
  });

  it('refuse les champs inconnus dans un corps de requete (whitelist stricte)', async () => {
    const res = await ctx
      .http()
      .post('/api/v1/auth/login')
      .set('X-Forwarded-For', freshIp())
      .send({ phone: '+2290167000001', pin: '1234', isAdmin: true });
    expect(res.status).toBe(400);
  });
});
