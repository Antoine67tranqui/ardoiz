import { NotificationsService } from './notifications.service';

describe('NotificationsService (fournisseurs absents)', () => {
  const build = (env: Record<string, string>) =>
    new NotificationsService({ get: (key: string) => env[key] } as any);
  const reminder = (channel: 'SMS' | 'WHATSAPP') => ({
    phone: '+2290167000001',
    channel,
    customerName: 'Aicha',
    amount: '1000',
    businessName: 'Boutique',
  });

  describe('hors production : envois simules (jamais bloquants)', () => {
    it('simule le SMS et le WhatsApp', async () => {
      const service = build({ NODE_ENV: 'development' });
      await expect(service.sendOtp('+2290167000001', '123456')).resolves.toBeUndefined();
      await expect(service.sendDebtReminder(reminder('SMS'))).resolves.toBeUndefined();
      await expect(service.sendDebtReminder(reminder('WHATSAPP'))).resolves.toBeUndefined();
    });
  });

  describe('en production : un fournisseur absent est une erreur, pas une simulation', () => {
    const service = build({ NODE_ENV: 'production' });

    it('refuse le SMS (OTP et relance) sans SMS_API_KEY / SMS_USERNAME', async () => {
      await expect(service.sendOtp('+2290167000001', '123456')).rejects.toThrow(/SMS non configure/);
      await expect(service.sendDebtReminder(reminder('SMS'))).rejects.toThrow(/SMS non configure/);
    });

    it('refuse le WhatsApp sans token', async () => {
      await expect(service.sendDebtReminder(reminder('WHATSAPP'))).rejects.toThrow(/WhatsApp non configure/);
    });
  });

  it("ne pretend jamais avoir envoye un WhatsApp : l'integration reelle n'existe pas encore", async () => {
    const service = build({ NODE_ENV: 'production', WHATSAPP_API_TOKEN: 'token' });
    await expect(service.sendDebtReminder(reminder('WHATSAPP'))).rejects.toThrow(/non implemente/);
  });

  it('adapte le ton du message a l\'etape de la relance', async () => {
    const send = jest.fn();
    const service = build({ NODE_ENV: 'development' });
    (service as any).sendSms = send;

    await service.sendDebtReminder({ ...reminder('SMS'), tone: 'GENTLE' });
    await service.sendDebtReminder({ ...reminder('SMS'), tone: 'NEUTRAL' });
    await service.sendDebtReminder({ ...reminder('SMS'), tone: 'FIRM' });

    const [gentle, neutral, firm] = send.mock.calls.map((c) => c[1] as string);
    expect(gentle).toMatch(/petit rappel amical/);
    expect(neutral).toMatch(/vous avez une ardoise de 1000 FCFA chez Boutique/);
    expect(firm).toMatch(/en retard de paiement/);
  });
});
