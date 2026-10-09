import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsDateString, IsNumber, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { MAX_AMOUNT_FCFA } from '../../common/constants';

/** Correction d'une dette saisie par erreur. `null` efface le motif / l'echeance. */
export class UpdateDebtDto {
  @ApiPropertyOptional({ example: 3000, description: 'Ne peut pas etre inferieur aux paiements deja recus' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  @Max(MAX_AMOUNT_FCFA)
  amount?: number;

  @ApiPropertyOptional({ example: 'Riz + huile', nullable: true })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string | null;

  @ApiPropertyOptional({ example: 'Alimentation' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  category?: string;

  @ApiPropertyOptional({ example: '2026-07-15', nullable: true })
  @IsOptional()
  @IsDateString()
  dueDate?: string | null;
}
