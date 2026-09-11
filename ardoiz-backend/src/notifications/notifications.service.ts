import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export type ReminderChannel = 'SMS' | 'WHATSAPP';

/**
 * Couche d'abstraction sur les fournisseurs SMS (Africa's Talking / Twilio)
 * et WhatsApp Business API. En l'absence de cles API (environnement de dev),
 * les envois sont simules et logges pour ne jamais bloquer le flux applicatif.
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(private readonly config: ConfigService) {}

  async sendOtp(phone: string, code: string): Promise<void> {
    await this.sendSms(phone, `Ardoiz: votre code de verification est ${code}. Valable 5 minutes.`);
  }

  async sendDebtReminder(params: {
    phone: string;
    channel: ReminderChannel;
    customerName: string;
    amount: string;
    businessName: string;
    tone?: 'GENTLE' | 'NEUTRAL' | 'FIRM';
  }): Promise<void> {
    const message = this.buildReminderMessage(params);

    if (params.channel === 'WHATSAPP') {
      await this.sendWhatsApp(params.phone, message);
    } else {
      await this.sendSms(params.phone, message);
    }
  }

  /**
   * Ton du message adapte a l'etape de la relance : courtois avant echeance,
   * neutre le jour meme, ferme en cas de retard confirme.
   */
  private buildReminderMessage(params: {
    customerName: string;
    amount: string;
    businessName: string;
    tone?: 'GENTLE' | 'NEUTRAL' | 'FIRM';
  }): string {
    switch (params.tone) {
      case 'GENTLE':
        return `Bonjour ${params.customerName}, petit rappel amical : votre ardoise de ${params.amount} FCFA chez ${params.businessName} arrive bientot a echeance. Merci d'y penser !`;
      case 'FIRM':
        return `Bonjour ${params.customerName}, votre ardoise de ${params.amount} FCFA chez ${params.businessName} est en retard de paiement. Merci de regulariser rapidement via Mobile Money pour eviter toute suspension de credit.`;
      case 'NEUTRAL':
      default:
        return `Bonjour ${params.customerName}, vous avez une ardoise de ${params.amount} FCFA chez ${params.businessName}. Merci de regulariser via Mobile Money des que possible.`;
    }
  }

  private async sendSms(phone: string, message: string): Promise<void> {
    const apiKey = this.config.get<string>('SMS_API_KEY');
    const username = this.config.get<string>('SMS_USERNAME');
    if (!apiKey || !username) {
      this.logger.warn(`[SMS SIMULE] -> ${phone}: ${message}`);
      return;
    }

    // Le compte "sandbox" d'Africa's Talking utilise un domaine dedie pour
    // les tests (credit gratuit, numeros de test), distinct de la prod.
    const host =
      username === 'sandbox'
        ? 'https://api.sandbox.africastalking.com'
        : 'https://api.africastalking.com';

    const senderId = this.config.get<string>('SMS_SENDER_ID');
    const body = new URLSearchParams({ username, to: phone, message });
    if (senderId) body.set('from', senderId);

    try {
      const response = await fetch(`${host}/version1/messaging`, {
        method: 'POST',
        headers: {
          apiKey,
          'Content-Type': 'application/x-www-form-urlencoded',
          Accept: 'application/json',
        },
        body,
      });

      const data = await response.json().catch(() => null);
      const recipient = data?.SMSMessageData?.Recipients?.[0];

      if (!response.ok || (recipient && recipient.status !== 'Success')) {
        throw new Error(
          `Reponse Africa's Talking invalide: ${response.status} ${JSON.stringify(data)}`,
        );
      }

      this.logger.log(`[SMS] -> ${phone}: envoye (${recipient?.messageId ?? 'ok'})`);
    } catch (error) {
      this.logger.error(`[SMS] Echec d'envoi vers ${phone}`, error as Error);
      throw error;
    }
  }

  private async sendWhatsApp(phone: string, message: string): Promise<void> {
    const token = this.config.get<string>('WHATSAPP_API_TOKEN');
    if (!token) {
      this.logger.warn(`[WHATSAPP SIMULE] -> ${phone}: ${message}`);
      return;
    }
    // Integration reelle WhatsApp Business Cloud API a brancher ici.
    this.logger.log(`[WHATSAPP] -> ${phone}: ${message}`);
  }
}
