import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma, PaymentMethod } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DebtsService } from '../debts/debts.service';
import { CreatePaymentDto } from './dto/create-payment.dto';

const UNIQUE_CONSTRAINT_VIOLATION = 'P2002';

@Injectable()
export class PaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly debtsService: DebtsService,
  ) {}

  /** Enregistrement manuel d'un paiement (ex: remise en especes) par le commercant. */
  async createManual(userId: string, dto: CreatePaymentDto) {
    await this.debtsService.getOwnedDebt(userId, dto.debtId);
    return this.recordPayment(dto.debtId, dto.amount, dto.method);
  }

  /**
   * Enregistrement d'un paiement recu via webhook Mobile Money.
   * `transactionRef` doit etre unique pour garantir l'idempotence du webhook.
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
    return this.recordPayment(
      params.debtId,
      params.amount,
      PaymentMethod.MOMO,
      params.transactionRef,
    );
  }

  private async recordPayment(
    debtId: string,
    amount: number,
    method: PaymentMethod,
    transactionRef?: string,
  ) {
    const debt = await this.prisma.debt.findUnique({ where: { id: debtId } });
    if (!debt) {
      throw new BadRequestException('Dette introuvable');
    }

    let payment;
    try {
      payment = await this.prisma.payment.create({
        data: { debtId, amount, method, transactionRef },
      });
    } catch (error) {
      // Deux livraisons concurrentes du meme webhook peuvent toutes deux
      // passer le findUnique() de createFromMobileMoneyWebhook avant que
      // l'une des deux n'ecrive : la seconde heurte alors la contrainte
      // unique sur transactionRef. On traite ce cas comme "deja traite"
      // plutot que de laisser remonter une 500 brute au webhook.
      if (
        transactionRef &&
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === UNIQUE_CONSTRAINT_VIOLATION
      ) {
        const existing = await this.prisma.payment.findUnique({
          where: { transactionRef },
        });
        if (existing) {
          return existing;
        }
      }
      throw error;
    }

    await this.debtsService.recomputeStatus(debtId);

    return payment;
  }
}
