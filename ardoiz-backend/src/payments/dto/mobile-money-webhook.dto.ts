import { IsNotEmpty, IsNumber, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { MAX_AMOUNT_FCFA } from '../../common/constants';

export class MobileMoneyWebhookDto {
  @IsUUID()
  debtId!: string;

  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  @Max(MAX_AMOUNT_FCFA)
  amount!: number;

  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  transactionRef!: string;
}
