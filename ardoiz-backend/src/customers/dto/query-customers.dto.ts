import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsIn, IsOptional, IsString } from 'class-validator';

export type CustomerSortField = 'name' | 'balance' | 'createdAt';

export class QueryCustomersDto {
  @ApiPropertyOptional({ description: 'Recherche par nom ou numero de telephone' })
  @IsOptional()
  @IsString()
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
