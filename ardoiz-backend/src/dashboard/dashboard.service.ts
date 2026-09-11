import { ForbiddenException, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { isPremiumActive } from '../subscription/subscription.utils';

export interface CategoryBreakdown {
  category: string;
  totalOutstanding: number;
  count: number;
}

export interface OverdueDebt {
  debtId: string;
  customerId: string;
  customerName: string;
  customerPhone: string;
  amount: number;
  outstanding: number;
  dueDate: Date;
  daysOverdue: number;
  category: string;
}

export interface MonthlyTrendPoint {
  month: string; // 'YYYY-MM'
  amountGranted: number;
  amountRecovered: number;
}

export interface AtRiskCustomer {
  customerId: string;
  customerName: string;
  customerPhone: string;
  overdueDebtCount: number;
  totalOverdueAmount: number;
  maxDaysOverdue: number;
}

const TREND_MONTHS = 6;

@Injectable()
export class DashboardService {
  constructor(private readonly prisma: PrismaService) {}

  async getSummary(userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (!isPremiumActive(user)) {
      throw new ForbiddenException({
        code: 'PREMIUM_REQUIRED',
        message: 'Le tableau de bord est reserve aux comptes Premium.',
      });
    }

    const [debts, totalCustomers] = await Promise.all([
      this.prisma.debt.findMany({
        where: { customer: { userId } },
        include: { customer: true, payments: true },
      }),
      this.prisma.customer.count({ where: { userId } }),
    ]);

    const now = new Date();
    let totalOutstanding = 0;
    const categoryMap = new Map<string, CategoryBreakdown>();
    const overdueDebts: OverdueDebt[] = [];
    const customersWithDebt = new Set<string>();

    for (const debt of debts) {
      const totalPaid = debt.payments.reduce((sum, p) => sum + Number(p.amount), 0);
      const outstanding = Math.max(0, Number(debt.amount) - totalPaid);
      totalOutstanding += outstanding;
      if (outstanding > 0) customersWithDebt.add(debt.customerId);

      const category = debt.category || 'Autre';
      const entry = categoryMap.get(category) ?? { category, totalOutstanding: 0, count: 0 };
      entry.totalOutstanding += outstanding;
      if (outstanding > 0) entry.count += 1;
      categoryMap.set(category, entry);

      if (outstanding > 0 && debt.dueDate && debt.dueDate.getTime() < now.getTime()) {
        const daysOverdue = Math.floor(
          (now.getTime() - debt.dueDate.getTime()) / (24 * 60 * 60 * 1000),
        );
        overdueDebts.push({
          debtId: debt.id,
          customerId: debt.customerId,
          customerName: debt.customer.name,
          customerPhone: debt.customer.phone,
          amount: Number(debt.amount),
          outstanding,
          dueDate: debt.dueDate,
          daysOverdue,
          category,
        });
      }
    }

    overdueDebts.sort((a, b) => b.daysOverdue - a.daysOverdue);

    // Taux de recouvrement : parmi les dettes entierement remboursees, quelle
    // part l'a ete avant/le jour de l'echeance (ou sans echeance fixee) vs
    // en retard. Donne une mesure de la fiabilite globale des clients.
    const paidDebts = debts.filter((d) => d.status === 'PAID');
    let paidOnTime = 0;
    for (const debt of paidDebts) {
      const lastPayment = debt.payments.reduce<Date | null>((latest, p) => {
        return !latest || p.paidAt > latest ? p.paidAt : latest;
      }, null);
      const onTime = !debt.dueDate || !lastPayment || lastPayment.getTime() <= debt.dueDate.getTime();
      if (onTime) paidOnTime += 1;
    }
    const recoveryRate = paidDebts.length === 0 ? null : paidOnTime / paidDebts.length;

    // Clients a risque : ceux avec des retards recurrents, classes par
    // nombre de dettes en retard puis par anciennete du plus vieux retard.
    const riskMap = new Map<string, AtRiskCustomer>();
    for (const overdue of overdueDebts) {
      const entry = riskMap.get(overdue.customerId) ?? {
        customerId: overdue.customerId,
        customerName: overdue.customerName,
        customerPhone: overdue.customerPhone,
        overdueDebtCount: 0,
        totalOverdueAmount: 0,
        maxDaysOverdue: 0,
      };
      entry.overdueDebtCount += 1;
      entry.totalOverdueAmount += overdue.outstanding;
      entry.maxDaysOverdue = Math.max(entry.maxDaysOverdue, overdue.daysOverdue);
      riskMap.set(overdue.customerId, entry);
    }
    const atRiskCustomers = [...riskMap.values()].sort(
      (a, b) => b.overdueDebtCount - a.overdueDebtCount || b.maxDaysOverdue - a.maxDaysOverdue,
    );

    // Tendance des 6 derniers mois : credit accorde vs recouvre, pour voir
    // l'evolution de l'encours dans le temps plutot qu'un simple instantane.
    const monthlyTrend = this.buildMonthlyTrend(debts);
    const currentMonth = monthlyTrend[monthlyTrend.length - 1];
    const previousMonth = monthlyTrend[monthlyTrend.length - 2];
    const monthOverMonth = previousMonth
      ? {
          amountGrantedDelta: currentMonth.amountGranted - previousMonth.amountGranted,
          amountRecoveredDelta: currentMonth.amountRecovered - previousMonth.amountRecovered,
        }
      : null;

    return {
      totalOutstanding,
      totalCustomers,
      customersWithDebt: customersWithDebt.size,
      byCategory: [...categoryMap.values()].sort(
        (a, b) => b.totalOutstanding - a.totalOutstanding,
      ),
      overdueDebts,
      recoveryRate,
      atRiskCustomers,
      monthlyTrend,
      monthOverMonth,
    };
  }

  private buildMonthlyTrend(
    debts: Array<{
      amount: unknown;
      createdAt: Date;
      payments: Array<{ amount: unknown; paidAt: Date }>;
    }>,
  ): MonthlyTrendPoint[] {
    const points: MonthlyTrendPoint[] = [];
    const now = new Date();

    for (let i = TREND_MONTHS - 1; i >= 0; i -= 1) {
      const start = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const end = new Date(now.getFullYear(), now.getMonth() - i + 1, 1);
      const month = `${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, '0')}`;

      let amountGranted = 0;
      let amountRecovered = 0;
      for (const debt of debts) {
        if (debt.createdAt >= start && debt.createdAt < end) {
          amountGranted += Number(debt.amount);
        }
        for (const payment of debt.payments) {
          if (payment.paidAt >= start && payment.paidAt < end) {
            amountRecovered += Number(payment.amount);
          }
        }
      }
      points.push({ month, amountGranted, amountRecovered });
    }

    return points;
  }
}
