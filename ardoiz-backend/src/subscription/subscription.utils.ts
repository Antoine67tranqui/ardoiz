import { Plan } from '@prisma/client';

interface PlanFields {
  plan: Plan;
  planExpiresAt: Date | null;
}

/** Un compte Premium expire des que planExpiresAt est depasse (abonnement non renouvele). */
export function isPremiumActive(user: PlanFields): boolean {
  if (user.plan !== 'PREMIUM') return false;
  if (!user.planExpiresAt) return false;
  return user.planExpiresAt.getTime() > Date.now();
}
