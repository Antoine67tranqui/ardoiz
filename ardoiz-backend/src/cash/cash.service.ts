import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { CashEntry, Prisma } from '@prisma/client';
import { clampClientDate } from '../common/dates';
import { PrismaService } from '../prisma/prisma.service';
import { sumAmounts } from '../common/money';
import { CreateCashEntryDto, UpdateCashEntryDto } from './dto/create-cash-entry.dto';
import { QueryCashDto } from './dto/query-cash.dto';

export type CashEntryView = Omit<CashEntry, 'amount'> & { amount: number };

const view = (e: CashEntry): CashEntryView => ({ ...e, amount: e.amount.toNumber() });

@Injectable()
export class CashService {
  constructor(private readonly prisma: PrismaService) {}

  /** Creation idempotente (meme `id` rejoue = meme ecriture), comme les clients et les dettes. */
  async create(userId: string, dto: CreateCashEntryDto): Promise<{ entry: CashEntryView; created: boolean }> {
    if (dto.id) {
      const replay = await this.findReplay(userId, dto.id);
      if (replay) return { entry: view(replay), created: false };
    }
    try {
      const entry = await this.prisma.cashEntry.create({
        data: {
          id: dto.id,
          userId,
          type: dto.type,
          amount: dto.amount,
          label: dto.label || null,
          category: dto.category || undefined,
          occurredAt: clampClientDate(dto.occurredAt),
        },
      });
      return { entry: view(entry), created: true };
    } catch (error) {
      if (dto.id && error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        const replay = await this.findReplay(userId, dto.id);
        if (replay) return { entry: view(replay), created: false };
      }
      throw error;
    }
  }

  private async findReplay(userId: string, id: string): Promise<CashEntry | null> {
    const existing = await this.prisma.cashEntry.findUnique({ where: { id } });
    if (!existing) return null;
    if (existing.userId !== userId) throw new ConflictException('Cet identifiant est deja utilise');
    return existing;
  }

  async list(userId: string, query: QueryCashDto = {}): Promise<CashEntryView[]> {
    const entries = await this.prisma.cashEntry.findMany({
      where: {
        userId,
        type: query.type,
        occurredAt: {
          ...(query.from ? { gte: new Date(query.from) } : {}),
          ...(query.to ? { lt: new Date(query.to) } : {}),
        },
      },
      orderBy: [{ occurredAt: 'desc' }, { createdAt: 'desc' }],
      take: query.limit ?? 500,
    });
    return entries.map(view);
  }

  private async getOwned(userId: string, id: string): Promise<CashEntry> {
    const entry = await this.prisma.cashEntry.findFirst({ where: { id, userId } });
    // 404 aussi pour l'ecriture d'un autre commercant : on ne revele pas son existence.
    if (!entry) throw new NotFoundException('Ecriture introuvable');
    return entry;
  }

  async update(userId: string, id: string, dto: UpdateCashEntryDto): Promise<CashEntryView> {
    await this.getOwned(userId, id);
    const entry = await this.prisma.cashEntry.update({
      where: { id },
      data: {
        amount: dto.amount,
        label: dto.label === undefined ? undefined : dto.label || null,
        category: dto.category || undefined,
        occurredAt: dto.occurredAt ? clampClientDate(dto.occurredAt) : undefined,
      },
    });
    return view(entry);
  }

  async remove(userId: string, id: string): Promise<{ message: string }> {
    await this.getOwned(userId, id);
    await this.prisma.cashEntry.delete({ where: { id } });
    return { message: 'Ecriture supprimee' };
  }

  /**
   * Tresorerie d'une periode, en « argent reellement entre et sorti » :
   * - entrees = ventes au comptant + remboursements recus de clients ;
   * - sorties = depenses + paiements faits aux fournisseurs.
   * Une dette accordee a un client ou un achat a credit ne bouge pas la caisse
   * tant qu'il n'est pas paye : ils sont indiques a part.
   */
  async summary(userId: string, from: Date, to: Date) {
    const range = { gte: from, lt: to };
    const [entries, payments, creditGranted, creditReceived] = await Promise.all([
      this.prisma.cashEntry.findMany({ where: { userId, occurredAt: range } }),
      this.prisma.payment.findMany({
        where: { paidAt: range, debt: { customer: { userId } } },
        select: { amount: true, debt: { select: { customer: { select: { kind: true } } } } },
      }),
      this.prisma.debt.findMany({
        where: { createdAt: range, customer: { userId, kind: 'CLIENT' } },
        select: { amount: true },
      }),
      this.prisma.debt.findMany({
        where: { createdAt: range, customer: { userId, kind: 'SUPPLIER' } },
        select: { amount: true },
      }),
    ]);

    const sales = sumAmounts(entries.filter((e) => e.type === 'SALE'));
    const expenses = sumAmounts(entries.filter((e) => e.type === 'EXPENSE'));
    const collected = sumAmounts(payments.filter((p) => p.debt.customer.kind === 'CLIENT'));
    const paidToSuppliers = sumAmounts(payments.filter((p) => p.debt.customer.kind === 'SUPPLIER'));
    const cashIn = sales.plus(collected);
    const cashOut = expenses.plus(paidToSuppliers);

    const byCategory = new Map<string, Prisma.Decimal>();
    for (const e of entries.filter((x) => x.type === 'EXPENSE')) {
      byCategory.set(e.category, (byCategory.get(e.category) ?? new Prisma.Decimal(0)).plus(e.amount));
    }

    return {
      sales: sales.toNumber(),
      collected: collected.toNumber(),
      cashIn: cashIn.toNumber(),
      expenses: expenses.toNumber(),
      paidToSuppliers: paidToSuppliers.toNumber(),
      cashOut: cashOut.toNumber(),
      net: cashIn.minus(cashOut).toNumber(),
      creditGranted: sumAmounts(creditGranted).toNumber(),
      creditReceived: sumAmounts(creditReceived).toNumber(),
      expensesByCategory: [...byCategory.entries()]
        .map(([category, total]) => ({ category, total: total.toNumber() }))
        .sort((a, b) => b.total - a.total),
    };
  }
}
