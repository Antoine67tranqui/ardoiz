/**
 * Montant maximal accepte (FCFA) : les colonnes sont en Decimal(12, 2), soit
 * 9 999 999 999,99 au plus. Au-dela, la base rejette l'ecriture (erreur 500) ;
 * on refuse en amont avec une 400 explicite.
 */
export const MAX_AMOUNT_FCFA = 9_999_999_999;
