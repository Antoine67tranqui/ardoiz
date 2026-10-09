import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsEnum, IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { PartyKind } from '@prisma/client';

export type CustomerSortField = 'name' | 'balance' | 'createdAt';

export class QueryCustomersDto {
  @ApiPropertyOptional({ enum: PartyKind, description: 'Ne retourner que les clients ou que les fournisseurs (tous par defaut)' })
  @IsOptional()
  @IsEnum(PartyKind)
  kind?: PartyKind;

  @ApiPropertyOptional({ description: 'Recherche par nom ou numero de telephone' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  search?: string;

  @ApiPropertyOptional({
    enum: ['name', 'balance', 'createdAt'],
    default: 'createdAt',
    description: 'Champ de tri',
  })
  @IsOptional()
  @IsIn(['name', 'balance', 'createdAt'])
  sortBy?: CustomerSortField;

  @ApiPropertyOptional({ enum: ['asc', 'desc'], default: 'desc' })
  @IsOptional()
  @IsIn(['asc', 'desc'])
  order?: 'asc' | 'desc';

  @ApiPropertyOptional({
    description: 'Ne retourner que les clients ayant au moins une dette en retard',
  })
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  @IsBoolean()
  overdueOnly?: boolean;
}
