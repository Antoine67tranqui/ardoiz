import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { CashType } from '@prisma/client';
import { IsDateString, IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';

export class QueryCashDto {
  @ApiPropertyOptional({ description: 'Debut (inclus), ISO 8601' })
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional({ description: 'Fin (exclue), ISO 8601' })
  @IsOptional()
  @IsDateString()
  to?: string;

  @ApiPropertyOptional({ enum: CashType })
  @IsOptional()
  @IsEnum(CashType)
  type?: CashType;

  @ApiPropertyOptional({ default: 500, maximum: 1000 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1000)
  limit?: number;
}

export class QueryCashSummaryDto {
  @ApiPropertyOptional({ description: 'Debut de la periode (inclus), ISO 8601' })
  @IsDateString()
  from!: string;

  @ApiPropertyOptional({ description: 'Fin de la periode (exclue), ISO 8601' })
  @IsDateString()
  to!: string;
}
