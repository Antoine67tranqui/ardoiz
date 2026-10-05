import { ApiProperty, ApiPropertyOptional, OmitType, PartialType } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { CashType } from '@prisma/client';
import { IsDateString, IsEnum, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { MAX_AMOUNT_FCFA } from '../../common/constants';

export class CreateCashEntryDto {
  @ApiPropertyOptional({ description: 'Identifiant genere par le client (UUID v4) : creation idempotente' })
  @IsOptional()
  @IsUUID('4')
  id?: string;

  @ApiProperty({ enum: CashType, description: 'SALE : vente au comptant. EXPENSE : depense.' })
  @IsEnum(CashType)
  type!: CashType;

  @ApiProperty({ example: 1500, description: 'Montant en FCFA' })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(MAX_AMOUNT_FCFA)
  amount!: number;

  @ApiPropertyOptional({ example: 'Sacs de riz', description: 'Libelle libre' })
  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @MaxLength(200)
  label?: string;

  @ApiPropertyOptional({ example: 'Alimentation' })
  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @MaxLength(50)
  category?: string;

  @ApiPropertyOptional({ description: "Date de l'operation (bornee a [maintenant - 366 jours ; maintenant])" })
  @IsOptional()
  @IsDateString()
  occurredAt?: string;
}

// Identifiant et nature (vente/depense) ne se modifient pas : on supprime et on ressaisit.
export class UpdateCashEntryDto extends PartialType(OmitType(CreateCashEntryDto, ['id', 'type'] as const)) {}
