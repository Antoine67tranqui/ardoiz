import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Payment, PaymentMethod, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DebtsService } from '../debts/debts.service';
import { clampClientDate } from '../common/dates';
import { sumAmounts } from '../common/money';
import { CreatePaymentDto } from './dto/create-payment.dto';

const UNIQUE_CONSTRAINT_VIOLATION = 'P2002';

@Injectable()
export class PaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly debtsService: DebtsService,
  ) {}

  /**
   * Enregistrement manuel d'un paiement (ex: remise en especes) par le
   * commercant. Idempotent si le client fournit un `id` : un envoi rejoue ne
   * credite jamais deux fois la dette.
   */
  async createManual(
    userId: string,
    dto: CreatePaymentDto,
  ): Promise<{ payment: Payment; created: boolean }> {
    await this.debtsService.getOwnedDebt(userId, dto.debtId);

    if (dto.id) {
      const replay = await this.findReplay(userId, dto.id, dto.debtId);
      if (replay) return { payment: replay, created: false };
    }

    try {
      const payment = await this.prisma.$transaction(async (tx) => {
        // Verrou sur la dette : deux paiements simultanes ne peuvent pas
        // depasser ensemble le solde (chacun verrait l'autre absent sans ce verrou).
        await tx.$queryRaw`SELECT id FROM debts WHERE id = ${dto.debtId} FOR UPDATE`;
        const debt = await tx.debt.findUniqueOrThrow({
          where: { id: dto.debtId },
          include: { payments: true },
        });
        const outstanding = new Prisma.Decimal(debt.amount).minus(sumAmounts(debt.payments));
        if (new Prisma.Decimal(dto.amount).greaterThan(outstanding)) {
          throw new BadRequestException({
            code: 'OVERPAYMENT',
            message: `Le montant depasse le solde restant de la dette (${Prisma.Decimal.max(0, outstanding).toString()}).`,
          });
        }
        const created = await tx.payment.create({
          data: {
            id: dto.id,
            debtId: dto.debtId,
            amount: dto.amount,
            method: dto.method,
            paidAt: clampClientDate(dto.paidAt),
          },
        });
        await this.debtsService.recomputeStatus(dto.debtId, tx);
        return created;
      });
      return { payment, created: true };
    } catch (error) {
      if (dto.id && this.isUniqueViolation(error)) {
        const replay = await this.findReplay(userId, dto.id, dto.debtId);
        if (replay) return { payment: replay, created: false };
      }
      throw error;
    }
  }

  /** Annule un paiement saisi par erreur : la dette retrouve son solde. */
  async remove(userId: string, paymentId: string) {
    const payment = await this.prisma.payment.findUnique({
      where: { id: paymentId },
      include: { debt: { include: { customer: true } } },
    });
    if (!payment) {
      throw new NotFoundException('Paiement introuvable');
    }
    if (payment.debt.customer.userId !== userId) {
      throw new ForbiddenException("Ce paiement n'appartient pas a ce commercant");
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.payment.delete({ where: { id: paymentId } });
      await this.debtsService.recomputeStatus(payment.debtId, tx);
    });
    return { message: 'Paiement supprime' };
  }

  /**
   * Enregistrement d'un paiement recu via webhook Mobile Money.
   * `transactionRef` doit etre unique pour garantir l'idempotence du webhook.
   * Contrairement a la saisie manuelle, l'argent a reellement ete recu : un
   * montant superieur au solde est accepte (la dette passe a PAID).
   */
  async createFromMobileMoneyWebhook(params: {
    debtId: string;
    amount: number;
    transactionRef: string;
  }) {
    const existing = await this.prisma.payment.findUnique({
      where: { transactionRef: params.transactionRef },
    });
    if (existing) {
      // Webhook deja traite : on ne double-compte pas le paiement.
      return existing;
    }

    const debt = await this.prisma.debt.findUnique({ where: { id: params.debtId } });
    if (!debt) {
      throw new BadRequestException('Dette introuvable');
    }

    let payment: Payment;
    try {
      payment = await this.prisma.payment.create({
        data: {
          debtId: params.debtId,
          amount: params.amount,
          method: PaymentMethod.MOMO,
          transactionRef: params.transactionRef,
        },
      });
    } catch (error) {
      // Deux livraisons concurrentes du meme webhook peuvent toutes deux
      // passer le findUnique() ci-dessus avant que l'une des deux n'ecrive :
      // la seconde heurte la contrainte unique sur transactionRef. On traite
      // ce cas comme "deja traite" plutot que de laisser remonter une 500.
      if (this.isUniqueViolation(error)) {
        const replay = await this.prisma.payment.findUnique({
          where: { transactionRef: params.transactionRef },
        });
        if (replay) return replay;
      }
      throw error;
    }

    await this.debtsService.recomputeStatus(params.debtId);
    return payment;
  }

  /** Paiement deja enregistre sous cet id, s'il concerne bien une dette de ce commercant. */
  private async findReplay(userId: string, id: string, debtId: string): Promise<Payment | null> {
    const existing = await this.prisma.payment.findUnique({
      where: { id },
      include: { debt: { include: { customer: true } } },
    });
    if (!existing) return null;
    if (existing.debt.customer.userId !== userId || existing.debtId !== debtId) {
      throw new ConflictException('Cet identifiant est deja utilise');
    }
    const { debt: _debt, ...payment } = existing;
    return payment;
  }

  private isUniqueViolation(error: unknown): boolean {
    return (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === UNIQUE_CONSTRAINT_VIOLATION
    );
  }
}
