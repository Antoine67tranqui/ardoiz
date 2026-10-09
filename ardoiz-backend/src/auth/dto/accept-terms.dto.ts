import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength } from 'class-validator';

export class AcceptTermsDto {
  @ApiProperty({ example: '2026-10-06', description: "Version des conditions d'utilisation et de la politique de confidentialite acceptee" })
  @IsString()
  @MaxLength(32)
  termsVersion!: string;
}
