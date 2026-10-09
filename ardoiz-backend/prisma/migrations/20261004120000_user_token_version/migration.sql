-- AlterTable: compteur de version de jeton, incremente a la deconnexion et
-- au changement de PIN pour permettre la revocation des refresh tokens deja
-- emis (JWT reste stateless, seule cette valeur est comparee a l'emission).
ALTER TABLE "users"
  ADD COLUMN "tokenVersion" INTEGER NOT NULL DEFAULT 0;
