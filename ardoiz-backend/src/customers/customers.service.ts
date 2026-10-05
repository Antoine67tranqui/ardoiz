import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Customer, Prisma } from '@prisma/client';
import { outstandingOf } from '../common/money';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCustomerDto } from './dto/create-customer.dto';
import { UpdateCustomerDto } from './dto/update-customer.dto';
import { QueryCustomersDto } from './dto/query-customers.dto';
import { isPremiumActive } from '../subscription/subscription.utils';
import { FREE_PLAN_CUSTOMER_LIMIT } from '../subscription/plan.constants';

@Injectable()
export class CustomersService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Cree un client. Si le client fournit un `id`, la creation est idempotente :
   * un envoi rejoue (coupure reseau, reessai de synchronisation) renvoie le
   * client deja enregistre, meme si le plan gratuit est entre-temps plein.
   */
  async create(
    userId: string,
    dto: CreateCustomerDto,
  ): Promise<{ customer: Customer; created: boolean }> {
    if (dto.id) {
      const replay = await this.findReplay(userId, dto.id);
      if (replay) return { customer: replay, created: false };
    }

    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });

    if (!isPremiumActive(user)) {
      // Limite par type : 15 clients ET 15 fournisseurs au plan gratuit.
      const kind = dto.kind ?? 'CLIENT';
      const customerCount = await this.prisma.customer.count({ where: { userId, kind } });
      if (customerCount >= FREE_PLAN_CUSTOMER_LIMIT) {
        const noun = kind === 'SUPPLIER' ? 'fournisseurs' : 'clients';
        throw new ForbiddenException({
          code: 'FREE_PLAN_LIMIT_REACHED',
          message: `Le plan gratuit est limite a ${FREE_PLAN_CUSTOMER_LIMIT} ${noun}. Passez a Premium pour en ajouter davantage.`,
        });
      }
    }

    try {
      const customer = await this.prisma.customer.create({ data: { ...dto, userId } });
      return { customer, created: true };
    } catch (error) {
      // Deux envois simultanes du meme id : le second perd la course.
      if (
        dto.id &&
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        const replay = await this.findReplay(userId, dto.id);
        if (replay) return { customer: replay, created: false };
      }
      throw error;
    }
  }

  private async findReplay(userId: string, id: string): Promise<Customer | null> {
    const existing = await this.prisma.customer.findUnique({ where: { id } });
    if (!existing) return null;
    if (existing.userId !== userId) {
      throw new ConflictException('Cet identifiant est deja utilise');
    }
    return existing;
  }

  async findAllForUser(userId: string, query: QueryCustomersDto = {}) {
    const { search, sortBy = 'createdAt', order = 'desc', overdueOnly, kind } = query;
    const now = new Date();

    const customers = await this.prisma.customer.findMany({
      where: {
        userId,
        ...(kind ? { kind } : {}),
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
          select: {
            amount: true,
            status: true,
            dueDate: true,
            payments: { select: { amount: true } },
          },
        },
      },
    });

    // Solde total du = somme, sur les dettes non soldees, du montant restant
    // (montant moins paiements deja recus : un client qui a rembourse 4000 sur
    // 5000 doit 1000, pas 5000), calcule ici plutot que stocke pour rester
    // source-unique-de-verite.
    let mapped = customers.map((customer) => {
      const outstandingDebts = customer.debts.filter((debt) => debt.status !== 'PAID');
      // Decimal plutot que Number() : cette somme sert a une comparaison au
      // plafond de credit qui doit rester exacte au FCFA pres.
      const outstandingBalanceDec = outstandingDebts.reduce(
        (sum, debt) => sum.plus(outstandingOf(debt.amount, debt.payments)),
        new Prisma.Decimal(0),
      );
      const hasOverdueDebt = outstandingDebts.some(
        (debt) => debt.dueDate && debt.dueDate.getTime() < now.getTime(),
      );
      const creditLimit = customer.creditLimit === null ? null : Number(customer.creditLimit);
      const { debts: _debts, ...rest } = customer;
      return {
        ...rest,
        creditLimit,
        outstandingBalance: outstandingBalanceDec.toNumber(),
        hasOverdueDebt,
        creditLimitExceeded:
          creditLimit !== null && outstandingBalanceDec.greaterThan(creditLimit),
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
