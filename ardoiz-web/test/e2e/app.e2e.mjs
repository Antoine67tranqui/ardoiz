// Recette de bout en bout du client web : vrai navigateur (Chromium), vrai backend, vraie base.
// Lancement : voir README (backend sur 127.0.0.1:3998 avec NODE_ENV!=production pour recevoir le code SMS simulé).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer } from './server.mjs';

const { chromium } = await import(process.env.PLAYWRIGHT_PATH ?? 'playwright');
let site; let browser;
let base;
let counter = Math.floor(Math.random() * 200) + 20;

before(async () => {
  site = await startServer({ backend: process.env.BACKEND_URL ?? 'http://127.0.0.1:3998' });
  base = `http://127.0.0.1:${site.port}`;
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
});
after(async () => { await browser?.close(); site?.server.close(); });

// Préfixe d'un numéro béninois valide pour la validation du serveur ; 6 chiffres aléatoires pour éviter les collisions.
const phone = () => `+2290167${String(Math.floor(Math.random() * 1e6)).padStart(6, '0')}`;

async function newPage() {
  const context = await browser.newContext({ locale: 'fr-FR', extraHTTPHeaders: { 'x-e2e-ip': `10.9.${Math.floor(counter / 250)}.${counter++ % 250}` } });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  const problems = [];
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('console', (m) => { if (['error', 'warning'].includes(m.type())) problems.push(`console ${m.type()}: ${m.text()}`); });
  page.problems = problems;
  return page;
}

async function signUp(page, { business = 'Boutique Test', pin = '1234' } = {}) {
  const number = phone();
  await page.goto(`${base}/app/index.html#/inscription`);
  await page.getByLabel('Votre numéro de téléphone').fill(number);
  await page.getByRole('button', { name: 'Recevoir le code par SMS' }).click();
  const hint = await page.getByRole('note').textContent();
  const code = hint.match(/(\d{6})/)[1];
  await page.getByLabel(/Code reçu par SMS/).fill(code);
  await page.getByRole('button', { name: 'Vérifier' }).click();
  await page.getByLabel('Nom de votre boutique').fill(business);
  await page.getByLabel('Code PIN (4 chiffres)').fill(pin);
  await page.getByLabel('Confirmez le code PIN').fill(pin);
  // Sans consentement, aucun compte n'est créé.
  await page.getByRole('button', { name: 'Créer mon compte' }).click();
  await page.getByText('Vous devez accepter pour continuer.').waitFor();
  await page.getByLabel(/J'ai lu et j'accepte/).check();
  await page.getByRole('button', { name: 'Créer mon compte' }).click();
  await page.getByRole('heading', { name: 'Clients' }).waitFor();
  return number;
}

test('inscription, ajout d\'un client, d\'une ardoise et d\'un remboursement', async () => {
  const page = await newPage();
  await signUp(page);
  assert.equal(await page.locator('#business').textContent(), 'Boutique Test');

  await page.getByRole('link', { name: 'Ajouter un client' }).first().click();
  await page.getByLabel('Nom').fill('Aïcha Traoré');
  await page.getByLabel('Téléphone').fill('+229 01 67 07 70 27');
  await page.getByRole('button', { name: 'Ajouter un client' }).click();
  await page.getByRole('heading', { name: 'Aïcha Traoré' }).waitFor();

  await page.getByRole('link', { name: 'Nouvelle ardoise' }).click();
  await page.getByLabel('Montant (FCFA)').fill('2 500');
  await page.getByLabel(/Motif/).fill('Riz et huile');
  await page.getByRole('button', { name: 'Dans 7 jours' }).click();
  await page.getByRole('button', { name: 'Nouvelle ardoise' }).click();
  await page.getByRole('heading', { name: 'Riz et huile' }).waitFor();
  assert.match(await page.locator('.balance .big').textContent(), /2\s?500\s?FCFA/);

  await page.getByLabel('Montant reçu (FCFA)').fill('1000');
  await page.getByRole('button', { name: 'Enregistrer le remboursement' }).click();
  await page.getByText('Partielle').waitFor();
  assert.match(await page.locator('.balance .big').textContent(), /1\s?500\s?FCFA/);

  // Un remboursement supérieur au solde est refusé avant tout envoi.
  await page.getByLabel('Montant reçu (FCFA)').fill('9999');
  await page.getByRole('button', { name: 'Enregistrer le remboursement' }).click();
  await page.getByText('Le montant dépasse le solde restant.').waitFor();

  await page.getByRole('button', { name: 'Tout solder' }).click();
  await page.getByRole('button', { name: 'Enregistrer le remboursement' }).click();
  await page.getByText('Soldée').first().waitFor();
  assert.deepEqual(page.problems, []);
});

