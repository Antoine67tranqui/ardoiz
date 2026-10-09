import { ApiProperty } from '@nestjs/swagger';
import { Matches } from 'class-validator';

export class DeleteAccountDto {
  @ApiProperty({ example: '1234', description: 'PIN a 4 chiffres, confirmation de la suppression definitive' })
  @Matches(/^\d{4}$/, { message: 'Le PIN doit contenir exactement 4 chiffres' })
  pin!: string;
}
