import { ApiProperty } from '@nestjs/swagger';
import { IsPhoneNumber, Matches } from 'class-validator';

export class LoginDto {
  @ApiProperty({ example: '+22997000000' })
  @IsPhoneNumber(undefined, { message: 'Numero de telephone invalide' })
  phone!: string;

  @ApiProperty({ example: '1234' })
  @Matches(/^\d{4}$/, { message: 'Le PIN doit contenir exactement 4 chiffres' })
  pin!: string;
}
