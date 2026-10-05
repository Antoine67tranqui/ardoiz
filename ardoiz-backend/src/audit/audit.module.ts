import { Global, Module } from '@nestjs/common';
import { AuditService } from './audit.service';
import { RetentionCron } from './retention.cron';

@Global()
@Module({ providers: [AuditService, RetentionCron], exports: [AuditService] })
export class AuditModule {}
