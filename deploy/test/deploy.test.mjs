// Contrôles statiques de l'infrastructure : cohérence avec le code, la politique de confidentialité
// et absence de secret dans le dépôt. Lancement : node --test deploy/test/deploy.test.mjs
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (...p) => readFileSync(join(root, ...p), 'utf8');
const caddy = read('deploy', 'Caddyfile');
const compose = read('deploy', 'docker-compose.yml');
const envExample = read('deploy', '.env.production.example');

const metaCsp = (file) => read(...file).match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)[1];
const caddyCsps = [...caddy.matchAll(/header Content-Security-Policy "([^"]+)"/g)].map((m) => m[1]);

test('Caddy envoie les mêmes CSP que les pages (plus frame-ancestors)', () => {
  assert.equal(caddyCsps.length, 2);
  const [app, site] = caddyCsps;
  assert.equal(app, `${metaCsp(['ardoiz-web', 'app', 'index.html'])}; frame-ancestors 'none'`);
  assert.equal(site, `${metaCsp(['ardoiz-web', 'index.html'])}; frame-ancestors 'none'`);
  for (const csp of caddyCsps) assert.doesNotMatch(csp, /unsafe-|\*|https?:/);
});

test('Caddy : en-têtes de sécurité, API relayée, journal sans adresse IP, 30 jours', () => {
  for (const h of ['Strict-Transport-Security', 'X-Content-Type-Options nosniff', 'Referrer-Policy no-referrer', 'X-Frame-Options DENY']) assert.ok(caddy.includes(h), h);
  assert.match(caddy, /reverse_proxy api:3000/);
  for (const field of ['request>remote_ip delete', 'request>client_ip delete', 'request>headers delete']) assert.ok(caddy.includes(field), field);
  assert.match(caddy, /roll_keep_for 720h/); // 30 jours
  assert.match(caddy, /header \/app\/sw\.js Cache-Control "no-cache"/);
});

test('compose : seul le serveur web publie des ports, secrets exigés, migration avant l\'API', () => {
  const services = compose.split(/\n  (?=[a-z]+:\n)/).slice(1);
  const withPorts = services.filter((s) => /\n    ports:/.test(s)).map((s) => s.split(':')[0]);
  assert.deepEqual(withPorts, ['web']);
  assert.match(compose, /DB_PASSWORD:\?/);
  assert.match(compose, /BACKUP_AGE_RECIPIENT:\?/);
  assert.match(compose, /migrate:\n\s+condition: service_completed_successfully/);
  assert.match(compose, /TRUST_PROXY: "1"/);
  assert.match(compose, /NODE_ENV: production/);
});

test('Dockerfile.web ne copie que des fichiers publics existants, jamais les tests', () => {
  const docker = read('deploy', 'Dockerfile.web');
  const copied = [...docker.matchAll(/^COPY (.+) \/srv\/web(?:\/\S*)?$/gm)].flatMap((m) => m[1].split(' '));
  assert.ok(copied.length > 5);
  for (const f of copied) assert.ok(existsSync(join(root, f)), `${f} introuvable`);
  assert.doesNotMatch(docker.split('\n').filter((l) => l.startsWith('COPY')).join('\n'), /test|node_modules|package\.json|_headers/);
});

test('chaque variable lue par le backend est documentée dans .env.production.example ou fixée par compose', () => {
  const used = new Set();
  const walk = (dir) => {
    for (const f of readdirSync(dir)) {
      const full = join(dir, f);
      if (statSync(full).isDirectory()) walk(full);
      else if (f.endsWith('.ts') && !f.endsWith('.spec.ts')) {
        const code = readFileSync(full, 'utf8');
        for (const m of code.matchAll(/(?:config\.get(?:<\w+>)?|process\.env\.|get<string>)\(?\s*'?([A-Z][A-Z0-9_]{3,})/g)) used.add(m[1]);
        for (const m of code.matchAll(/process\.env\.([A-Z][A-Z0-9_]+)/g)) used.add(m[1]);
      }
    }
  };
  walk(join(root, 'ardoiz-backend', 'src'));
  const fixedByCompose = new Set(['NODE_ENV', 'PORT', 'DATABASE_URL', 'TRUST_PROXY', 'CORS_ORIGINS']);
  const documented = new Set([...envExample.matchAll(/^([A-Z][A-Z0-9_]+)=/gm)].map((m) => m[1]));
  const missing = [...used].filter((k) => !documented.has(k) && !fixedByCompose.has(k));
  assert.deepEqual(missing, []);
});

test('.env.production.example ne contient aucune valeur secrète', () => {
  for (const key of ['DB_PASSWORD', 'JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET', 'JWT_OTP_SECRET', 'SMS_API_KEY', 'MOMO_API_KEY', 'MOMO_WEBHOOK_SECRET', 'BACKUP_AGE_RECIPIENT']) {
    assert.match(envExample, new RegExp(`^${key}=$`, 'm'), key);
  }
});

test('la durée de sauvegarde est celle annoncée dans la politique de confidentialité', () => {
  assert.match(compose, /BACKUP_KEEP_DAYS: "30"/);
  assert.match(read('ardoiz-web', 'confidentialite.html'), /Copies de sauvegarde du serveur<\/td><td>30 jours au plus/);
  assert.match(read('deploy', 'backup', 'backup.sh'), /-mmin/);
});

test('aucune clé ni aucun secret réel dans les fichiers versionnés', () => {
  const files = execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8' }).split('\n').filter(Boolean)
    .filter((f) => !/\.(png|jpg|ico|jar|lock)$/.test(f) && !f.endsWith('package-lock.json'));
  const patterns = [
    [/\bsk_(?:live|sandbox)_[A-Za-z0-9_]{12,}/, 'clé secrète de paiement'],
    [/\bpk_(?:live|sandbox)_[A-Za-z0-9_]{12,}/, 'clé publique de paiement'],
    [/-----BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY-----/, 'clé privée'],
    [/AGE-SECRET-KEY-1[A-Z0-9]{20,}/, 'clé privée age'],
    [/\bAKIA[0-9A-Z]{16}\b/, 'clé AWS'],
    [/\bAIza[0-9A-Za-z_-]{35}\b/, 'clé API Google'],
  ];
  const found = [];
  for (const f of files) {
    if (!existsSync(join(root, f))) continue;
    const text = readFileSync(join(root, f), 'utf8');
    for (const [re, label] of patterns) if (re.test(text)) found.push(`${f} : ${label}`);
  }
  assert.deepEqual(found, []);
});

test('le dépôt exclut les fichiers de secrets', () => {
  const ignore = read('.gitignore');
  for (const entry of ['deploy/.env', 'key.properties', '*.jks', '*.keystore', '*.age']) assert.ok(ignore.includes(entry), entry);
});
