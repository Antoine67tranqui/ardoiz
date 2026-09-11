import { ApiProperty } from '@nestjs/swagger';
import { IsPhoneNumber } from 'class-validator';

export class RequestOtpDto {
  @ApiProperty({ example: '+22997000000' })
  @IsPhoneNumber(undefined, { message: 'Numero de telephone invalide' })
  phone!: string;
}
