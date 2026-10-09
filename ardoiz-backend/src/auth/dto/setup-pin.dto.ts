import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsNotEmpty, IsString, Matches, MaxLength } from 'class-validator';

export class SetupPinDto {
  @ApiProperty({ description: 'Jeton temporaire recu apres verification OTP' })
  @IsString()
  @IsNotEmpty()
  otpSessionToken!: string;

  @ApiProperty({ example: 'Boutique Fatou' })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  businessName!: string;

  @ApiProperty({ example: '1234', description: 'Code PIN a 4 chiffres' })
  @Matches(/^\d{4}$/, { message: 'Le PIN doit contenir exactement 4 chiffres' })
  pin!: string;

  @ApiProperty({
    example: '2026-10-06',
    description: "Version des conditions d'utilisation et de la politique de confidentialite acceptees (consentement explicite, obligatoire)",
  })
  @IsString()
  @MaxLength(32)
  termsVersion!: string;
}
