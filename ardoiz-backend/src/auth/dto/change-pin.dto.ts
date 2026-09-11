import { ApiProperty } from '@nestjs/swagger';
import { Matches } from 'class-validator';

export class ChangePinDto {
  @ApiProperty({ example: '1234', description: 'PIN actuel a 4 chiffres' })
  @Matches(/^\d{4}$/, { message: 'Le PIN doit contenir exactement 4 chiffres' })
  currentPin!: string;

  @ApiProperty({ example: '5678', description: 'Nouveau PIN a 4 chiffres' })
  @Matches(/^\d{4}$/, { message: 'Le PIN doit contenir exactement 4 chiffres' })
  newPin!: string;
}
