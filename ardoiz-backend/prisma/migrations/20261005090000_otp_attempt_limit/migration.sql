-- AlterTable: compteur d'essais OTP errones (limite par compte, independante de l'IP)
ALTER TABLE "users"
  ADD COLUMN "otpFailedAttempts" INTEGER NOT NULL DEFAULT 0;

-- Les codes OTP etaient stockes en clair : les invalider, ils sont desormais
-- compares sous forme d'empreinte HMAC. Un code en attente (5 min de validite)
-- est simplement a redemander.
UPDATE "users" SET "otpCode" = NULL, "otpExpiresAt" = NULL WHERE "otpCode" IS NOT NULL;
