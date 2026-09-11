import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UpsertReminderRuleDto } from './dto/upsert-reminder-rule.dto';

/**
 * Trois etapes par defaut a la creation d'un compte : rappel courtois 3
 * jours avant l'echeance, rappel neutre le jour meme, relance ferme 7
 * jours apres. Le commercant peut ensuite les modifier/desactiver/ajouter
 * d'autres etapes librement (voir ReminderRulesService.listForUser).
 */
const DEFAULT_RULES: Array<Pick<UpsertReminderRuleDto, 'offsetDays' | 'channel' | 'tone'>> = [
  { offsetDays: -3, channel: 'SMS', tone: 'GENTLE' },
  { offsetDays: 0, channel: 'SMS', tone: 'NEUTRAL' },
  { offsetDays: 7, channel: 'SMS', tone: 'FIRM' },
];

@Injectable()
export class ReminderRulesService {
  constructor(private readonly prisma: PrismaService) {}

  /** Retourne les etapes de relance du commercant, en les initialisant aux valeurs par defaut au premier appel. */
  async listForUser(userId: string) {
    const existing = await this.prisma.reminderRule.findMany({
      where: { userId },
      orderBy: { offsetDays: 'asc' },
    });
    if (existing.length > 0) return existing;

    await this.prisma.reminderRule.createMany({
      data: DEFAULT_RULES.map((rule) => ({ ...rule, userId })),
    });
    return this.prisma.reminderRule.findMany({
      where: { userId },
      orderBy: { offsetDays: 'asc' },
    });
  }

  /** Cree ou met a jour l'etape pour ce decalage (un seul offsetDays par etape et par commercant). */
  async upsert(userId: string, dto: UpsertReminderRuleDto) {
    return this.prisma.reminderRule.upsert({
      where: { userId_offsetDays: { userId, offsetDays: dto.offsetDays } },
      create: {
        userId,
        offsetDays: dto.offsetDays,
        channel: dto.channel ?? 'SMS',
        tone: dto.tone ?? 'NEUTRAL',
        enabled: dto.enabled ?? true,
      },
      update: {
        channel: dto.channel,
        tone: dto.tone,
        enabled: dto.enabled,
      },
    });
  }

  async remove(userId: string, ruleId: string) {
    const rule = await this.prisma.reminderRule.findUnique({ where: { id: ruleId } });
    if (!rule || rule.userId !== userId) {
      throw new NotFoundException('Etape de relance introuvable');
    }
    await this.prisma.reminderRule.delete({ where: { id: ruleId } });
    return { message: 'Etape de relance supprimee' };
  }
}
