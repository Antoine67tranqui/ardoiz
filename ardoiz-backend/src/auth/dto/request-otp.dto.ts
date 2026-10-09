import { ApiProperty } from '@nestjs/swagger';
import { IsPhoneNumber } from 'class-validator';

export class RequestOtpDto {
  @ApiProperty({ example: '+2290167077027' })
  @IsPhoneNumber(undefined, { message: 'Numero de telephone invalide' })
  phone!: string;
}
