// Contrôles statiques et unitaires du client web en ligne (sans navigateur).
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatMoney, parseAmount, moneyInput, toCents, validate, initials, fold, endOfLocalDay, dateInputValue, relativeDays } from '../app/js/format.js';
import { debtView, partyBalance, periodRange, activityLabel } from '../app/js/model.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const app = join(root, 'app');

const read = (p) => readFileSync(join(app, p), 'utf8');
function files(dir) {
  return readdirSync(dir).flatMap((f) => (statSync(join(dir, f)).isDirectory() ? files(join(dir, f)) : [join(dir, f)]));
}
const sources = files(app).filter((f) => f.endsWith('.js') || f.endsWith('.html') || f.endsWith('.css'));

test('aucun innerHTML, eval ni écriture de HTML dans le client', () => {
  for (const f of sources.filter((s) => s.endsWith('.js'))) {
    const code = readFileSync(f, 'utf8');
    for (const banned of [/innerHTML/, /outerHTML/, /insertAdjacentHTML/, /document\.write/, /\beval\(/, /new Function\(/, /setAttribute\(\s*['"]style['"]/, /\.srcdoc/]) {
      assert.doesNotMatch(code, banned, `${f} : ${banned}`);
    }
  }
});

test('index.html : CSP stricte, aucun script ni style en ligne, une seule balise script externe', () => {
  const html = read('index.html');
  const csp = html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)[1];
  assert.match(csp, /default-src 'none'/);
  assert.match(csp, /script-src 'self'/);
  assert.match(csp, /connect-src 'self'/);
  assert.match(csp, /base-uri 'none'/);
  assert.doesNotMatch(csp, /unsafe-|\*|https?:/);
  assert.doesNotMatch(html, /\son[a-z]+\s*=|\sstyle\s*=|<style\b/i);
  assert.deepEqual(html.match(/<script\b[^>]*>/g), ['<script type="module" src="js/main.js">']);
  for (const m of html.matchAll(/\b(?:src|href)="(https?:)?\/\/[^"]+"/g)) assert.fail(`ressource externe : ${m[0]}`);
});

test('chaque import relatif résout vers un fichier existant', () => {
  for (const f of sources.filter((s) => s.endsWith('.js'))) {
    for (const m of readFileSync(f, 'utf8').matchAll(/from '(\.[^']+)'/g)) {
      assert.ok(existsSync(resolve(dirname(f), m[1])), `${f} : ${m[1]} introuvable`);
    }
  }
});

test('le service worker met en cache exactement les fichiers de la coque, et jamais l\'API', () => {
  const sw = read('sw.js');
  const listed = [...sw.matchAll(/'\.\/([^']*)'/g)].map((m) => m[1]).filter((p) => p !== '');
  for (const p of listed) assert.ok(existsSync(join(app, p)), `sw.js : ${p} inexistant`);
  const modules = files(join(app, 'js')).map((f) => f.slice(app.length + 1)).concat(['config.js', 'app.css', 'index.html', 'manifest.webmanifest']);
  for (const m of modules) assert.ok(listed.includes(m), `sw.js : ${m} absent de la coque`);
  assert.match(sw, /pathname\.startsWith\('\/api\/'\)\) return/);
});

test('la version des conditions est celle du serveur', () => {
  const legal = readFileSync(join(root, '..', 'ardoiz-backend', 'src', 'common', 'legal.ts'), 'utf8');
  const server = legal.match(/CURRENT_TERMS_VERSION = '([^']+)'/)[1];
  assert.match(read('config.js'), new RegExp(`TERMS_VERSION = '${server}'`));
  const dart = readFileSync(join(root, '..', 'ardoiz-app', 'lib', 'core', 'legal.dart'), 'utf8');
  assert.ok(dart.includes(server), 'version de l\'application mobile différente');
});

test('la limite gratuite affichée est celle du serveur', () => {
  const constants = readFileSync(join(root, '..', 'ardoiz-backend', 'src', 'subscription', 'plan.constants.ts'), 'utf8');
  const limit = Number(constants.match(/FREE_PLAN_CUSTOMER_LIMIT\s*=\s*(\d+)/)[1]);
  assert.match(read('config.js'), new RegExp(`FREE_PLAN_LIMIT = ${limit}`));
});

test('ni ancien nom de marque ni tiret cadratin dans le client', () => {
  for (const f of sources) {
    const code = readFileSync(f, 'utf8');
    assert.doesNotMatch(code, /ardoiz/i, f);
    assert.doesNotMatch(code, /—/, f);
  }
});

test('le client mentionne CIVORA et renvoie vers les pages légales', () => {
  const html = read('index.html');
  assert.match(html, /CIVORA Conseil et Solutions/);
  for (const page of ['confidentialite.html', 'conditions.html', 'mentions-legales.html']) assert.ok(html.includes(`../${page}`), page);
  assert.ok(html.includes('../assets/civora-logo.png'));
  assert.ok(existsSync(join(root, 'assets', 'civora-logo.png')));
});

// ---- Montants ----
test('formatMoney : milliers, centimes, négatif', () => {
  const T = '\u202f'; // espace fine insécable (milliers)
  const N = '\u00a0'; // espace insécable avant l'unité
  assert.equal(formatMoney(250_000), `2${T}500${N}FCFA`);
  assert.equal(formatMoney(125_050), `1${T}250,50${N}FCFA`);
  assert.equal(formatMoney(-1_000), `-10${N}FCFA`);
  assert.equal(formatMoney(0), `0${N}FCFA`);
  assert.equal(formatMoney(123_456_700, { currency: false }), `1${T}234${T}567`);
});

test('parseAmount : formats de saisie courants, refus du reste', () => {
  assert.equal(parseAmount('2 500'), 250_000);
  assert.equal(parseAmount('1250,5'), 125_050);
  assert.equal(parseAmount('1250.50'), 125_050);
  assert.equal(parseAmount('0'), 0);
  for (const bad of ['', 'abc', '-5', '1,234,5', '12.345', '1e5', '10 000 000 000', null]) assert.equal(parseAmount(bad), null, String(bad));
  assert.equal(moneyInput(125_050), '1250,50');
  assert.equal(moneyInput(250_000), '2500');
  assert.equal(toCents('2500.10'), 250_010);
  assert.equal(toCents(0.1 + 0.2), 30);
});

test('validations : mêmes règles que le serveur', () => {
  assert.equal(validate.name(' A '), 'Le nom doit comporter au moins 2 caractères.');
  assert.equal(validate.name('Aïcha'), null);
  assert.equal(validate.customerPhone('+229 01 67 07 70 27'), null);
  assert.ok(validate.customerPhone('12'));
  assert.equal(validate.accountPhone('+229 01 67 07 70 27'), null);
  assert.ok(validate.accountPhone('0167077027'));
  assert.equal(validate.pin('1234'), null);
  assert.ok(validate.pin('123'));
  assert.ok(validate.pin('12a4'));
  assert.equal(validate.otp('123456'), null);
  assert.ok(validate.amount('abc'));
  assert.ok(validate.amount('0'));
  assert.equal(validate.amount('500', 50_000), null);
  assert.ok(validate.amount('501', 50_000));
  assert.equal(validate.optionalAmount(''), null);
});

test('dates : fin de journée locale, valeur de champ, jours relatifs', () => {
  const end = endOfLocalDay('2026-10-10');
  assert.equal(end.getHours(), 23);
  assert.equal(dateInputValue(end), '2026-10-10');
  const now = new Date(2026, 9, 10, 15);
  assert.equal(relativeDays(new Date(2026, 9, 11), now), 'demain');
  assert.equal(relativeDays(new Date(2026, 9, 7), now), 'il y a 3 jours');
  assert.equal(initials('Aïcha Traoré'), 'AT');
  assert.equal(initials('  '), '?');
  assert.equal(fold('Éléonore'), 'eleonore');
});

// ---- Modèle ----
test('debtView : reste, statut et retard (échéance courue jusqu\'à la fin du jour)', () => {
  const now = new Date(2026, 9, 12, 10);
  const base = { amount: '2500.00', payments: [], createdAt: now.toISOString() };
  assert.deepEqual(pick(debtView(base, now)), { outstanding: 250_000, paid: 0, status: 'PENDING', overdueDays: 0 });
  const partial = debtView({ ...base, payments: [{ amount: '1000.00', paidAt: now.toISOString() }] }, now);
  assert.deepEqual(pick(partial), { outstanding: 150_000, paid: 100_000, status: 'PARTIAL', overdueDays: 0 });
  const paid = debtView({ ...base, payments: [{ amount: '2500.00' }], dueDate: new Date(2026, 8, 1).toISOString() }, now);
  assert.deepEqual(pick(paid), { outstanding: 0, paid: 250_000, status: 'PAID', overdueDays: 0 });
  // Échéance le 10 : encore valable le 10, en retard de 1 jour le 11, de 2 jours le 12.
  const due = new Date(2026, 9, 10, 12).toISOString();
  assert.equal(debtView({ ...base, dueDate: due }, new Date(2026, 9, 10, 23, 30)).overdueDays, 0);
  assert.equal(debtView({ ...base, dueDate: due }, new Date(2026, 9, 11, 8)).overdueDays, 1);
  assert.equal(debtView({ ...base, dueDate: due }, now).overdueDays, 2);
  assert.equal(partyBalance([debtView(base, now), partial]), 400_000);
});
const pick = ({ outstanding, paid, status, overdueDays }) => ({ outstanding, paid, status, overdueDays });

test('periodRange : jour, semaine (lundi) et mois', () => {
  const wed = new Date(2026, 9, 7, 15);
  const [d0, d1] = periodRange('today', wed);
  assert.deepEqual([d0.getDate(), d1.getDate()], [7, 8]);
  const [w0, w1] = periodRange('week', wed);
  assert.deepEqual([w0.getDate(), w1.getDate()], [5, 12]);
  const [m0, m1] = periodRange('month', wed);
  assert.deepEqual([m0.getMonth(), m0.getDate(), m1.getMonth(), m1.getDate()], [9, 1, 10, 1]);
  assert.equal(activityLabel('LOGIN'), 'Connexion');
  assert.equal(activityLabel('INCONNU'), 'Activité du compte');
});
