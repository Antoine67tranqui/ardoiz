// Contrôles de la vitrine : sécurité (aucun script, aucune ressource externe, CSP stricte),
// accessibilité de base, liens valides et cohérence avec les règles du backend.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const pages = readdirSync(root).filter((f) => f.endsWith('.html'));
const read = (f) => readFileSync(join(root, f), 'utf8');

test('le site contient les pages attendues', () => {
  assert.deepEqual(pages.sort(), ['404.html', 'conditions.html', 'confidentialite.html', 'index.html', 'mentions-legales.html']);
});

for (const page of pages) {
  const html = read(page);

  test(`${page} : structure et accessibilité de base`, () => {
    assert.match(html, /^<!DOCTYPE html>/i);
    assert.match(html, /<html lang="fr">/);
    assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
    assert.match(html, /<title>[^<]{5,}<\/title>/);
    assert.equal((html.match(/<h1[ >]/g) ?? []).length, 1, 'un seul h1');
    for (const img of html.match(/<img\b[^>]*>/g) ?? []) assert.match(img, /\balt="/, `alt manquant : ${img}`);
    assert.match(html, /<main\b/);
  });

  test(`${page} : aucun script, aucun style en ligne, aucune ressource externe`, () => {
    assert.doesNotMatch(html, /<script\b/i);
    assert.doesNotMatch(html, /<iframe\b|<object\b|<embed\b|<form\b/i);
    assert.doesNotMatch(html, /\son[a-z]+\s*=/i, 'pas de gestionnaire en ligne');
    assert.doesNotMatch(html, /\sstyle\s*=/i, 'pas de style en ligne');
    assert.doesNotMatch(html, /<style\b/i);
    // Les seules URL absolues autorisées sont des liens de navigation, pas des ressources chargées.
    for (const m of html.matchAll(/\b(?:src|href)="(https?:)?\/\/[^"]+"/g)) assert.fail(`ressource externe : ${m[0]}`);
  });

  test(`${page} : CSP stricte (rien n'est autorisé hors du site lui-même)`, () => {
    const csp = html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)?.[1];
    assert.ok(csp, 'CSP manquante');
    assert.match(csp, /default-src 'none'/);
    assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval|\*/);
    assert.match(csp, /base-uri 'none'/);
  });

  test(`${page} : liens et ancres valides`, () => {
    for (const m of html.matchAll(/\b(?:href|src)="([^"]+)"/g)) {
      const target = m[1];
      if (/^(mailto:|tel:)/.test(target)) continue;
      const [path, fragment] = target.split('#');
      const file = path === '' || path === './' ? page : path.replace(/^\//, '');
      const full = join(root, file === '' ? 'index.html' : file);
      assert.ok(existsSync(full), `${page} : cible introuvable ${target}`);
      if (fragment) {
        const targetHtml = file.endsWith('.html') ? readFileSync(full, 'utf8') : '';
        assert.match(targetHtml, new RegExp(`\\bid="${fragment}"`), `${page} : ancre #${fragment} introuvable`);
      }
    }
  });

  test(`${page} : ni ancien nom de marque, ni tiret cadratin`, () => {
    assert.doesNotMatch(html, /ardoiz/i);
    assert.doesNotMatch(html, /\u2014/);
  });
}

