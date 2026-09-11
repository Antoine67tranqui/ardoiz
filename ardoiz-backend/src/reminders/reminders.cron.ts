import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { RemindersService } from './reminders.service';

@Injectable()
export class RemindersCron {
  private readonly logger = new Logger(RemindersCron.name);

  constructor(private readonly remindersService: RemindersService) {}

  // Tous les jours a 8h locales : relance des dettes en attente/partielles echues.
  @Cron(CronExpression.EVERY_DAY_AT_8AM)
  async handleDailyReminders() {
    const { sent } = await this.remindersService.sendAutomaticReminders();
    this.logger.log(`Relances automatiques envoyees: ${sent}`);
  }
}
