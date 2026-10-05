// Calculs sur les données renvoyées par l'API (montants en centimes entiers, jamais en flottants).
import { toCents } from './format.js';

const DAY = 86_400_000;

/** Dette normalisée : montants en centimes, reste à payer, jours de retard. */
export function debtView(raw, now = new Date()) {
  const amount = toCents(raw.amount);
  const payments = (raw.payments ?? []).map((p) => ({ ...p, cents: toCents(p.amount) }));
  const paid = payments.reduce((sum, p) => sum + p.cents, 0);
  const outstanding = Math.max(0, amount - paid);
  let overdueDays = 0;
  if (outstanding > 0 && raw.dueDate) {
    const due = new Date(raw.dueDate);
    // Une échéance « le 10 » court jusqu'à la fin du 10 : en retard à partir du 11.
    const dueEnd = new Date(due.getFullYear(), due.getMonth(), due.getDate() + 1).getTime();
    if (now.getTime() >= dueEnd) overdueDays = Math.max(1, Math.floor((now.getTime() - dueEnd) / DAY) + 1);
  }
  const status = outstanding === 0 ? 'PAID' : paid > 0 ? 'PARTIAL' : 'PENDING';
  return { ...raw, amount, paid, outstanding, overdueDays, status, payments };
}

/** Solde d'un client ou fournisseur à partir de sa fiche détaillée. */
export function partyBalance(debts) {
  return debts.reduce((sum, d) => sum + d.outstanding, 0);
}

export const isSupplier = (party) => party.kind === 'SUPPLIER';

/** Libellés lisibles du journal d'activité (jamais les codes bruts du serveur). */
export function activityLabel(action) {
  return ({
    ACCOUNT_CREATED: 'Compte créé',
    LOGIN: 'Connexion',
    PIN_LOCKED: 'Compte verrouillé après plusieurs codes PIN erronés',
    PIN_CHANGED: 'Code PIN modifié',
    LOGOUT: 'Déconnexion',
    CONSENT_ACCEPTED: 'Conditions et confidentialité acceptées',
    DATA_EXPORT: 'Export de vos données',
    CUSTOMER_EXPORT: "Export des données d'un client ou fournisseur",
  })[action] ?? 'Activité du compte';
}

/** Bornes [début inclus, fin exclue) d'une période pour la caisse, en heure locale. */
export function periodRange(kind, now = new Date()) {
  const y = now.getFullYear();
  const m = now.getMonth();
  const d = now.getDate();
  if (kind === 'today') return [new Date(y, m, d), new Date(y, m, d + 1)];
  if (kind === 'week') {
    const monday = d - ((now.getDay() + 6) % 7);
    return [new Date(y, m, monday), new Date(y, m, monday + 7)];
  }
  return [new Date(y, m, 1), new Date(y, m + 1, 1)];
}
