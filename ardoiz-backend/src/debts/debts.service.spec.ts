import { DebtsService } from './debts.service';

describe('DebtsService.recomputeStatus', () => {
  const buildPrismaMock = (payments: { amount: number }[], debtAmount: number) => ({
    debt: {
      findUniqueOrThrow: jest.fn().mockResolvedValue({
        id: 'debt-1',
        amount: debtAmount,
        payments,
      }),
      update: jest.fn().mockImplementation(({ data }) =>
        Promise.resolve({ id: 'debt-1', status: data.status }),
      ),
    },
  });

  it('marque la dette PENDING quand aucun paiement n\'a ete recu', async () => {
    const prisma = buildPrismaMock([], 5000);
    const service = new DebtsService(prisma as any);

    const result = await service.recomputeStatus('debt-1');

    expect(result.status).toBe('PENDING');
  });

  it('marque la dette PARTIAL quand un paiement partiel a ete recu', async () => {
    const prisma = buildPrismaMock([{ amount: 2000 }], 5000);
    const service = new DebtsService(prisma as any);

    const result = await service.recomputeStatus('debt-1');

    expect(result.status).toBe('PARTIAL');
  });

  it('marque la dette PAID quand la somme des paiements couvre le montant du', async () => {
    const prisma = buildPrismaMock([{ amount: 3000 }, { amount: 2000 }], 5000);
    const service = new DebtsService(prisma as any);

    const result = await service.recomputeStatus('debt-1');

    expect(result.status).toBe('PAID');
  });

  it('marque la dette PAID meme en cas de trop-percu', async () => {
    const prisma = buildPrismaMock([{ amount: 5500 }], 5000);
    const service = new DebtsService(prisma as any);

    const result = await service.recomputeStatus('debt-1');

    expect(result.status).toBe('PAID');
  });
});
