-- CreateEnum
CREATE TYPE "PartyKind" AS ENUM ('CLIENT', 'SUPPLIER');

-- CreateEnum
CREATE TYPE "CashType" AS ENUM ('SALE', 'EXPENSE');

-- AlterTable
ALTER TABLE "customers" ADD COLUMN     "kind" "PartyKind" NOT NULL DEFAULT 'CLIENT',
ADD COLUMN     "reminderOptOut" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "cash_entries" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "CashType" NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "label" TEXT,
    "category" TEXT NOT NULL DEFAULT 'Autre',
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "cash_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "consent_records" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "acceptedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "consent_records_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "cash_entries_userId_occurredAt_idx" ON "cash_entries"("userId", "occurredAt");

-- CreateIndex
CREATE INDEX "consent_records_userId_idx" ON "consent_records"("userId");

-- CreateIndex
CREATE INDEX "audit_logs_userId_createdAt_idx" ON "audit_logs"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "audit_logs_createdAt_idx" ON "audit_logs"("createdAt");

-- CreateIndex
CREATE INDEX "customers_userId_kind_idx" ON "customers"("userId", "kind");

-- AddForeignKey
ALTER TABLE "cash_entries" ADD CONSTRAINT "cash_entries_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "consent_records" ADD CONSTRAINT "consent_records_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

