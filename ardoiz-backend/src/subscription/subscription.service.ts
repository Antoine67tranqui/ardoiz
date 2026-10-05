import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { MobileMoneyService } from '../payments/mobile-money.service';
import { isPremiumActive } from './subscription.utils';
import {
  FREE_PLAN_CUSTOMER_LIMIT,
  PREMIUM_DURATION_DAYS,
  PREMIUM_MONTHLY_PRICE_FCFA,
} from './plan.constants';

@Injectable()
export class SubscriptionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly mobileMoneyService: MobileMoneyService,
  ) {}

  async getStatus(userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    const [customerCount, supplierCount] = await Promise.all([
      this.prisma.customer.count({ where: { userId, kind: 'CLIENT' } }),
      this.prisma.customer.count({ where: { userId, kind: 'SUPPLIER' } }),
    ]);
    const isPremium = isPremiumActive(user);

    return {
      plan: isPremium ? 'PREMIUM' : 'FREE',
      planExpiresAt: user.planExpiresAt,
      customerCount,
      supplierCount,
      customerLimit: isPremium ? null : FREE_PLAN_CUSTOMER_LIMIT,
      monthlyPriceFcfa: PREMIUM_MONTHLY_PRICE_FCFA,
      paymentsAvailable: this.mobileMoneyService.isOperational(),
    };
  }

  /**
   * Demande de paiement de l'abonnement via Mobile Money. En l'absence
   * d'agregateur reel configure (MOMO_API_KEY), le paiement est simule et
   * l'abonnement Premium est active immediatement pour permettre de tester
   * le parcours complet ; des qu'un agregateur reel est branche, l'activation
   * devra etre deplacee vers la confirmation du webhook de paiement.
   */
  async upgrade(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('Utilisateur introuvable');
    }

    // L'activation "simulee" ci-dessous offre Premium sans paiement : elle ne
    // doit exister qu'en dev/test (assertOperational refuse en production tant
    // qu'aucun agregateur reel n'est branche).
    this.mobileMoneyService.assertOperational();

    const result = await this.mobileMoneyService.requestPayment({
      phone: user.phone,
      amount: PREMIUM_MONTHLY_PRICE_FCFA,
      debtId: `subscription-${userId}`,
      customerName: user.businessName,
      businessName: 'Carné',
    });

    if (result.simulated) {
      const planExpiresAt = new Date();
      planExpiresAt.setDate(planExpiresAt.getDate() + PREMIUM_DURATION_DAYS);
      await this.prisma.user.update({
        where: { id: userId },
        data: { plan: 'PREMIUM', planExpiresAt },
      });
      return {
        activated: true,
        simulated: true,
        planExpiresAt,
        message:
          "Mode test : aucun agregateur Mobile Money reel n'est configure, " +
          "l'abonnement Premium a ete active directement pour vous permettre " +
          'de tester. En production, il ne sera active qu\'apres confirmation ' +
          'reelle du paiement.',
      };
    }

    return {
      activated: false,
      simulated: false,
      reference: result.reference,
      message: result.message,
    };
  }
}
