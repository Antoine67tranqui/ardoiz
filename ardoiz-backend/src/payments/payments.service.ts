import { BadRequestException, Injectable } from '@nestjs/common';
import { PaymentMethod } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DebtsService } from '../debts/debts.service';
import { CreatePaymentDto } from './dto/create-payment.dto';

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

    const payment = await this.prisma.payment.create({
      data: { debtId, amount, method, transactionRef },
    });

    await this.debtsService.recomputeStatus(debtId);

    return payment;
  }
}
