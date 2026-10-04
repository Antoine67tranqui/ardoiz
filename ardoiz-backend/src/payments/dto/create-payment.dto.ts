import { ApiProperty } from '@nestjs/swagger';
import { PaymentMethod } from '@prisma/client';
import { IsEnum, IsNumber, IsUUID, Max, Min } from 'class-validator';
import { MAX_AMOUNT_FCFA } from '../../common/constants';

export class CreatePaymentDto {
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
}
