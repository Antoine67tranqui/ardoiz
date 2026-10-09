import { ApiPropertyOptional } from '@nestjs/swagger';
import { ReminderChannel } from '@prisma/client';
import { IsEnum, IsOptional } from 'class-validator';

export class SendReminderDto {
  @ApiPropertyOptional({ enum: ReminderChannel })
  @IsOptional()
  @IsEnum(ReminderChannel)
  channel?: ReminderChannel;
}
