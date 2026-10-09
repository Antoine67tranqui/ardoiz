import * as crypto from 'crypto';
import { BadRequestException, UnauthorizedException } from '@nestjs/common';
import { MobileMoneyController } from './mobile-money.controller';

describe('MobileMoneyController.handleWebhook (verification de signature)', () => {
  const SECRET = 'test-webhook-secret';
  const dto = { debtId: 'debt-1', amount: 2000, transactionRef: 'TX-123' };

  const buildController = () => {
    const paymentsService = { createFromMobileMoneyWebhook: jest.fn().mockResolvedValue({ id: 'payment-1' }) };
    const config = { get: jest.fn().mockReturnValue(SECRET) };
    return { controller: new MobileMoneyController(paymentsService as any, config as any), paymentsService };
  };

  const sign = (rawBody: Buffer) =>
    crypto.createHmac('sha256', SECRET).update(rawBody).digest('hex');

  it('accepte une signature calculee sur le corps brut exact recu', async () => {
    const { controller, paymentsService } = buildController();
    // Le corps brut envoye par un vrai agregateur n'a pas forcement le meme
    // ordre de cles/espacement que la DTO re-serialisee cote serveur.
    const rawBody = Buffer.from('{"transactionRef":"TX-123","debtId":"debt-1","amount":2000}');
    const signature = sign(rawBody);

    await controller.handleWebhook(dto as any, signature, { rawBody } as any);

    expect(paymentsService.createFromMobileMoneyWebhook).toHaveBeenCalledWith(dto);
  });

  it('rejette une signature calculee sur JSON.stringify(dto) si elle differe du corps brut', async () => {
    const { controller } = buildController();
    const rawBody = Buffer.from('{"transactionRef":"TX-123","debtId":"debt-1","amount":2000}');
    // Reproduit l'ancien bug : signer le DTO re-serialise plutot que les
    // octets reellement envoyes doit maintenant echouer.
    const wrongSignature = sign(Buffer.from(JSON.stringify(dto)));

    await expect(
      controller.handleWebhook(dto as any, wrongSignature, { rawBody } as any),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('rejette une signature invalide', async () => {
    const { controller } = buildController();
    const rawBody = Buffer.from(JSON.stringify(dto));

    await expect(
      controller.handleWebhook(dto as any, 'signature-bidon', { rawBody } as any),
    ).rejects.toThrow(UnauthorizedException);
  });

  it("rejette si le corps brut n'est pas disponible", async () => {
    const { controller } = buildController();

    await expect(
      controller.handleWebhook(dto as any, 'une-signature', { rawBody: undefined } as any),
    ).rejects.toThrow(BadRequestException);
  });
});
