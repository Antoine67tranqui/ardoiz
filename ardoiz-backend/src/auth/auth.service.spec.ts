import * as bcrypt from 'bcrypt';
import { UnauthorizedException } from '@nestjs/common';
import { AuthService } from './auth.service';

describe('AuthService.login (verrouillage PIN)', () => {
  const PIN = '1234';
  let pinHash: string;

  beforeAll(async () => {
    pinHash = await bcrypt.hash(PIN, 10);
  });

  const buildUser = (overrides: Partial<Record<string, unknown>> = {}) => ({
    id: 'user-1',
    phone: '+22990000000',
    pinHash,
    pinFailedAttempts: 0,
    pinLockedUntil: null,
    ...overrides,
  });

  const buildDeps = (user: ReturnType<typeof buildUser>) => {
    const updatedUser = { ...user };
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue(user),
        update: jest.fn().mockImplementation(({ data }) => {
          Object.assign(updatedUser, data);
          return Promise.resolve(updatedUser);
        }),
      },
    };
    const jwt = { sign: jest.fn().mockReturnValue('token') };
    const config = { get: jest.fn().mockReturnValue('secret') };
    const notifications = {};
    const service = new AuthService(prisma as any, jwt as any, config as any, notifications as any);
    return { service, prisma };
  };

  it('rejette un mauvais PIN et incremente le compteur d\'echecs', async () => {
    const { service, prisma } = buildDeps(buildUser());

    await expect(service.login('+22990000000', '0000')).rejects.toThrow(UnauthorizedException);

    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ pinFailedAttempts: 1 }) }),
    );
  });

  it('verrouille le compte apres 5 echecs consecutifs', async () => {
    const { service, prisma } = buildDeps(buildUser({ pinFailedAttempts: 4 }));

    await expect(service.login('+22990000000', '0000')).rejects.toThrow(/verrouille/);

    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ pinFailedAttempts: 0, pinLockedUntil: expect.any(Date) }),
      }),
    );
  });

  it('refuse la connexion tant que le compte est verrouille, meme avec le bon PIN', async () => {
    const lockedUntil = new Date(Date.now() + 5 * 60 * 1000);
    const { service } = buildDeps(buildUser({ pinLockedUntil: lockedUntil }));

    await expect(service.login('+22990000000', PIN)).rejects.toThrow(/tentatives/);
  });

  it('reinitialise le compteur d\'echecs apres une connexion reussie', async () => {
    const { service, prisma } = buildDeps(buildUser({ pinFailedAttempts: 3 }));

    const result = await service.login('+22990000000', PIN);

    expect(result.accessToken).toBe('token');
    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { pinFailedAttempts: 0, pinLockedUntil: null },
      }),
    );
  });
});
