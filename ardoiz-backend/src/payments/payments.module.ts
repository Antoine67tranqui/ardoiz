import { Module } from '@nestjs/common';
import { PaymentsService } from './payments.service';
import { PaymentsController } from './payments.controller';
import { MobileMoneyController } from './mobile-money.controller';
import { MobileMoneyService } from './mobile-money.service';
import { DebtsModule } from '../debts/debts.module';

@Module({
  imports: [DebtsModule],
  controllers: [PaymentsController, MobileMoneyController],
  providers: [PaymentsService, MobileMoneyService],
  exports: [PaymentsService, MobileMoneyService],
})
export class PaymentsModule {}
