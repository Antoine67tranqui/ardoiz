#!/usr/bin/env node
// Verification EN BAC A SABLE de l'acces FedaPay, avant d'ecrire l'integration de paiement.
//
//   FEDAPAY_SECRET_KEY=sk_sandbox_... node scripts/fedapay-sandbox-check.mjs
//
// Ce que fait ce script (et rien d'autre) :
//   1. POST /v1/transactions : cree UNE transaction de test de 100 XOF ;
//   2. POST /v1/transactions/{id}/token : demande le jeton et le lien de paiement ;
//   3. GET  /v1/transactions/{id} : relit la transaction et son statut.
// Il affiche la FORME des reponses (noms des champs, types, statut), jamais la cle, ni les jetons.
// Il refuse une cle de production (sk_live_...). La cle ne se met que dans l'environnement, jamais dans un fichier du depot.
// Colle la sortie dans la conversation de developpement : l'integration sera ecrite d'apres les reponses REELLES.
// FEDAPAY_BASE_URL ne sert qu'aux tests automatiques du script (serveur factice local).
const BASE = process.env.FEDAPAY_BASE_URL ?? 'https://sandbox-api.fedapay.com/v1';
const key = process.env.FEDAPAY_SECRET_KEY ?? '';

if (!key) { console.error('FEDAPAY_SECRET_KEY est requis (cle secrete du bac a sable, sk_sandbox_...).'); process.exit(2); }
if (!key.startsWith('sk_sandbox_')) { console.error('Ce script n\'accepte que les cles du bac a sable (sk_sandbox_...). Cle refusee.'); process.exit(2); }

const shape = (value, depth = 0) => {
  if (value === null) return 'null';
  if (Array.isArray(value)) return value.length === 0 ? '[]' : [shape(value[0], depth + 1)];
  if (typeof value === 'object') {
    if (depth >= 3) return '{...}';
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, shape(v, depth + 1)]));
  }
  // Jamais la valeur d'une chaine (elle pourrait etre un jeton ou un lien de paiement) : seulement sa longueur.
  if (typeof value === 'string') return `string(${value.length})`;
  return typeof value;
};

async function call(method, path, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', Accept: 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* corps non JSON */ }
  console.log(`\n${method} ${path} -> HTTP ${res.status}`);
  if (json) console.log(JSON.stringify(shape(json), null, 2));
  else console.log(`(corps non JSON, ${text.length} caracteres)`);
  if (!res.ok) {
    // Les messages d'erreur ne contiennent pas de secret : ils aident a corriger la requete.
    console.log('message d\'erreur du serveur :', json?.message ?? json?.error ?? text.slice(0, 300));
    process.exit(1);
  }
  return json;
}

const created = await call('POST', '/transactions', {
  description: 'Carne : verification bac a sable',
  amount: 100,
  currency: { iso: 'XOF' },
  ...(process.env.FEDAPAY_CALLBACK_URL ? { callback_url: process.env.FEDAPAY_CALLBACK_URL } : {}),
});

// La reponse enveloppe l'objet sous une cle (ex. "v1/transaction") : on la retrouve sans la supposer.
const unwrap = (json) => {
  const inner = json && typeof json === 'object' ? Object.values(json).find((v) => v && typeof v === 'object' && !Array.isArray(v)) : null;
  return inner && 'id' in inner ? inner : json;
};
const tx = unwrap(created);
if (!tx?.id) { console.error('\nImpossible de trouver l\'identifiant de la transaction dans la reponse.'); process.exit(1); }

await call('POST', `/transactions/${tx.id}/token`);
const read = await call('GET', `/transactions/${tx.id}`);
const status = unwrap(read)?.status;
console.log(`\nStatut lu : ${status ?? '(champ "status" introuvable)'}`);
console.log('\nVerification terminee : l\'acces au bac a sable FedaPay fonctionne. Envoie cette sortie pour que l\'integration soit ecrite d\'apres les reponses reelles.');
