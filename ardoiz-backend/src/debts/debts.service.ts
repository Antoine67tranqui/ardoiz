import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DebtStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateDebtDto } from './dto/create-debt.dto';

@Injectable()
export class DebtsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(userId: string, dto: CreateDebtDto) {
    const customer = await this.prisma.customer.findUnique({
      where: { id: dto.customerId },
    });
    if (!customer) {
      throw new NotFoundException('Client introuvable');
    }
    if (customer.userId !== userId) {
      throw new ForbiddenException("Ce client n'appartient pas a ce commercant");
    }

    const debt = await this.prisma.debt.create({
      data: {
        customerId: dto.customerId,
        amount: dto.amount,
        reason: dto.reason,
        category: dto.category,
        dueDate: dto.dueDate ? new Date(dto.dueDate) : undefined,
      },
    });

    // Alerte non bloquante : le plafond de credit est une aide a la decision
    // pour le commercant, pas une limite technique (il peut vouloir l'outrepasser
    // pour un bon client ponctuellement).
    let creditLimitExceeded = false;
    if (customer.creditLimit !== null) {
      const outstandingDebts = await this.prisma.debt.findMany({
        where: { customerId: customer.id, status: { not: 'PAID' } },
        select: { amount: true },
      });
      const totalOutstanding = outstandingDebts.reduce((sum, d) => sum + Number(d.amount), 0);
      creditLimitExceeded = totalOutstanding > Number(customer.creditLimit);
    }

    return { ...debt, creditLimitExceeded };
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
    const debt = await this.getOwnedDebt(userId, debtId);
    return debt;
  }

  /** Recalcule le statut d'une dette a partir de la somme de ses paiements. */
  async recomputeStatus(debtId: string) {
    const debt = await this.prisma.debt.findUniqueOrThrow({
      where: { id: debtId },
      include: { payments: true },
    });
    const totalPaid = debt.payments.reduce((sum, p) => sum + Number(p.amount), 0);

    let status: DebtStatus = 'PENDING';
    if (totalPaid >= Number(debt.amount)) {
      status = 'PAID';
    } else if (totalPaid > 0) {
      status = 'PARTIAL';
    }

    return this.prisma.debt.update({ where: { id: debtId }, data: { status } });
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
}
