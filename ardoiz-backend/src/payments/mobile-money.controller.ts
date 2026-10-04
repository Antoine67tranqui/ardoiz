import {
  BadRequestException,
  Body,
  Controller,
  Headers,
  Post,
  Req,
  UnauthorizedException,
} from '@nestjs/common';
import type { RawBodyRequest } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiExcludeController } from '@nestjs/swagger';
import { ConfigService } from '@nestjs/config';
import type { Request } from 'express';
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

  // Limite genereuse (trafic serveur a serveur legitime) mais presente :
  // sans elle, le endpoint est une surface illimitee pour tenter de deviner
  // le secret HMAC, meme si timingSafeEqual rend chaque tentative individuelle
  // non exploitable par mesure de temps.
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @Post()
  async handleWebhook(
    @Body() dto: MobileMoneyWebhookDto,
    @Headers('x-momo-signature') signature: string,
    @Req() req: RawBodyRequest<Request>,
  ) {
    this.verifySignature(req.rawBody, signature);

    return this.paymentsService.createFromMobileMoneyWebhook({
      debtId: dto.debtId,
      amount: dto.amount,
      transactionRef: dto.transactionRef,
    });
  }

  // Verifie le HMAC sur les octets bruts exacts recus (req.rawBody, capture
  // par `rawBody: true` dans main.ts), et non sur une re-serialisation du
  // DTO : l'agregateur signe le corps qu'il a reellement envoye, dont l'ordre
  // des champs, les espaces ou des champs additionnels retires par le
  // ValidationPipe (whitelist: true) feraient echouer une comparaison basee
  // sur JSON.stringify(dto).
  private verifySignature(rawBody: Buffer | undefined, signature: string) {
    const secret = this.config.get<string>('MOMO_WEBHOOK_SECRET');
    if (!secret) {
      throw new BadRequestException('Webhook Mobile Money non configure');
    }
    if (!signature) {
      throw new UnauthorizedException('Signature manquante');
    }
    if (!rawBody) {
      throw new BadRequestException('Corps de requete brut indisponible');
    }

    const expected = crypto.createHmac('sha256', secret).update(rawBody).digest('hex');

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
