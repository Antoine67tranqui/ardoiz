import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsNumber, IsOptional, IsString, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';
import { MAX_AMOUNT_FCFA } from '../../common/constants';

export class CreateCustomerDto {
  @ApiProperty({ example: 'Aicha Traore' })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  name!: string;

  // Obligatoire : necessaire pour les relances SMS/WhatsApp et les
  // demandes de paiement Mobile Money. On evite IsPhoneNumber()
  // (libphonenumber-js), trop strict sur les numeros locaux/anciens
  // formats reels des commercants d'Afrique de l'Ouest, et on se
  // contente d'un garde-fou large.
  @ApiProperty({ example: '+229 01 67 07 70 27' })
  @Matches(/^[0-9+()\-.\s]{8,20}$/, {
    message: 'Numero de telephone invalide (8 a 20 chiffres, espaces et + acceptes)',
  })
  phone!: string;

  @ApiPropertyOptional({
    example: 20000,
    description:
      "Plafond de credit optionnel (FCFA) : au-dela, l'app alerte le commercant sans bloquer la saisie",
  })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(MAX_AMOUNT_FCFA)
  creditLimit?: number;
}
