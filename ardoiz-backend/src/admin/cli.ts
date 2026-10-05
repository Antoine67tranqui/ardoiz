/**
 * Operations d'administration (pilote, support), sans exposer aucune route HTTP
 * d'administration : elles s'executent sur le serveur, avec acces a la base.
 *
 *   node dist/admin/cli.js grant-premium +2290167070027 90   # Premium pour 90 jours
 *   node dist/admin/cli.js revoke-premium +2290167070027
 *   node dist/admin/cli.js show +2290167070027                # etat d'un compte (sans donnees du carnet)
 */
import { PrismaClient } from '@prisma/client';

const DAY_MS = 24 * 60 * 60 * 1000;

export async function run(argv: string[], prisma: PrismaClient = new PrismaClient()): Promise<string> {
  const [command, phone, daysArg] = argv;
  if (!command || !phone) throw new Error('Usage: admin <grant-premium|revoke-premium|show> <telephone> [jours]');

  const user = await prisma.user.findUnique({ where: { phone } });
  if (!user) throw new Error(`Aucun compte pour ${phone}`);

  switch (command) {
    case 'grant-premium': {
      const days = Number(daysArg);
      if (!Number.isInteger(days) || days < 1 || days > 730) throw new Error('Le nombre de jours doit etre un entier entre 1 et 730');
      // On prolonge a partir de l'echeance si elle est future (pas de jours perdus).
      const base = user.planExpiresAt && user.planExpiresAt.getTime() > Date.now() ? user.planExpiresAt.getTime() : Date.now();
      const planExpiresAt = new Date(base + days * DAY_MS);
      await prisma.user.update({ where: { id: user.id }, data: { plan: 'PREMIUM', planExpiresAt } });
      return `Premium jusqu'au ${planExpiresAt.toISOString().slice(0, 10)} pour ${phone}`;
    }
    case 'revoke-premium':
      await prisma.user.update({ where: { id: user.id }, data: { plan: 'FREE', planExpiresAt: null } });
      return `Plan gratuit pour ${phone}`;
    case 'show': {
      const [customers, suppliers] = await Promise.all([
        prisma.customer.count({ where: { userId: user.id, kind: 'CLIENT' } }),
        prisma.customer.count({ where: { userId: user.id, kind: 'SUPPLIER' } }),
      ]);
      return JSON.stringify({ phone, businessName: user.businessName, plan: user.plan, planExpiresAt: user.planExpiresAt, createdAt: user.createdAt, customers, suppliers });
    }
    default:
      throw new Error(`Commande inconnue : ${command}`);
  }
}

if (require.main === module) {
  const prisma = new PrismaClient();
  run(process.argv.slice(2), prisma)
    .then((message) => console.log(message))
    .catch((error: Error) => {
      console.error(error.message);
      process.exitCode = 1;
    })
    .finally(() => prisma.$disconnect());
}
