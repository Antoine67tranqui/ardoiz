import { PaymentsService } from './payments.service';

describe('PaymentsService.createFromMobileMoneyWebhook', () => {
  const buildPrismaMock = (existingPayment: any = null) => ({
    payment: {
      findUnique: jest.fn().mockResolvedValue(existingPayment),
      create: jest.fn().mockImplementation(({ data }) =>
        Promise.resolve({ id: 'payment-1', ...data }),
      ),
    },
    debt: {
      findUnique: jest.fn().mockResolvedValue({ id: 'debt-1', amount: 5000 }),
    },
  });

  const buildDebtsServiceMock = () => ({
    recomputeStatus: jest.fn().mockResolvedValue({ id: 'debt-1', status: 'PARTIAL' }),
    getOwnedDebt: jest.fn(),
  });

  it('cree un nouveau paiement quand la reference de transaction est inedite', async () => {
    const prisma = buildPrismaMock(null);
    const debtsService = buildDebtsServiceMock();
    const service = new PaymentsService(prisma as any, debtsService as any);

    const result = await service.createFromMobileMoneyWebhook({
      debtId: 'debt-1',
      amount: 2000,
      transactionRef: 'TX-123',
    });

    expect(prisma.payment.create).toHaveBeenCalledTimes(1);
    expect(debtsService.recomputeStatus).toHaveBeenCalledWith('debt-1');
    expect(result).toMatchObject({ transactionRef: 'TX-123' });
  });

  it('ne cree pas de doublon si le webhook est rejoue avec la meme reference', async () => {
    const existing = { id: 'payment-1', transactionRef: 'TX-123', amount: 2000 };
    const prisma = buildPrismaMock(existing);
    const debtsService = buildDebtsServiceMock();
    const service = new PaymentsService(prisma as any, debtsService as any);

    const result = await service.createFromMobileMoneyWebhook({
      debtId: 'debt-1',
      amount: 2000,
      transactionRef: 'TX-123',
    });

    expect(prisma.payment.create).not.toHaveBeenCalled();
    expect(debtsService.recomputeStatus).not.toHaveBeenCalled();
    expect(result).toBe(existing);
  });
});
