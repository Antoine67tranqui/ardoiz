import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  HttpStatus,
  Param,
  Post,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Response } from 'express';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { PaymentsService } from './payments.service';
import { CreatePaymentDto } from './dto/create-payment.dto';
import { RequestMomoPaymentDto } from './dto/request-momo-payment.dto';
import { MobileMoneyService } from './mobile-money.service';
import { DebtsService } from '../debts/debts.service';
import { outstandingOf } from '../common/money';

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

  /** 201 a la creation, 200 si un envoi rejoue (meme `id` client) renvoie le paiement existant. */
  @Post()
  async create(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreatePaymentDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const { payment, created } = await this.paymentsService.createManual(user.id, dto);
    if (!created) res.status(HttpStatus.OK);
    return payment;
  }

  @Delete(':id')
  remove(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string) {
    return this.paymentsService.remove(user.id, id);
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

    const outstanding = outstandingOf(debt.amount, debt.payments);
    if (outstanding.lessThanOrEqualTo(0)) {
      throw new BadRequestException('Cette dette est deja soldee');
    }

    return this.mobileMoneyService.requestPayment({
      phone: debt.customer.phone,
      amount: outstanding.toNumber(),
      debtId: debt.id,
      customerName: debt.customer.name,
      businessName: user.businessName,
    });
  }
}
