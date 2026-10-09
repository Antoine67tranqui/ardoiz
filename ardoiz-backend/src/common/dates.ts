const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_PAST_DAYS = 366;

/**
 * Date d'un evenement saisi hors ligne (dette accordee, paiement recu) : la
 * date locale du telephone est conservee (le tableau de bord range les dettes
 * par mois d'octroi), mais bornee a [maintenant - 366 jours ; maintenant] pour
 * qu'une horloge de telephone deregleee ne fausse pas l'historique.
 */
export function clampClientDate(value: string | undefined, now: Date = new Date()): Date {
  if (!value) return now;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return now;
  const earliest = new Date(now.getTime() - MAX_PAST_DAYS * DAY_MS);
  if (date.getTime() > now.getTime()) return now;
  if (date.getTime() < earliest.getTime()) return earliest;
  return date;
}
