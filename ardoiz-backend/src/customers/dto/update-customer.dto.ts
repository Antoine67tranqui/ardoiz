import { OmitType, PartialType } from '@nestjs/swagger';
import { CreateCustomerDto } from './create-customer.dto';

// L'identifiant ne se modifie jamais : il est exclu du DTO de mise a jour.
export class UpdateCustomerDto extends PartialType(OmitType(CreateCustomerDto, ['id'] as const)) {}
