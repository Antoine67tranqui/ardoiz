import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as crypto from 'crypto';

export interface MomoPaymentRequestResult {
  reference: string;
  simulated: boolean;
  message: string;
}

/**
 * Abstraction sur l'agregateur Mobile Money (CinetPay / PayDunya). Tant
 * qu'aucune cle API reelle n'est fournie (MOMO_API_KEY absent), la demande
 * de paiement est simulee et journalisee cote serveur, comme pour les SMS
 * OTP (NotificationsService), afin de rester testable de bout en bout sans
 * compte agregateur reel.
 */
@Injectable()
export class MobileMoneyService {
  private readonly logger = new Logger(MobileMoneyService.name);

  constructor(private readonly config: ConfigService) {}

  isConfigured(): boolean {
    return Boolean(this.config.get<string>('MOMO_API_KEY'));
  }

  async requestPayment(params: {
    phone: string;
    amount: number;
    debtId: string;
    customerName: string;
    businessName: string;
  }): Promise<MomoPaymentRequestResult> {
    if (!this.isConfigured()) {
      const reference = `SIM-${crypto.randomUUID()}`;
      this.logger.warn(
        `[MOMO SIMULE] Demande de paiement de ${params.amount} FCFA envoyee a ${params.phone} ` +
          `(${params.customerName}) pour le compte de ${params.businessName}. Reference: ${reference}`,
      );
      return {
        reference,
        simulated: true,
        message:
          'Aucun agregateur Mobile Money configure : demande simulee. ' +
          'Renseignez MOMO_API_KEY et MOMO_SITE_ID pour activer les paiements reels.',
      };
    }

    // Integration reelle a brancher ici (ex: CinetPay "Payin" / PayDunya
    // checkout API) une fois MOMO_API_KEY / MOMO_SITE_ID renseignes dans
    // .env. La reponse de l'agregateur doit fournir une reference de
    // transaction, confirmee ensuite via le webhook /webhooks/mobile-money.
    throw new Error(
      "Integration Mobile Money reelle non implementee. Fournissez les details de l'agregateur (CinetPay/PayDunya) pour la brancher.",
    );
  }
}
