import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { PaymentMethod } from '@prisma/client';
import { IsDateString, IsEnum, IsNumber, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { MAX_AMOUNT_FCFA } from '../../common/constants';

export class CreatePaymentDto {
  @ApiPropertyOptional({
    description:
      "Identifiant genere par le client (UUID v4) : rend la creation idempotente, un meme envoi rejoue apres une coupure reseau ne cree jamais de doublon",
  })
  @IsOptional()
  @IsUUID('4')
  id?: string;

  @ApiProperty({ description: 'Identifiant de la dette remboursee' })
  @IsUUID()
  debtId!: string;

  @ApiProperty({ example: 1000 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  @Max(MAX_AMOUNT_FCFA)
  amount!: number;

  @ApiProperty({ enum: PaymentMethod, example: PaymentMethod.CASH })
  @IsEnum(PaymentMethod)
  method!: PaymentMethod;

  @ApiPropertyOptional({ description: "Date du remboursement sur l'appareil (borne a [maintenant - 366 jours ; maintenant])" })
  @IsOptional()
  @IsDateString()
  paidAt?: string;
}
