import { Body, Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { ReminderRulesService } from './reminder-rules.service';
import { UpsertReminderRuleDto } from './dto/upsert-reminder-rule.dto';

@ApiTags('reminder-rules')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('reminders/rules')
export class ReminderRulesController {
  constructor(private readonly reminderRulesService: ReminderRulesService) {}

  @Get()
  list(@CurrentUser() user: AuthenticatedUser) {
    return this.reminderRulesService.listForUser(user.id);
  }

  @Post()
  upsert(@CurrentUser() user: AuthenticatedUser, @Body() dto: UpsertReminderRuleDto) {
    return this.reminderRulesService.upsert(user.id, dto);
  }

  @Delete(':id')
  remove(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string) {
    return this.reminderRulesService.remove(user.id, id);
  }
}
