import { ApiProperty } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';

export class RequestMomoPaymentDto {
  @ApiProperty({ description: 'Identifiant de la dette a faire rembourser via Mobile Money' })
  @IsUUID()
  debtId!: string;
}
