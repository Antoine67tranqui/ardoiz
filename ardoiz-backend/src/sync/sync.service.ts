import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class SyncService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Instantane complet des donnees du commercant. Une entite absente de
   * l'instantane a ete supprimee : l'app mobile retire alors sa copie locale
   * (sauf si elle a des modifications en attente d'envoi). Les montants sont
   * des nombres a 2 decimales au plus (colonnes Decimal(12, 2)).
   */
  async snapshot(userId: string) {
    const [customers, debts, payments, cashEntries] = await Promise.all([
      this.prisma.customer.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } }),
      this.prisma.debt.findMany({
        where: { customer: { userId } },
        orderBy: { createdAt: 'asc' },
      }),
      this.prisma.payment.findMany({
        where: { debt: { customer: { userId } } },
        orderBy: { paidAt: 'asc' },
      }),
      this.prisma.cashEntry.findMany({ where: { userId }, orderBy: { occurredAt: 'asc' } }),
    ]);

    return {
      serverTime: new Date().toISOString(),
      customers: customers.map((c) => ({
        id: c.id,
        name: c.name,
        phone: c.phone,
        creditLimit: c.creditLimit === null ? null : c.creditLimit.toNumber(),
        kind: c.kind,
        reminderOptOut: c.reminderOptOut,
        createdAt: c.createdAt.toISOString(),
      })),
      debts: debts.map((d) => ({
        id: d.id,
        customerId: d.customerId,
        amount: d.amount.toNumber(),
        reason: d.reason,
        category: d.category,
        status: d.status,
        dueDate: d.dueDate?.toISOString() ?? null,
        createdAt: d.createdAt.toISOString(),
      })),
      payments: payments.map((p) => ({
        id: p.id,
        debtId: p.debtId,
        amount: p.amount.toNumber(),
        method: p.method,
        paidAt: p.paidAt.toISOString(),
      })),
      cashEntries: cashEntries.map((e) => ({
        id: e.id,
        type: e.type,
        amount: e.amount.toNumber(),
        label: e.label,
        category: e.category,
        occurredAt: e.occurredAt.toISOString(),
      })),
    };
  }
}