test('un nom hostile s\'affiche comme du texte et ne s\'exécute jamais (XSS)', async () => {
  const page = await newPage();
  await signUp(page);
  const evil = '<img src=x onerror="window.__pwned=1"><script>window.__pwned=1</script>';
  await page.goto(`${base}/app/index.html#/clients/nouveau`);
  await page.getByLabel('Nom').fill(evil);
  await page.getByLabel('Téléphone').fill('+229 01 67 07 70 28');
  await page.getByRole('button', { name: 'Ajouter un client' }).click();
  await page.getByRole('heading', { level: 1 }).filter({ hasText: '<img' }).waitFor();
  await page.goto(`${base}/app/index.html#/clients`);
  await page.getByText('<img src=x', { exact: false }).first().waitFor();
  assert.equal(await page.evaluate(() => window.__pwned), undefined);
  assert.equal(await page.locator('main img').count(), 0);
});

test('la CSP bloque un script injecté et toute requête vers un autre domaine', async () => {
  const page = await newPage();
  await page.goto(`${base}/app/index.html#/connexion`);
  const violations = await page.evaluate(() => new Promise((resolve) => {
    const seen = [];
    document.addEventListener('securitypolicyviolation', (e) => seen.push(e.violatedDirective));
    const script = document.createElement('script');
    script.textContent = 'window.__csp = 1';
    document.head.append(script);
    fetch('https://example.org/x').catch(() => {});
    document.body.setAttribute('style', 'color:red');
    setTimeout(() => resolve({ seen, ran: window.__csp === 1 }), 400);
  }));
  assert.equal(violations.ran, false);
  assert.ok(violations.seen.some((d) => d.startsWith('script-src')), JSON.stringify(violations));
  assert.ok(violations.seen.some((d) => d.startsWith('connect-src')), JSON.stringify(violations));
});

test('fournisseurs et caisse : la trésorerie distingue ventes, dépenses et paiements', async () => {
  const page = await newPage();
  await signUp(page);
  await page.getByRole('link', { name: 'Fournisseurs' }).click();
  await page.getByRole('link', { name: 'Ajouter un fournisseur' }).first().click();
  await page.getByLabel('Nom').fill('Grossiste Cotonou');
  await page.getByLabel('Téléphone').fill('+229 01 55 55 55 55');
  await page.getByRole('button', { name: 'Ajouter un fournisseur' }).click();
  await page.getByRole('link', { name: 'Nouvel achat à crédit' }).click();
  await page.getByLabel('Montant (FCFA)').fill('10000');
  await page.getByRole('button', { name: 'Nouvel achat à crédit' }).click();
  await page.getByLabel('Montant payé (FCFA)').fill('4000');
  await page.getByRole('button', { name: 'Enregistrer le paiement' }).click();
  await page.getByText('Partielle').waitFor();

  await page.getByRole('link', { name: 'Caisse' }).click();
  await page.getByRole('button', { name: 'Noter une vente ou une dépense' }).click();
  await page.getByLabel('Montant (FCFA)').fill('7000');
  await page.getByRole('button', { name: 'Enregistrer' }).click();
  await page.getByText('Vente').first().waitFor();
  await page.getByRole('button', { name: 'Noter une vente ou une dépense' }).click();
  await page.getByRole('radio', { name: 'Dépense' }).click();
  await page.getByLabel('Montant (FCFA)').fill('1500');
  await page.getByRole('button', { name: 'Enregistrer' }).click();
  await page.waitForFunction(() => document.body.innerText.includes('Dépense ·'));
  // 7 000 de ventes, moins 1 500 de dépenses, moins 4 000 payés au fournisseur = 1 500.
  const net = await page.locator('.balance .big').textContent();
  assert.match(net, /1\s?500\s?FCFA/);
});

