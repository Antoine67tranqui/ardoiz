import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsDateString, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { MAX_AMOUNT_FCFA } from '../../common/constants';

export class CreateDebtDto {
  @ApiPropertyOptional({
    description:
      "Identifiant genere par le client (UUID v4) : rend la creation idempotente, un meme envoi rejoue apres une coupure reseau ne cree jamais de doublon",
  })
  @IsOptional()
  @IsUUID('4')
  id?: string;

  @ApiProperty({ description: 'Identifiant du client concerne' })
  @IsUUID()
  customerId!: string;

  @ApiProperty({ example: 2500, description: 'Montant de la dette en FCFA' })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  @Max(MAX_AMOUNT_FCFA)
  amount!: number;

  @ApiPropertyOptional({ example: 'Riz + huile' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;

  @ApiPropertyOptional({ example: 'Alimentation', description: 'Categorie de produit, pour le tableau de bord' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  category?: string;

  @ApiPropertyOptional({ example: '2026-07-15', description: 'Date a laquelle le client doit avoir rembourse' })
  @IsOptional()
  @IsDateString()
  dueDate?: string;

  @ApiPropertyOptional({ description: "Date de saisie sur l'appareil (borne a [maintenant - 366 jours ; maintenant])" })
  @IsOptional()
  @IsDateString()
  createdAt?: string;
}
