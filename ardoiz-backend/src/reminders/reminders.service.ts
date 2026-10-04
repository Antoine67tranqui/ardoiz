import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ReminderChannel } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { DebtsService } from '../debts/debts.service';
import { outstandingOf } from '../common/money';

@Injectable()
export class RemindersService {
  private readonly logger = new Logger(RemindersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly debtsService: DebtsService,
  ) {}

  /** Envoi manuel d'une relance pour une dette donnee, declenche par le commercant. */
  async sendManualReminder(
    userId: string,
    debtId: string,
    channel: ReminderChannel = 'SMS',
  ) {
    const debt = await this.debtsService.getOwnedDebt(userId, debtId);
    // Relancer une dette soldee enverrait un message de reclamation a tort.
    if (outstandingOf(debt.amount, debt.payments).lessThanOrEqualTo(0)) {
      throw new BadRequestException('Cette dette est deja soldee');
    }
    return this.dispatchReminder(debt.id, channel);
  }

  /**
   * Utilise par le cron quotidien : pour chaque commercant Premium et
   * chaque etape de relance qu'il a configuree (ReminderRule, ex. J-3
   * courtois / J0 neutre / J+7 ferme), envoie la relance aux dettes dont
   * l'echeance tombe exactement sur cette etape aujourd'hui, sans jamais
   * relancer deux fois la meme etape pour une meme dette. La relance
   * automatique reste une fonctionnalite Premium ; la relance manuelle
   * depuis l'app reste disponible a tous.
   */
  async sendAutomaticReminders(): Promise<{ sent: number }> {
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const rules = await this.prisma.reminderRule.findMany({
      where: {
        enabled: true,
        user: { plan: 'PREMIUM', planExpiresAt: { gt: now } },
      },
    });

    let sent = 0;
    for (const rule of rules) {
      // Dette echue a cette etape si dueDate == aujourd'hui - offsetDays.
      const targetStart = new Date(todayStart);
      targetStart.setDate(targetStart.getDate() - rule.offsetDays);
      const targetEnd = new Date(targetStart);
      targetEnd.setDate(targetEnd.getDate() + 1);

      const debts = await this.prisma.debt.findMany({
        where: {
          status: { in: ['PENDING', 'PARTIAL'] },
          dueDate: { gte: targetStart, lt: targetEnd },
          customer: { userId: rule.userId },
          // Pas de relance deja envoyee pour cette meme etape sur cette dette.
          reminders: { none: { stageOffsetDays: rule.offsetDays } },
        },
      });

      for (const debt of debts) {
        try {
          const reminder = await this.dispatchReminder(
            debt.id,
            rule.channel,
            rule.offsetDays,
            rule.tone,
          );
          // dispatchReminder absorbe les echecs d'envoi (statut FAILED) : ne
          // compter que les relances reellement parties.
          if (reminder.status === 'SENT') sent += 1;
        } catch (error) {
          this.logger.error(`Echec relance dette ${debt.id} (etape ${rule.offsetDays}j)`, error as Error);
        }
      }
    }
    return { sent };
  }

  private async dispatchReminder(
    debtId: string,
    channel: ReminderChannel,
    stageOffsetDays: number | null = null,
    tone: 'GENTLE' | 'NEUTRAL' | 'FIRM' = 'NEUTRAL',
  ) {
    const debt = await this.prisma.debt.findUniqueOrThrow({
      where: { id: debtId },
      include: { customer: { include: { user: true } }, payments: true },
    });

    const reminder = await this.prisma.reminder.create({
      data: { debtId, channel, status: 'QUEUED', stageOffsetDays },
    });

    if (!debt.customer.phone) {
      await this.prisma.reminder.update({
        where: { id: reminder.id },
        data: { status: 'FAILED' },
      });
      return reminder;
    }

    try {
      await this.notifications.sendDebtReminder({
        phone: debt.customer.phone,
        channel,
        customerName: debt.customer.name,
        // Le reste a payer, pas le montant initial : apres un paiement partiel,
        // reclamer la somme d'origine serait faux et ferait perdre la confiance du client.
        amount: outstandingOf(debt.amount, debt.payments).toString(),
        businessName: debt.customer.user.businessName,
        tone,
      });
      return this.prisma.reminder.update({
        where: { id: reminder.id },
        data: { status: 'SENT', sentAt: new Date() },
      });
    } catch (error) {
      this.logger.error(`Envoi relance echoue pour dette ${debtId}`, error as Error);
      return this.prisma.reminder.update({
        where: { id: reminder.id },
        data: { status: 'FAILED' },
      });
    }
  }
}
