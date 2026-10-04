import crypto from 'crypto';
import { AuthService } from './auth.service';

describe('AuthService.requestOtp (generation du code)', () => {
  const phone = '+2290167000001';

  const build = () => {
    const prisma = { user: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) } };
    const notifications = { sendOtp: jest.fn().mockResolvedValue(undefined) };
    const config = { get: jest.fn((key: string) => (key === 'JWT_OTP_SECRET' ? 'secret-de-test' : undefined)) };
    return { service: new AuthService(prisma as any, {} as any, config as any, notifications as any), prisma, notifications };
  };

  it('utilise un generateur cryptographique (crypto.randomInt), jamais Math.random()', async () => {
    // Import par defaut : on espionne l'objet module reel que le service utilise.
    const randomInt = jest.spyOn(crypto, 'randomInt').mockReturnValue(123456 as never);
    const mathRandom = jest.spyOn(Math, 'random');
    const { service, notifications } = build();

    const result = await service.requestOtp(phone);

    expect(randomInt).toHaveBeenCalledWith(100000, 1000000);
    expect(mathRandom).not.toHaveBeenCalled();
    expect(notifications.sendOtp).toHaveBeenCalledWith(phone, '123456');
    expect(result.devCode).toBe('123456');
    randomInt.mockRestore();
    mathRandom.mockRestore();
  });

  it('ne persiste que l\'empreinte du code, jamais le code', async () => {
    const { service, prisma } = build();

    await service.requestOtp(phone);

    const stored = prisma.user.updateMany.mock.calls[0][0].data.otpCode as string;
    expect(stored).toMatch(/^[0-9a-f]{64}$/);
  });
});
