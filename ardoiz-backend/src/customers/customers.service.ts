import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCustomerDto } from './dto/create-customer.dto';
import { UpdateCustomerDto } from './dto/update-customer.dto';
import { QueryCustomersDto } from './dto/query-customers.dto';
import { isPremiumActive } from '../subscription/subscription.utils';
import { FREE_PLAN_CUSTOMER_LIMIT } from '../subscription/plan.constants';

@Injectable()
export class CustomersService {
  constructor(private readonly prisma: PrismaService) {}

  async create(userId: string, dto: CreateCustomerDto) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });

    if (!isPremiumActive(user)) {
      const customerCount = await this.prisma.customer.count({ where: { userId } });
      if (customerCount >= FREE_PLAN_CUSTOMER_LIMIT) {
        throw new ForbiddenException({
          code: 'FREE_PLAN_LIMIT_REACHED',
          message: `Le plan gratuit est limite a ${FREE_PLAN_CUSTOMER_LIMIT} clients. Passez a Premium pour en ajouter davantage.`,
        });
      }
    }

    return this.prisma.customer.create({
      data: { ...dto, userId },
    });
  }

  async findAllForUser(userId: string, query: QueryCustomersDto = {}) {
    const { search, sortBy = 'createdAt', order = 'desc', overdueOnly } = query;
    const now = new Date();

    const customers = await this.prisma.customer.findMany({
      where: {
        userId,
        ...(search
          ? {
              OR: [
                { name: { contains: search, mode: 'insensitive' } },
                { phone: { contains: search } },
              ],
            }
          : {}),
      },
      include: {
        debts: {
          select: { amount: true, status: true, dueDate: true },
        },
      },
    });

    // Solde total du = somme des dettes non totalement remboursees,
    // calcule ici plutot que stocke pour rester source-unique-de-verite.
    let mapped = customers.map((customer) => {
      const outstandingDebts = customer.debts.filter((debt) => debt.status !== 'PAID');
      const outstandingBalance = outstandingDebts.reduce(
        (sum, debt) => sum + Number(debt.amount),
        0,
      );
      const hasOverdueDebt = outstandingDebts.some(
        (debt) => debt.dueDate && debt.dueDate.getTime() < now.getTime(),
      );
      const creditLimit = customer.creditLimit === null ? null : Number(customer.creditLimit);
      const { debts: _debts, ...rest } = customer;
      return {
        ...rest,
        creditLimit,
        outstandingBalance,
        hasOverdueDebt,
        creditLimitExceeded: creditLimit !== null && outstandingBalance > creditLimit,
      };
    });

    if (overdueOnly) {
      mapped = mapped.filter((customer) => customer.hasOverdueDebt);
    }

    mapped.sort((a, b) => {
      let comparison = 0;
      if (sortBy === 'name') {
        comparison = a.name.localeCompare(b.name);
      } else if (sortBy === 'balance') {
        comparison = a.outstandingBalance - b.outstandingBalance;
      } else {
        comparison = a.createdAt.getTime() - b.createdAt.getTime();
      }
      return order === 'asc' ? comparison : -comparison;
    });

    return mapped;
  }

  async findOneForUser(userId: string, customerId: string) {
    const customer = await this.prisma.customer.findUnique({
      where: { id: customerId },
      include: {
        debts: {
          include: { payments: true },
          orderBy: { createdAt: 'desc' },
        },
      },
    });
    if (!customer) {
      throw new NotFoundException('Client introuvable');
    }
    this.assertOwnership(customer.userId, userId);
    return customer;
  }

  async update(userId: string, customerId: string, dto: UpdateCustomerDto) {
    await this.findOneForUser(userId, customerId);
    return this.prisma.customer.update({ where: { id: customerId }, data: dto });
  }

  async remove(userId: string, customerId: string) {
    await this.findOneForUser(userId, customerId);
    await this.prisma.customer.delete({ where: { id: customerId } });
    return { message: 'Client supprime' };
  }

  private assertOwnership(ownerId: string, requesterId: string) {
    if (ownerId !== requesterId) {
      throw new ForbiddenException("Ce client n'appartient pas a ce commercant");
    }
  }
}
