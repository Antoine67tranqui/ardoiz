import {
  BadRequestException,
  Body,
  Controller,
  Headers,
  Post,
  UnauthorizedException,
} from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import { ConfigService } from '@nestjs/config';
import * as crypto from 'crypto';
import { PaymentsService } from './payments.service';
import { MobileMoneyWebhookDto } from './dto/mobile-money-webhook.dto';

/**
 * Endpoint public appele par l'agregateur Mobile Money (CinetPay / PayDunya)
 * lors de la confirmation d'un remboursement. Protege par verification HMAC
 * plutot que par JWT car appele par un systeme externe, pas un utilisateur connecte.
 */
@ApiExcludeController()
@Controller('webhooks/mobile-money')
export class MobileMoneyController {
  constructor(
    private readonly paymentsService: PaymentsService,
    private readonly config: ConfigService,
  ) {}

  @Post()
  async handleWebhook(
    @Body() dto: MobileMoneyWebhookDto,
    @Headers('x-momo-signature') signature: string,
  ) {
    this.verifySignature(dto, signature);

    return this.paymentsService.createFromMobileMoneyWebhook({
      debtId: dto.debtId,
      amount: dto.amount,
      transactionRef: dto.transactionRef,
    });
  }

  private verifySignature(payload: MobileMoneyWebhookDto, signature: string) {
    const secret = this.config.get<string>('MOMO_WEBHOOK_SECRET');
    if (!secret) {
      throw new BadRequestException('Webhook Mobile Money non configure');
    }
    if (!signature) {
      throw new UnauthorizedException('Signature manquante');
    }

    const expected = crypto
      .createHmac('sha256', secret)
      .update(JSON.stringify(payload))
      .digest('hex');

    const signatureBuffer = Buffer.from(signature);
    const expectedBuffer = Buffer.from(expected);
    const isValid =
      signatureBuffer.length === expectedBuffer.length &&
      crypto.timingSafeEqual(signatureBuffer, expectedBuffer);

    if (!isValid) {
      throw new UnauthorizedException('Signature de webhook invalide');
    }
  }
}
