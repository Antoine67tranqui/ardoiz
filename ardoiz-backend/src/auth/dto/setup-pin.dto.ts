import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString, Matches } from 'class-validator';

export class SetupPinDto {
  @ApiProperty({ description: 'Jeton temporaire recu apres verification OTP' })
  @IsString()
  @IsNotEmpty()
  otpSessionToken!: string;

  @ApiProperty({ example: 'Boutique Fatou' })
  @IsString()
  @IsNotEmpty()
  businessName!: string;

  @ApiProperty({ example: '1234', description: 'Code PIN a 4 chiffres' })
  @Matches(/^\d{4}$/, { message: 'Le PIN doit contenir exactement 4 chiffres' })
  pin!: string;
}
