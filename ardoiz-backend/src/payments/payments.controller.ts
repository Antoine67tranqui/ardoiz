import { BadRequestException, Body, Controller, Post, UseGuards } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { PaymentsService } from './payments.service';
import { CreatePaymentDto } from './dto/create-payment.dto';
import { RequestMomoPaymentDto } from './dto/request-momo-payment.dto';
import { MobileMoneyService } from './mobile-money.service';
import { DebtsService } from '../debts/debts.service';

@ApiTags('payments')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('payments')
export class PaymentsController {
  constructor(
    private readonly paymentsService: PaymentsService,
    private readonly mobileMoneyService: MobileMoneyService,
    private readonly debtsService: DebtsService,
  ) {}

  @Post()
  create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreatePaymentDto) {
    return this.paymentsService.createManual(user.id, dto);
  }

  @Post('momo-request')
  async requestMomoPayment(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RequestMomoPaymentDto,
  ) {
    const debt = await this.debtsService.getOwnedDebt(user.id, dto.debtId);
    if (!debt.customer.phone) {
      throw new BadRequestException("Ce client n'a pas de numero de telephone enregistre");
    }

    const totalPaid = debt.payments.reduce(
      (sum, p) => sum.plus(p.amount),
      new Prisma.Decimal(0),
    );
    const outstanding = new Prisma.Decimal(debt.amount).minus(totalPaid);

    return this.mobileMoneyService.requestPayment({
      phone: debt.customer.phone,
      amount: outstanding.toNumber(),
      debtId: debt.id,
      customerName: debt.customer.name,
      businessName: user.businessName,
    });
  }
}