test('connexion, mauvais PIN, déconnexion, session reprise à l\'ouverture', async () => {
  const page = await newPage();
  const number = await signUp(page);
  await page.getByRole('link', { name: 'Réglages' }).click();
  await page.getByRole('button', { name: 'Me déconnecter' }).click();
  await page.getByRole('heading', { name: 'Connexion' }).waitFor();

  await page.getByLabel('Votre numéro de téléphone').fill(number);
  await page.getByLabel('Code PIN (4 chiffres)').fill('9999');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.getByRole('alert').filter({ hasText: 'Numéro de téléphone ou code PIN incorrect.' }).waitFor();

  await page.getByLabel('Code PIN (4 chiffres)').fill('1234');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.getByRole('heading', { name: 'Clients' }).waitFor();

  // Rechargement de l'onglet : le jeton de rafraîchissement (sessionStorage) rouvre la session.
  await page.reload();
  await page.getByRole('heading', { name: 'Clients' }).waitFor();
  // Le jeton d'accès n'est jamais écrit dans le stockage du navigateur.
  const stored = await page.evaluate(() => JSON.stringify({ l: { ...localStorage }, s: { ...sessionStorage } }));
  assert.ok(!/eyJ[\w-]+\.eyJ[\w-]+\.[\w-]+/.test(stored.replace(/carne_refresh_token":"[^"]+"/, '')), 'jeton d\'accès dans le stockage');
  assert.deepEqual(await page.evaluate(() => Object.keys(localStorage)), []);
});

test('bilan réservé à Premium, réglages, journal d\'activité, export et suppression du compte', async () => {
  const page = await newPage();
  const number = await signUp(page);
  await page.getByRole('link', { name: 'Bilan' }).click();
  await page.getByText('Le bilan est réservé à la formule Premium').waitFor();

  await page.getByRole('link', { name: 'Réglages' }).click();
  await page.getByText(/Gratuite : 0 client\(s\)/).waitFor();
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('button', { name: 'Toutes mes données (JSON)' }).click(),
  ]);
  assert.match(download.suggestedFilename(), /^carne-mes-donnees-\d{4}-\d{2}-\d{2}\.json$/);

  await page.getByRole('link', { name: "Voir l'activité de mon compte" }).click();
  await page.getByText('Compte créé').waitFor();
  await page.getByText('Export de vos données').waitFor();

  await page.getByRole('link', { name: '← Réglages' }).click();
  await page.getByRole('link', { name: 'Supprimer mon compte' }).click();
  await page.getByLabel('Code PIN pour confirmer').fill('0000');
  await page.getByRole('button', { name: 'Supprimer définitivement mon compte' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Oui, tout supprimer' }).click();
  await page.getByRole('alert').first().waitFor(); // mauvais PIN : refusé, compte intact
  assert.ok(await page.getByRole('heading', { name: 'Supprimer mon compte' }).isVisible());

  await page.getByLabel('Code PIN pour confirmer').fill('1234');
  await page.getByRole('button', { name: 'Supprimer définitivement mon compte' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Oui, tout supprimer' }).click();
  await page.getByRole('heading', { name: 'Connexion' }).waitFor();

  await page.getByLabel('Votre numéro de téléphone').fill(number);
  await page.getByLabel('Code PIN (4 chiffres)').fill('1234');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.getByRole('alert').first().waitFor();
});

test('hors connexion : bandeau explicite et reprise au retour du réseau', async () => {
  const page = await newPage();
  await signUp(page);
  await page.context().setOffline(true);
  await page.getByRole('link', { name: 'Réglages' }).click();
  await page.getByText(/Pas de connexion au serveur/).waitFor();
  assert.ok(await page.locator('#offline').isVisible());
  await page.context().setOffline(false);
  await page.getByRole('heading', { name: 'Mon compte' }).waitFor();
  assert.ok(!(await page.locator('#offline').isVisible()));
});

test('page d\'accueil lisible avec un texte agrandi, sans défilement horizontal (mobile 360 px)', async () => {
  const context = await browser.newContext({ viewport: { width: 360, height: 740 }, locale: 'fr-FR', extraHTTPHeaders: { 'x-e2e-ip': `10.8.0.${counter++ % 250}` } });
  const page = await context.newPage();
  await page.goto(`${base}/app/index.html#/connexion`);
  await page.getByRole('heading', { name: 'Connexion' }).waitFor();
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  assert.ok(overflow <= 0, `défilement horizontal : ${overflow}px`);
});

// ---- Parcours complémentaires ----
import { execFileSync } from 'node:child_process';
const BACKEND_DIR = process.env.BACKEND_DIR ?? new URL('../../../ardoiz-backend', import.meta.url).pathname;
// Accès direct à la base de recette, pour simuler ce que le serveur ferait avec le temps.
const sql = (statement) => execFileSync('psql', [process.env.DATABASE_URL.replace(/\?.*$/, ''), '-q', '-c', statement], { encoding: 'utf8' });
// Opérations d'administration réelles (CLI du serveur) : aucune route HTTP d'administration n'existe.
const admin = (...args) => execFileSync('node', ['dist/admin/cli.js', ...args], { cwd: BACKEND_DIR, env: process.env, encoding: 'utf8' });

async function addClient(page, name, phoneNumber = '+229 01 67 07 70 29') {
  await page.goto(`${base}/app/index.html#/clients/nouveau`);
  await page.getByLabel('Nom').fill(name);
  await page.getByLabel('Téléphone').fill(phoneNumber);
  await page.getByRole('button', { name: 'Ajouter un client' }).click();
  await page.getByRole('heading', { name }).waitFor();
}

async function addDebt(page, amount, reason, { due = true } = {}) {
  await page.getByRole('link', { name: 'Nouvelle ardoise' }).click();
  await page.getByLabel('Montant (FCFA)').fill(amount);
  await page.getByLabel(/Motif/).fill(reason);
  if (due) await page.getByRole('button', { name: 'Dans 7 jours' }).click();
  await page.getByRole('button', { name: 'Nouvelle ardoise' }).click();
  await page.getByRole('heading', { name: reason }).waitFor();
}

test('Premium : bilan chiffré, relance par SMS, opposition d\'un client aux relances', async () => {
  const page = await newPage();
  const number = await signUp(page);
  admin('grant-premium', number, '30');
  await addClient(page, 'Koffi Mensah');
  await addDebt(page, '5000', 'Sucre');

  await page.getByRole('button', { name: 'Envoyer une relance' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Envoyer' }).click();
  await page.getByText('Relance envoyée.').waitFor();
  await page.getByRole('heading', { name: 'Relances' }).waitFor();

  await page.getByRole('link', { name: /Koffi Mensah/ }).click();
  await page.getByRole('link', { name: 'Modifier' }).click();
  await page.getByLabel('Cette personne refuse les relances').check();
  await page.getByRole('button', { name: 'Enregistrer' }).click();
  await page.getByText('Cette personne refuse les relances.').first().waitFor();
  await page.getByRole('link', { name: /Sucre/ }).click();
  assert.equal(await page.getByRole('button', { name: 'Envoyer une relance' }).count(), 0, 'plus de relance possible après opposition');

  await page.getByRole('link', { name: 'Bilan' }).click();
  await page.getByRole('heading', { name: 'Bilan' }).waitFor();
  assert.match(await page.locator('.kpi').first().textContent(), /5\s?000\s?FCFA/);
  await page.getByRole('link', { name: 'Réglages' }).click();
  await page.getByText(/Premium actif jusqu'au/).waitFor();
});

test('correction d\'une ardoise : montant inférieur aux remboursements refusé, puis suppression du client', async () => {
  const page = await newPage();
  await signUp(page);
  await addClient(page, 'Ami Dossou');
  await addDebt(page, '3000', 'Farine', { due: false });
  await page.getByLabel('Montant reçu (FCFA)').fill('2000');
  await page.getByRole('button', { name: 'Enregistrer le remboursement' }).click();
  await page.getByText('Partielle').waitFor();

  await page.getByRole('link', { name: 'Corriger' }).click();
  await page.getByLabel(/Montant \(FCFA\)/).fill('1500');
  await page.getByRole('button', { name: 'Enregistrer' }).click();
  await page.getByText(/ne peut pas être inférieur/).waitFor();
  await page.getByLabel(/Montant \(FCFA\)/).fill('4000');
  await page.getByRole('button', { name: 'Enregistrer' }).click();
  await page.getByRole('heading', { name: 'Farine' }).waitFor();
  assert.match(await page.locator('.balance .big').textContent(), /2\s?000\s?FCFA/);

  await page.getByRole('link', { name: /Ami Dossou/ }).click();
  await page.getByRole('button', { name: 'Télécharger ses données' }).click();
  await page.getByText('Fichier enregistré sur votre appareil.').waitFor();
  await page.getByRole('button', { name: 'Supprimer' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Supprimer' }).click();
  await page.getByText('Aucun client pour le moment').waitFor();
});

test('PIN oublié : nouveau PIN après vérification SMS, ancien PIN refusé ; changement de PIN', async () => {
  const page = await newPage();
  const number = await signUp(page, { pin: '1234' });
  await page.getByRole('link', { name: 'Réglages' }).click();
  await page.getByRole('button', { name: 'Me déconnecter' }).click();

  // Le serveur impose 60 s entre deux codes : on simule l'écoulement du délai.
  sql(`update users set "otpExpiresAt" = now() - interval '1 minute' where phone = '${number}'`);
  await page.getByRole('link', { name: 'PIN oublié ?' }).click();
  await page.getByRole('heading', { name: 'Créer un compte' }).waitFor();
  await page.getByLabel('Votre numéro de téléphone').fill(number);
  await page.getByRole('button', { name: 'Recevoir le code par SMS' }).click();
  const code = (await page.getByRole('note').textContent()).match(/(\d{6})/)[1];
  await page.getByLabel(/Code reçu par SMS/).fill(code);
  await page.getByRole('button', { name: 'Vérifier' }).click();
  await page.getByRole('heading', { name: 'Choisissez un nouveau PIN' }).waitFor();
  await page.getByLabel('Nom de votre boutique').fill('Boutique Test');
  await page.getByLabel('Code PIN (4 chiffres)').fill('5678');
  await page.getByLabel('Confirmez le code PIN').fill('5678');
  await page.getByLabel(/J'ai lu et j'accepte/).check();
  await page.getByRole('button', { name: 'Enregistrer le nouveau PIN' }).click();
  await page.getByRole('heading', { name: 'Clients' }).waitFor();

  // Changement de PIN : reconnexion obligatoire avec le nouveau code.
  await page.getByRole('link', { name: 'Réglages' }).click();
  await page.getByRole('link', { name: 'Changer le code PIN' }).click();
  await page.getByLabel('Code PIN actuel').fill('0000');
  await page.getByLabel('Nouveau code PIN', { exact: true }).fill('4321');
  await page.getByLabel('Confirmez le nouveau code PIN').fill('4321');
  await page.getByRole('button', { name: 'Changer le PIN' }).click();
  await page.getByRole('alert').filter({ hasText: /incorrect/ }).waitFor();
  await page.getByLabel('Code PIN actuel').fill('5678');
  await page.getByRole('button', { name: 'Changer le PIN' }).click();
  await page.getByRole('heading', { name: 'Connexion' }).waitFor();
  await page.getByLabel('Votre numéro de téléphone').fill(number);
  await page.getByLabel('Code PIN (4 chiffres)').fill('5678');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.getByRole('alert').filter({ hasText: 'incorrect' }).waitFor();
  await page.getByLabel('Code PIN (4 chiffres)').fill('4321');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.getByRole('heading', { name: 'Clients' }).waitFor();
});

test('nouvelle version des conditions : accès bloqué jusqu\'à l\'acceptation', async () => {
  const page = await newPage();
  await signUp(page);
  // Simule une nouvelle version côté serveur : le consentement existant ne porte plus sur la version courante.
  sql(`delete from consent_records where "userId" = (select id from users order by "createdAt" desc limit 1)`);
  await page.reload();
  await page.getByRole('heading', { name: 'Conditions mises à jour' }).waitFor();
  await page.goto(`${base}/app/index.html#/clients`);
  await page.getByRole('heading', { name: 'Conditions mises à jour' }).waitFor();
  await page.getByRole('button', { name: 'Accepter et continuer' }).click();
  await page.getByText('Vous devez accepter pour continuer.').waitFor();
  await page.getByLabel(/J'ai lu et j'accepte/).check();
  await page.getByRole('button', { name: 'Accepter et continuer' }).click();
  await page.getByRole('heading', { name: 'Clients' }).waitFor();
});

test('XSS : motif, libellé de caisse et nom de boutique hostiles restent du texte', async () => {
  const page = await newPage();
  const evil = '"><img src=x onerror=window.__pwned=1>';
  await signUp(page, { business: evil });
  assert.equal(await page.locator('#business').textContent(), evil);
  await addClient(page, 'Client Sûr');
  await addDebt(page, '100', evil, { due: false });
  await page.getByRole('link', { name: 'Caisse' }).click();
  await page.getByRole('button', { name: 'Noter une vente ou une dépense' }).click();
  await page.getByLabel('Montant (FCFA)').fill('50');
  await page.getByLabel(/Libellé/).fill(evil);
  await page.getByRole('button', { name: 'Enregistrer' }).click();
  await page.getByText(evil).first().waitFor();
  assert.equal(await page.evaluate(() => window.__pwned), undefined);
  assert.equal(await page.locator('img[src="x"]').count(), 0);
});
