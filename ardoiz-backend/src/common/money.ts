import { Prisma } from '@prisma/client';

type DecimalLike = Prisma.Decimal | number | string;

/** Somme exacte de montants (Decimal, jamais de flottant JS). */
export function sumAmounts(items: Array<{ amount: DecimalLike }>): Prisma.Decimal {
  return items.reduce((sum, item) => sum.plus(item.amount), new Prisma.Decimal(0));
}

/**
 * Solde restant d'une dette : montant moins paiements recus, jamais negatif
 * (un paiement superieur a la dette, ex. recu via Mobile Money, ne cree pas de
 * solde "inverse").
 */
export function outstandingOf(
  debtAmount: DecimalLike,
  payments: Array<{ amount: DecimalLike }>,
): Prisma.Decimal {
  return Prisma.Decimal.max(0, new Prisma.Decimal(debtAmount).minus(sumAmounts(payments)));
}
