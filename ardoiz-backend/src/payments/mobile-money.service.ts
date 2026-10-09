import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as crypto from 'crypto';
import { FeatureUnavailableException } from '../common/feature-unavailable.exception';

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

  /**
   * Les paiements reels sont-ils utilisables ? Hors production, la simulation
   * permet de tester le parcours complet. En production il faut une cle
   * d'agregateur ET une integration reelle, qui n'est pas encore branchee :
   * tant que c'est le cas, on le dit franchement plutot que de simuler un
   * paiement qui n'atteindrait jamais le client.
   */
  isOperational(): boolean {
    if (this.config.get<string>('NODE_ENV') !== 'production') return true;
    return this.isConfigured() && MobileMoneyService.REAL_INTEGRATION_IMPLEMENTED;
  }

  /** A passer a `true` quand l'appel reel a l'agregateur est branche et teste. */
  static readonly REAL_INTEGRATION_IMPLEMENTED = false;

  assertOperational(): void {
    if (!this.isOperational()) {
      throw new FeatureUnavailableException("Le paiement Mobile Money n'est pas encore disponible.");
    }
  }

  async requestPayment(params: {
    phone: string;
    amount: number;
    debtId: string;
    customerName: string;
    businessName: string;
  }): Promise<MomoPaymentRequestResult> {
    this.assertOperational();
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
    throw new FeatureUnavailableException("Le paiement Mobile Money n'est pas encore disponible.");
  }
}
