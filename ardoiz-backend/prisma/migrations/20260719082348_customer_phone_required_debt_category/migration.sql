/*
  Warnings:

  - Made the column `phone` on table `customers` required. This step will fail if there are existing NULL values in that column.

*/
-- AlterTable
ALTER TABLE "customers" ALTER COLUMN "phone" SET NOT NULL;

-- AlterTable
ALTER TABLE "debts" ADD COLUMN     "category" TEXT NOT NULL DEFAULT 'Autre';

-- CreateIndex
CREATE INDEX "debts_category_idx" ON "debts"("category");
