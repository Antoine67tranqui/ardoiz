import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export type AuditAction =
  | 'ACCOUNT_CREATED'
  | 'LOGIN'
  | 'PIN_LOCKED'
  | 'PIN_CHANGED'
  | 'LOGOUT'
  | 'CONSENT_ACCEPTED'
  | 'DATA_EXPORT'
  | 'CUSTOMER_EXPORT';

/** Duree de conservation du journal d'activite. */
export const AUDIT_RETENTION_DAYS = 365;

/**
 * Journal d'activite du compte : ce qui s'est passe et quand, JAMAIS d'adresse
 * IP ni de donnee du carnet. Une panne du journal ne doit jamais empecher une
 * action de l'utilisateur (connexion, export) : l'echec est consigne puis ignore.
 */
@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  async record(userId: string, action: AuditAction): Promise<void> {
    try {
      await this.prisma.auditLog.create({ data: { userId, action } });
    } catch (error) {
      this.logger.error(`Journal d'activite indisponible (${action})`, error as Error);
    }
  }

  /** Les 100 derniers evenements, du plus recent au plus ancien. */
  async recent(userId: string) {
    const logs = await this.prisma.auditLog.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 100,
      select: { action: true, createdAt: true },
    });
    return logs;
  }

  /** Purge de ce qui depasse la duree de conservation. */
  async purgeExpired(now: Date = new Date()): Promise<number> {
    const limit = new Date(now.getTime() - AUDIT_RETENTION_DAYS * 24 * 3600 * 1000);
    const { count } = await this.prisma.auditLog.deleteMany({ where: { createdAt: { lt: limit } } });
    return count;
  }
}
