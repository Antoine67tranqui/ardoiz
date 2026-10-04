import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Debt, DebtStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { clampClientDate } from '../common/dates';
import { outstandingOf, sumAmounts } from '../common/money';
import { CreateDebtDto } from './dto/create-debt.dto';
import { UpdateDebtDto } from './dto/update-debt.dto';

const UNIQUE_CONSTRAINT_VIOLATION = 'P2002';

export type DebtWithAlert = Debt & { creditLimitExceeded: boolean };

@Injectable()
export class DebtsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Cree une dette. Si le client fournit un `id`, la creation est idempotente :
   * rejouer le meme envoi (coupure reseau, reessai de synchronisation) renvoie
   * la dette deja enregistree au lieu d'en creer une seconde.
   */
  async create(
    userId: string,
    dto: CreateDebtDto,
  ): Promise<{ debt: DebtWithAlert; created: boolean }> {
    const customer = await this.prisma.customer.findUnique({
      where: { id: dto.customerId },
    });
    if (!customer) {
      throw new NotFoundException('Client introuvable');
    }
    if (customer.userId !== userId) {
      throw new ForbiddenException("Ce client n'appartient pas a ce commercant");
    }

    if (dto.id) {
      const replay = await this.findReplay(userId, dto.id, dto.customerId);
      if (replay) {
        return {
          debt: { ...replay, creditLimitExceeded: await this.isOverLimit(customer) },
          created: false,
        };
      }
    }

    let debt: Debt;
    try {
      debt = await this.prisma.debt.create({
        data: {
          id: dto.id,
          customerId: dto.customerId,
          amount: dto.amount,
          reason: dto.reason,
          category: dto.category,
          dueDate: dto.dueDate ? new Date(dto.dueDate) : undefined,
          createdAt: clampClientDate(dto.createdAt),
        },
      });
    } catch (error) {
      // Deux envois simultanes du meme id : le second perd la course.
      if (dto.id && this.isUniqueViolation(error)) {
        const replay = await this.findReplay(userId, dto.id, dto.customerId);
        if (replay) {
          return {
            debt: { ...replay, creditLimitExceeded: await this.isOverLimit(customer) },
            created: false,
          };
        }
      }
      throw error;
    }

    // Alerte non bloquante : le plafond de credit est une aide a la decision
    // pour le commercant, pas une limite technique (il peut vouloir l'outrepasser
    // pour un bon client ponctuellement).
    return {
      debt: { ...debt, creditLimitExceeded: await this.isOverLimit(customer) },
      created: true,
    };
  }

  async findAllForUser(userId: string, status?: DebtStatus) {
    return this.prisma.debt.findMany({
      where: {
        status,
        customer: { userId },
      },
      include: { customer: true, payments: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOneForUser(userId: string, debtId: string) {
    return this.getOwnedDebt(userId, debtId);
  }

  /** Corrige une dette saisie par erreur (montant, motif, categorie, echeance). */
  async update(userId: string, debtId: string, dto: UpdateDebtDto) {
    const debt = await this.getOwnedDebt(userId, debtId);

    if (dto.amount !== undefined) {
      const totalPaid = sumAmounts(debt.payments);
      if (totalPaid.greaterThan(dto.amount)) {
        throw new BadRequestException({
          code: 'AMOUNT_BELOW_PAYMENTS',
          message: `Le montant ne peut pas etre inferieur aux paiements deja recus (${totalPaid.toString()}).`,
        });
      }
    }

    await this.prisma.debt.update({
      where: { id: debtId },
      data: {
        amount: dto.amount,
        reason: dto.reason,
        category: dto.category,
        dueDate: dto.dueDate === undefined ? undefined : dto.dueDate === null ? null : new Date(dto.dueDate),
      },
    });
    return this.recomputeStatus(debtId);
  }

  /** Supprime une dette (et, en cascade, ses paiements et relances). */
  async remove(userId: string, debtId: string) {
    await this.getOwnedDebt(userId, debtId);
    await this.prisma.debt.delete({ where: { id: debtId } });
    return { message: 'Dette supprimee' };
  }

  /** Recalcule le statut d'une dette a partir de la somme de ses paiements. */
  async recomputeStatus(debtId: string, db: Prisma.TransactionClient | PrismaService = this.prisma) {
    const debt = await db.debt.findUniqueOrThrow({
      where: { id: debtId },
      include: { payments: true },
    });
    const totalPaid = sumAmounts(debt.payments);

    let status: DebtStatus = 'PENDING';
    if (totalPaid.greaterThanOrEqualTo(debt.amount)) {
      status = 'PAID';
    } else if (totalPaid.greaterThan(0)) {
      status = 'PARTIAL';
    }

    return db.debt.update({ where: { id: debtId }, data: { status } });
  }

  async getOwnedDebt(userId: string, debtId: string) {
    const debt = await this.prisma.debt.findUnique({
      where: { id: debtId },
      include: { customer: true, payments: true, reminders: true },
    });
    if (!debt) {
      throw new NotFoundException('Dette introuvable');
    }
    if (debt.customer.userId !== userId) {
      throw new ForbiddenException("Cette dette n'appartient pas a ce commercant");
    }
    return debt;
  }

  /** Dette deja enregistree sous cet id, si elle appartient bien a ce commercant et a ce client. */
  private async findReplay(userId: string, id: string, customerId: string): Promise<Debt | null> {
    const existing = await this.prisma.debt.findUnique({
      where: { id },
      include: { customer: true },
    });
    if (!existing) return null;
    if (existing.customer.userId !== userId || existing.customerId !== customerId) {
      throw new ConflictException('Cet identifiant est deja utilise');
    }
    const { customer: _customer, ...debt } = existing;
    return debt;
  }

  private isUniqueViolation(error: unknown): boolean {
    return (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === UNIQUE_CONSTRAINT_VIOLATION
    );
  }

  // Encours du client (net des paiements deja recus) compare a son plafond.
  private async isOverLimit(customer: { id: string; creditLimit: Prisma.Decimal | null }): Promise<boolean> {
    if (customer.creditLimit === null) return false;
    const outstandingDebts = await this.prisma.debt.findMany({
      where: { customerId: customer.id, status: { not: 'PAID' } },
      select: { amount: true, payments: { select: { amount: true } } },
    });
    const total = outstandingDebts.reduce(
      (sum, debt) => sum.plus(outstandingOf(debt.amount, debt.payments)),
      new Prisma.Decimal(0),
    );
    return total.greaterThan(customer.creditLimit);
  }
}
