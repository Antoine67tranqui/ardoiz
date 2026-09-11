import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ReminderChannel, ReminderTone } from '@prisma/client';
import { IsBoolean, IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';

export class UpsertReminderRuleDto {
  @ApiProperty({
    example: -3,
    description:
      "Decalage en jours par rapport a l'echeance : negatif = rappel avant echeance, positif = relance de retard",
  })
  @IsInt()
  @Min(-30)
  @Max(60)
  offsetDays!: number;

  @ApiPropertyOptional({ enum: ReminderChannel, default: 'SMS' })
  @IsOptional()
  @IsEnum(ReminderChannel)
  channel?: ReminderChannel;

  @ApiPropertyOptional({ enum: ReminderTone, default: 'NEUTRAL' })
  @IsOptional()
  @IsEnum(ReminderTone)
  tone?: ReminderTone;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  enabled?: boolean;
}
