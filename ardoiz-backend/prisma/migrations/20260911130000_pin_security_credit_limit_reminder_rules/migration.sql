-- CreateEnum
CREATE TYPE "ReminderTone" AS ENUM ('GENTLE', 'NEUTRAL', 'FIRM');

-- AlterTable: PIN brute-force protection
ALTER TABLE "users"
  ADD COLUMN "pinFailedAttempts" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "pinLockedUntil" TIMESTAMP(3);

-- AlterTable: optional per-customer credit limit
ALTER TABLE "customers"
  ADD COLUMN "creditLimit" DECIMAL(12,2);

-- AlterTable: track which reminder stage (offset from due date) fired
ALTER TABLE "reminders"
  ADD COLUMN "stageOffsetDays" INTEGER;

-- CreateTable: configurable progressive reminder rules
CREATE TABLE "reminder_rules" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "offsetDays" INTEGER NOT NULL,
    "channel" "ReminderChannel" NOT NULL DEFAULT 'SMS',
    "tone" "ReminderTone" NOT NULL DEFAULT 'NEUTRAL',
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "reminder_rules_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "reminder_rules_userId_idx" ON "reminder_rules"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "reminder_rules_userId_offsetDays_key" ON "reminder_rules"("userId", "offsetDays");

-- AddForeignKey
ALTER TABLE "reminder_rules" ADD CONSTRAINT "reminder_rules_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