test('la feuille de style n\'importe rien d\'externe', () => {
  const css = read('styles.css');
  assert.doesNotMatch(css, /@import|url\(\s*["']?https?:/i);
  assert.doesNotMatch(css, /\u2014/);
});

test('les en-têtes _headers reprennent la même CSP que les pages (plus frame-ancestors)', () => {
  const headers = read('_headers');
  const csp = headers.match(/Content-Security-Policy: (.+)/)?.[1];
  assert.ok(csp);
  const meta = read('index.html').match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)[1];
  assert.equal(csp.replace('; frame-ancestors \'none\'', ''), meta);
  for (const h of ['Strict-Transport-Security', 'X-Content-Type-Options: nosniff', 'Referrer-Policy: no-referrer']) assert.ok(headers.includes(h), h);
});

test('les chiffres de la formule correspondent aux règles du backend', () => {
  const constants = readFileSync(join(root, '..', 'ardoiz-backend', 'src', 'subscription', 'plan.constants.ts'), 'utf8');
  const num = (name) => Number(constants.match(new RegExp(`${name}\\s*=\\s*([0-9_]+)`))[1].replaceAll('_', ''));
  const limit = num('FREE_PLAN_CUSTOMER_LIMIT');
  const price = num('PREMIUM_MONTHLY_PRICE_FCFA');
  const days = num('PREMIUM_DURATION_DAYS');

  const html = read('index.html');
  assert.match(html, new RegExp(`Jusqu'à ${limit} clients`));
  assert.ok(html.includes(`${price.toLocaleString('fr-FR').replace(/ | /g, ' ')} FCFA`), 'prix');
  assert.match(html, new RegExp(`pour ${days} jours`));
});

test('les logos existent aux tailles annoncées', () => {
  for (const f of ['logo-512.png', 'logo-192.png', 'apple-touch-icon.png', 'favicon-32.png', 'favicon-48.png']) {
    assert.ok(existsSync(join(root, 'assets', f)), f);
  }
});

test('page de confidentialité : chaque point à compléter est explicite et annoncé', () => {
  const html = read('confidentialite.html');
  assert.match(html, /Version de travail/);
  const placeholders = html.match(/\[à (?:compléter|confirmer)[^\]]*\]/g) ?? [];
  assert.ok(placeholders.length > 0, 'les informations propres à l\'éditeur doivent rester signalées tant qu\'elles manquent');
  // Aucune promesse que le code ne tient pas.
  for (const claim of ['Suppression', 'Exporter l\'historique', 'Supprimer mon compte']) assert.ok(html.includes(claim), claim);
});

const backend = (...p) => readFileSync(join(root, '..', 'ardoiz-backend', 'src', ...p), 'utf8');

test('pages juridiques : version, éditeur et points à compléter signalés', () => {
  const version = backend('common', 'legal.ts').match(/CURRENT_TERMS_VERSION = '([^']+)'/)[1];
  for (const page of ['confidentialite.html', 'conditions.html', 'mentions-legales.html']) {
    const html = read(page);
    assert.match(html, /Version de travail/, page);
    assert.ok(html.includes(`version ${version}`) || html.includes(`Version en vigueur : ${version}`), `${page} : version ${version}`);
    assert.match(html, /CIVORA CONSEIL ET SOLUTIONS/, page);
    assert.match(html, /\[à (?:compléter|confirmer)/, `${page} : aucun point à compléter signalé`);
  }
  // Chaque page du site renvoie vers les trois documents et crédite l'éditeur.
  for (const page of pages) {
    if (page === '404.html') continue;
    const html = read(page);
    for (const target of ['confidentialite.html', 'conditions.html', 'mentions-legales.html']) assert.ok(html.includes(`href="${target}"`), `${page} -> ${target}`);
    assert.match(html, /conçu et développé par CIVORA CONSEIL ET SOLUTIONS/, page);
  }
});

test('la politique de confidentialité ne promet que ce que le code fait', () => {
  const html = read('confidentialite.html');
  const auth = backend('auth', 'auth.service.ts');
  const num = (re) => Number(auth.match(re)[1]);
  assert.match(html, new RegExp(`verrouillage de ${num(/PIN_LOCKOUT_MINUTES = (\d+)/)} minutes après ${num(/MAX_PIN_ATTEMPTS = (\d+)/)} erreurs`));
  assert.match(html, new RegExp(`${num(/OTP_TTL_MINUTES = (\d+)/)} minutes de validité`));
  assert.match(auth, /JWT_REFRESH_EXPIRES_IN'\) \?\? '30d'/);
  assert.match(html, /30 jours au plus, ou jusqu'à votre déconnexion/);
  const days = Number(backend('audit', 'audit.service.ts').match(/AUDIT_RETENTION_DAYS = (\d+)/)[1]);
  assert.equal(days, 365);
  assert.match(html, /Journal d'activité du compte<\/td><td>12 mois/);
  assert.match(html, /La version en ligne n'utilise aucun cookie/);
});

test('les conditions affichent les limites et le prix du serveur', () => {
  const constants = backend('subscription', 'plan.constants.ts');
  const n = (name) => Number(constants.match(new RegExp(`${name}\\s*=\\s*([0-9_]+)`))[1].replaceAll('_', ''));
  const html = read('conditions.html');
  assert.match(html, new RegExp(`jusqu'à ${n('FREE_PLAN_CUSTOMER_LIMIT')} clients`));
  assert.ok(html.includes(`${n('PREMIUM_MONTHLY_PRICE_FCFA').toLocaleString('fr-FR').replace(/[\u202f\u00a0]/g, ' ')} FCFA pour ${n('PREMIUM_DURATION_DAYS')} jours`));
});
