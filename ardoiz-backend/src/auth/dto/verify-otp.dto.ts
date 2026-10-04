import { ApiProperty } from '@nestjs/swagger';
import { IsPhoneNumber, Length } from 'class-validator';

export class VerifyOtpDto {
  @ApiProperty({ example: '+2290167077027' })
  @IsPhoneNumber(undefined, { message: 'Numero de telephone invalide' })
  phone!: string;

  @ApiProperty({ example: '123456' })
  @Length(6, 6, { message: 'Le code OTP doit contenir 6 chiffres' })
  code!: string;
}
