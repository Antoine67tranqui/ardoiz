import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsDateString, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateDebtDto {
  @ApiProperty({ description: 'Identifiant du client concerne' })
  @IsUUID()
  customerId!: string;

  @ApiProperty({ example: 2500, description: 'Montant de la dette en FCFA' })
  @IsNumber()
  @Min(1)
  amount!: number;

  @ApiPropertyOptional({ example: 'Riz + huile' })
  @IsOptional()
  @IsString()
  reason?: string;

  @ApiPropertyOptional({ example: 'Alimentation', description: 'Categorie de produit, pour le tableau de bord' })
  @IsOptional()
  @IsString()
  category?: string;

  @ApiPropertyOptional({ example: '2026-07-15', description: 'Date a laquelle le client doit avoir rembourse' })
  @IsOptional()
  @IsDateString()
  dueDate?: string;
}
