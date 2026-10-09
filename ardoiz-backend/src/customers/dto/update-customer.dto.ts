import { OmitType, PartialType } from '@nestjs/swagger';
import { CreateCustomerDto } from './create-customer.dto';

// L'identifiant et le type (client/fournisseur) ne se modifient jamais : il est exclu du DTO de mise a jour.
export class UpdateCustomerDto extends PartialType(OmitType(CreateCustomerDto, ['id', 'kind'] as const)) {}
