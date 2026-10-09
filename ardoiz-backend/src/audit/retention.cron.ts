import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from './audit.service';

/** Purge quotidienne : ce qui n'a plus de raison d'etre conserve est supprime. */
@Injectable()
export class RetentionCron {
  private readonly logger = new Logger(RetentionCron.name);

  constructor(
    private readonly audit: AuditService,
    private readonly prisma: PrismaService,
  ) {}

  @Cron('30 3 * * *')
  async run(): Promise<{ auditLogs: number; otpResidues: number }> {
    const auditLogs = await this.audit.purgeExpired();
    // Empreinte d'un code SMS expire depuis plus d'un jour : plus aucune utilite.
    const { count: otpResidues } = await this.prisma.user.updateMany({
      where: { otpExpiresAt: { lt: new Date(Date.now() - 24 * 3600 * 1000) }, otpCode: { not: null } },
      data: { otpCode: null, otpExpiresAt: null, otpFailedAttempts: 0 },
    });
    this.logger.log(`Purge: ${auditLogs} entree(s) de journal, ${otpResidues} code(s) SMS expire(s)`);
    return { auditLogs, otpResidues };
  }
}
