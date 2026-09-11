import { IsNumber, IsString, IsUUID, Min } from 'class-validator';

export class MobileMoneyWebhookDto {
  @IsUUID()
  debtId!: string;

  @IsNumber()
  @Min(1)
  amount!: number;

  @IsString()
  transactionRef!: string;
}
