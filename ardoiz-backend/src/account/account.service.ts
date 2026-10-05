import { BadRequestException, Injectable } from '@nestjs/common';
import { AuditService } from '../audit/audit.service';
import { CURRENT_TERMS_VERSION } from '../common/legal';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AccountService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  /** L'utilisateur a-t-il accepte la version EN VIGUEUR des conditions et de la politique ? */
  async consentStatus(userId: string) {
    const accepted = await this.prisma.consentRecord.findFirst({
      where: { userId, version: CURRENT_TERMS_VERSION },
      orderBy: { acceptedAt: 'desc' },
    });
    return { termsVersion: CURRENT_TERMS_VERSION, termsAccepted: accepted !== null, acceptedAt: accepted?.acceptedAt ?? null };
  }

  async acceptTerms(userId: string, version: string) {
    if (version !== CURRENT_TERMS_VERSION) {
      throw new BadRequestException({
        code: 'TERMS_VERSION_MISMATCH',
        message: 'Les conditions ont change : mettez a jour l\'application puis acceptez la version en vigueur.',
      });
    }
    const existing = await this.prisma.consentRecord.findFirst({ where: { userId, version } });
    if (!existing) {
      await this.prisma.consentRecord.create({ data: { userId, version } });
      await this.audit.record(userId, 'CONSENT_ACCEPTED');
    }
    return this.consentStatus(userId);
  }

  /**
   * Copie complete des donnees du commercant (droit d'acces et de portabilite) :
   * tout ce que Carne conserve a son sujet, dans un format lisible par une machine.
   * Le PIN (empreinte) et les secrets techniques n'en font pas partie.
   */
  async exportAll(userId: string) {
    const [user, customers, cashEntries, rules, consents, activity] = await Promise.all([
      this.prisma.user.findUniqueOrThrow({ where: { id: userId } }),
      this.prisma.customer.findMany({
        where: { userId },
        include: { debts: { include: { payments: true, reminders: true } } },
        orderBy: { createdAt: 'asc' },
      }),
      this.prisma.cashEntry.findMany({ where: { userId }, orderBy: { occurredAt: 'asc' } }),
      this.prisma.reminderRule.findMany({ where: { userId }, orderBy: { offsetDays: 'asc' } }),
      this.prisma.consentRecord.findMany({ where: { userId }, orderBy: { acceptedAt: 'asc' } }),
      this.audit.recent(userId),
    ]);
    await this.audit.record(userId, 'DATA_EXPORT');

    const money = (v: { toNumber(): number } | null) => (v === null ? null : v.toNumber());
    return {
      exportedAt: new Date().toISOString(),
      format: 'carne-export-v1',
      account: {
        id: user.id,
        phone: user.phone,
        businessName: user.businessName,
        plan: user.plan,
        planExpiresAt: user.planExpiresAt,
        createdAt: user.createdAt,
      },
      customers: customers.map((c) => ({
        id: c.id,
        kind: c.kind,
        name: c.name,
        phone: c.phone,
        creditLimit: money(c.creditLimit),
        reminderOptOut: c.reminderOptOut,
        createdAt: c.createdAt,
        debts: c.debts.map((d) => ({
          id: d.id,
          amount: money(d.amount),
          reason: d.reason,
          category: d.category,
          status: d.status,
          dueDate: d.dueDate,
          createdAt: d.createdAt,
          payments: d.payments.map((p) => ({ id: p.id, amount: money(p.amount), method: p.method, paidAt: p.paidAt })),
          reminders: d.reminders.map((r) => ({ channel: r.channel, status: r.status, sentAt: r.sentAt, createdAt: r.createdAt })),
        })),
      })),
      cashEntries: cashEntries.map((e) => ({
        id: e.id,
        type: e.type,
        amount: money(e.amount),
        label: e.label,
        category: e.category,
        occurredAt: e.occurredAt,
      })),
      reminderRules: rules.map((r) => ({ offsetDays: r.offsetDays, channel: r.channel, tone: r.tone, enabled: r.enabled })),
      consents: consents.map((c) => ({ version: c.version, acceptedAt: c.acceptedAt })),
      activity,
    };
  }

  /** Donnees d'UN client ou fournisseur (demande d'acces faite par cette personne au commercant). */
  async exportParty(userId: string, customerId: string) {
    const customer = await this.prisma.customer.findFirst({
      where: { id: customerId, userId },
      include: { debts: { include: { payments: true, reminders: true }, orderBy: { createdAt: 'asc' } } },
    });
    if (!customer) return null;
    await this.audit.record(userId, 'CUSTOMER_EXPORT');
    const money = (v: { toNumber(): number } | null) => (v === null ? null : v.toNumber());
    return {
      exportedAt: new Date().toISOString(),
      format: 'carne-customer-export-v1',
      kind: customer.kind,
      name: customer.name,
      phone: customer.phone,
      creditLimit: money(customer.creditLimit),
      reminderOptOut: customer.reminderOptOut,
      createdAt: customer.createdAt,
      debts: customer.debts.map((d) => ({
        amount: money(d.amount),
        reason: d.reason,
        category: d.category,
        status: d.status,
        dueDate: d.dueDate,
        createdAt: d.createdAt,
        payments: d.payments.map((p) => ({ amount: money(p.amount), method: p.method, paidAt: p.paidAt })),
        reminders: d.reminders.map((r) => ({ channel: r.channel, status: r.status, sentAt: r.sentAt })),
      })),
    };
  }
}
