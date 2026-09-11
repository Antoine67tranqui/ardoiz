import { Body, Controller, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { ReminderChannel } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { RemindersService } from './reminders.service';

@ApiTags('reminders')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('debts/:debtId/reminders')
export class RemindersController {
  constructor(private readonly remindersService: RemindersService) {}

  @Post()
  send(
    @CurrentUser() user: AuthenticatedUser,
    @Param('debtId') debtId: string,
    @Body('channel') channel?: ReminderChannel,
  ) {
    return this.remindersService.sendManualReminder(user.id, debtId, channel);
  }
}
