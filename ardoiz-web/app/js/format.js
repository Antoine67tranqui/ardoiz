const THIN = ' '; // espace fine insécable (milliers)
const NBSP = ' ';
export const MAX_FCFA = 9_999_999_999;

/** Montant en centimes (entier) depuis un nombre ou une chaîne décimale renvoyée par l'API. */
export function toCents(value) {
  return Math.round(Number(value) * 100);
}

/** Pour l'API : centimes -> nombre à 2 décimales au plus. */
export function fromCents(cents) {
  return cents / 100;
}

/** « 1 250 FCFA », ou « 1 250,50 FCFA » s'il y a des centimes. */
export function formatMoney(cents, { currency = true } = {}) {
  const negative = cents < 0;
  const abs = Math.abs(cents);
  const whole = Math.floor(abs / 100);
  const fraction = abs % 100;
  const digits = String(whole).replace(/\B(?=(\d{3})+(?!\d))/g, THIN);
  const number = fraction === 0 ? digits : `${digits},${String(fraction).padStart(2, '0')}`;
  return `${negative ? '-' : ''}${number}${currency ? `${NBSP}FCFA` : ''}`;
}

/** Saisie « 1 250,50 », « 1250.5 », « 2500 » -> centimes, ou null si invalide. */
export function parseAmount(input) {
  const cleaned = String(input ?? '').replace(/[\s  ]/g, '');
  const match = /^(\d+)(?:[.,](\d{1,2}))?$/.exec(cleaned);
  if (!match) return null;
  const whole = Number(match[1]);
  if (!Number.isSafeInteger(whole) || whole > MAX_FCFA) return null;
  const cents = whole * 100 + Number((match[2] ?? '').padEnd(2, '0') || 0);
  return cents > MAX_FCFA * 100 ? null : cents;
}

/** Champ de saisie : 250000 -> « 2500 », 125050 -> « 1250,50 ». */
export function moneyInput(cents) {
  const whole = Math.floor(Math.abs(cents) / 100);
  const fraction = Math.abs(cents) % 100;
  return fraction === 0 ? String(whole) : `${whole},${String(fraction).padStart(2, '0')}`;
}

const MONTHS = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const MONTH_NAMES = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

export const monthName = (monthIndex) => MONTH_NAMES[monthIndex];

/** « 4 oct. 2026 » (heure locale). */
export function formatDate(value) {
  const d = new Date(value);
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

export function formatTime(value) {
  const d = new Date(value);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/** Valeur d'un <input type="date"> (AAAA-MM-JJ, heure locale). */
export function dateInputValue(value) {
  const d = new Date(value);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** Fin de la journée locale choisie : une échéance « le 10 » court jusqu'à la fin du 10. */
export function endOfLocalDay(dateInput) {
  const [y, m, d] = dateInput.split('-').map(Number);
  return new Date(y, m - 1, d, 23, 59, 59);
}

/** Midi local d'un jour passé, ou maintenant pour aujourd'hui. */
export function occurredAtFor(dateInput, now = new Date()) {
  if (dateInput === dateInputValue(now)) return now;
  const [y, m, d] = dateInput.split('-').map(Number);
  return new Date(y, m - 1, d, 12);
}

export function relativeDays(value, now = new Date()) {
  const a = new Date(new Date(value).getFullYear(), new Date(value).getMonth(), new Date(value).getDate());
  const b = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const days = Math.round((a - b) / 86_400_000);
  if (days === 0) return "aujourd'hui";
  if (days === 1) return 'demain';
  if (days === -1) return 'hier';
  return days > 0 ? `dans ${days} jours` : `il y a ${-days} jours`;
}

export function initials(name) {
  const parts = String(name).trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  const first = [...parts[0]][0].toUpperCase();
  return parts.length === 1 ? first : first + [...parts[parts.length - 1]][0].toUpperCase();
}

/** Texte comparable pour la recherche : minuscules sans accents. */
export function fold(text) {
  return String(text).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
}

export const digitsOnly = (text) => String(text).replace(/\D/g, '');

// ---- Validations (mêmes règles que l'application et le serveur) ----

export const validate = {
  name: (v) => {
    const t = String(v ?? '').trim();
    if (!t) return 'Saisissez un nom.';
    if (t.length < 2) return 'Le nom doit comporter au moins 2 caractères.';
    if (t.length > 100) return 'Le nom est trop long (100 caractères maximum).';
    return null;
  },
  customerPhone: (v) => {
    const t = String(v ?? '').trim();
    if (!t) return 'Le téléphone est nécessaire pour les relances.';
    return /^[0-9+()\-.\s]{8,20}$/.test(t) ? null : 'Numéro invalide (8 à 20 chiffres, espaces et + acceptés).';
  },
  accountPhone: (v) => {
    const t = String(v ?? '').replace(/[\s().-]/g, '');
    if (!t) return 'Saisissez votre numéro de téléphone.';
    return /^\+\d{8,15}$/.test(t) ? null : 'Saisissez le numéro avec l\'indicatif du pays, par ex. +229 01 67 07 70 27.';
  },
  pin: (v) => (/^\d{4}$/.test(v ?? '') ? null : 'Le code PIN comporte exactement 4 chiffres.'),
  otp: (v) => (/^\d{6}$/.test(v ?? '') ? null : 'Le code reçu par SMS comporte 6 chiffres.'),
  amount: (v, maxCents = null) => {
    const cents = parseAmount(v);
    if (cents === null) return 'Saisissez un montant valide (ex. 2 500).';
    if (cents <= 0) return 'Le montant doit être supérieur à zéro.';
    if (maxCents !== null && cents > maxCents) return 'Le montant dépasse le solde restant.';
    return null;
  },
  optionalAmount: (v) => (String(v ?? '').trim() === '' ? null : validate.amount(v)),
  businessName: (v) => {
    const t = String(v ?? '').trim();
    if (!t) return 'Saisissez le nom de votre boutique.';
    return t.length > 100 ? 'Le nom est trop long (100 caractères maximum).' : null;
  },
  label: (v) => (String(v ?? '').trim().length > 200 ? 'Le libellé est trop long (200 caractères maximum).' : null),
  reason: (v) => (String(v ?? '').trim().length > 500 ? 'Le motif est trop long (500 caractères maximum).' : null),
};

export const normalizeAccountPhone = (v) => String(v).replace(/[\s().-]/g, '');

export const DEBT_CATEGORIES = ['Alimentation', 'Boissons', 'Hygiène', 'Ménage', 'Autre'];
export const EXPENSE_CATEGORIES = ['Achat de marchandises', 'Transport', 'Loyer', 'Électricité et eau', 'Salaires', 'Autre'];
