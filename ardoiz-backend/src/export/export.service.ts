import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { outstandingOf, sumAmounts } from '../common/money';
import { PrismaService } from '../prisma/prisma.service';

/** Echappe une valeur pour un champ CSV (RFC 4180). */
function csvField(value: unknown): string {
  let str = value === null || value === undefined ? '' : String(value);
  // Injection de formule (OWASP « CSV injection ») : un nom de client comme
  // « =HYPERLINK(...) » serait EXECUTE par Excel a l'ouverture. Une apostrophe
  // en tete force le tableur a lire le texte tel quel.
  if (typeof value === 'string' && /^[=+\-@\t\r]/.test(str)) str = `'${str}`;
  if (/[",\n]/.test(str)) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

function formatDate(date: Date | null): string {
  if (!date) return '';
  return date.toISOString().slice(0, 10);
}

const STATUS_LABELS: Record<string, string> = {
  PENDING: 'En attente',
  PARTIAL: 'Partiellement remboursee',
  PAID: 'Remboursee',
};

@Injectable()
export class ExportService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Genere l'historique complet (une ligne par dette/"ardoise") du
   * commercant au format CSV, pour lui permettre de garder une trace
   * exportable de toutes les entrees (dettes) et sorties (remboursements)
   * enregistrees dans l'app, independamment de Carne.
   */
  async generateHistoryCsv(userId: string): Promise<string> {
    const debts = await this.prisma.debt.findMany({
      where: { customer: { userId } },
      include: { customer: true, payments: true, reminders: true },
      orderBy: { createdAt: 'desc' },
    });

    const headers = [
      'Type',
      'Nom',
      'Telephone',
      'Categorie',
      'Motif',
      'Montant initial (FCFA)',
      'Montant rembourse (FCFA)',
      'Solde restant (FCFA)',
      'Statut',
      'Date d\'enregistrement',
      'Date d\'echeance',
      'Date du dernier remboursement',
      'Methode du dernier remboursement',
      'Nombre de relances envoyees',
    ];

    const rows = debts.map((debt) => {
      const totalPaid = sumAmounts(debt.payments);
      const outstanding = outstandingOf(debt.amount, debt.payments);
      const lastPayment = debt.payments.sort(
        (a, b) => b.paidAt.getTime() - a.paidAt.getTime(),
      )[0];

      return [
        debt.customer.kind === 'SUPPLIER' ? 'Fournisseur' : 'Client',
        debt.customer.name,
        debt.customer.phone,
        debt.category,
        debt.reason ?? '',
        new Prisma.Decimal(debt.amount).toFixed(2),
        totalPaid.toFixed(2),
        outstanding.toFixed(2),
        STATUS_LABELS[debt.status] ?? debt.status,
        formatDate(debt.createdAt),
        formatDate(debt.dueDate),
        lastPayment ? formatDate(lastPayment.paidAt) : '',
        lastPayment ? lastPayment.method : '',
        debt.reminders.length,
      ];
    });

    const lines = [headers, ...rows].map((row) => row.map(csvField).join(','));
    // BOM UTF-8 : garantit que les caracteres accentues s'affichent
    // correctement a l'ouverture dans Excel.
    return '﻿' + lines.join('\r\n');
  }

  /** Journal de caisse (ventes au comptant et depenses) au format CSV. */
  async generateCashCsv(userId: string): Promise<string> {
    const entries = await this.prisma.cashEntry.findMany({ where: { userId }, orderBy: { occurredAt: 'desc' } });
    const headers = ['Date', 'Nature', 'Montant (FCFA)', 'Categorie', 'Libelle'];
    const rows = entries.map((e) => [
      formatDate(e.occurredAt),
      e.type === 'SALE' ? 'Vente' : 'Depense',
      new Prisma.Decimal(e.amount).toFixed(2),
      e.category,
      e.label ?? '',
    ]);
    return '\ufeff' + [headers, ...rows].map((row) => row.map(csvField).join(',')).join('\r\n');
  }
}
