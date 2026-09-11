import { ApiProperty } from '@nestjs/swagger';
import { PaymentMethod } from '@prisma/client';
import { IsEnum, IsNumber, IsUUID, Min } from 'class-validator';

export class CreatePaymentDto {
  @ApiProperty({ description: 'Identifiant de la dette remboursee' })
  @IsUUID()
  debtId!: string;

  @ApiProperty({ example: 1000 })
  @IsNumber()
  @Min(1)
  amount!: number;

  @ApiProperty({ enum: PaymentMethod, example: PaymentMethod.CASH })
  @IsEnum(PaymentMethod)
  method!: PaymentMethod;
}
