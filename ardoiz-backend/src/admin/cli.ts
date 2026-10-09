/**
 * Operations d'administration (pilote, support), sans exposer aucune route HTTP
 * d'administration : elles s'executent sur le serveur, avec acces a la base.
 *
 *   node dist/admin/cli.js grant-premium +2290167070027 90   # Premium pour 90 jours
 *   node dist/admin/cli.js revoke-premium +2290167070027
 *   node dist/admin/cli.js show +2290167070027                # etat d'un compte (sans donnees du carnet)
 *   node dist/admin/cli.js opt-out-contact +2290167070027     # une personne refuse les relances (tous carnets)
 */
import { PrismaClient } from '@prisma/client';

const DAY_MS = 24 * 60 * 60 * 1000;

export async function run(argv: string[], prisma: PrismaClient = new PrismaClient()): Promise<string> {
  const [command, phone, daysArg] = argv;
  if (!command || !phone) throw new Error('Usage: admin <grant-premium|revoke-premium|show|opt-out-contact> <telephone> [jours]');

  // Droit d'opposition d'une personne notee dans le carnet d'un ou plusieurs commercants : elle n'a
  // pas de compte, on agit donc sur les fiches portant son numero, quel que soit le commercant.
  if (command === 'opt-out-contact') return optOutContact(prisma, phone);

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

/**
 * Les numeros des carnets sont saisis librement (« +229 01 67 07 70 27 », « 97 00 00 00 »...) et le Benin est
 * passe de 8 a 10 chiffres : on compare donc les 8 derniers chiffres, sans espaces ni signes.
 */
async function optOutContact(prisma: PrismaClient, phone: string): Promise<string> {
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 8) throw new Error('Numero invalide : au moins 8 chiffres');
  const tail = digits.slice(-8);
  const updated = await prisma.$executeRaw`
    UPDATE customers SET "reminderOptOut" = true
    WHERE kind = 'CLIENT' AND "reminderOptOut" = false
      AND right(regexp_replace(phone, '[^0-9]', '', 'g'), 8) = ${tail}`;
  return `${updated} fiche(s) mise(s) a jour : plus aucune relance ne sera envoyee a ce numero`;
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
