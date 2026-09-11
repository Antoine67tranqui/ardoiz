import { Module } from '@nestjs/common';
import { RemindersService } from './reminders.service';
import { RemindersController } from './reminders.controller';
import { RemindersCron } from './reminders.cron';
import { ReminderRulesService } from './reminder-rules.service';
import { ReminderRulesController } from './reminder-rules.controller';
import { NotificationsModule } from '../notifications/notifications.module';
import { DebtsModule } from '../debts/debts.module';

@Module({
  imports: [NotificationsModule, DebtsModule],
  controllers: [RemindersController, ReminderRulesController],
  providers: [RemindersService, RemindersCron, ReminderRulesService],
  exports: [RemindersService],
})
export class RemindersModule {}
