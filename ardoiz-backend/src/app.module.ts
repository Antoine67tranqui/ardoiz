import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerModule } from '@nestjs/throttler';
import { AppThrottlerGuard } from './common/guards/app-throttler.guard';
import { validateEnv } from './config/env.validation';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { CustomersModule } from './customers/customers.module';
import { DebtsModule } from './debts/debts.module';
import { PaymentsModule } from './payments/payments.module';
import { RemindersModule } from './reminders/reminders.module';
import { NotificationsModule } from './notifications/notifications.module';
import { DashboardModule } from './dashboard/dashboard.module';
import { SubscriptionModule } from './subscription/subscription.module';
import { ExportModule } from './export/export.module';
import { SyncModule } from './sync/sync.module';
import { CashModule } from './cash/cash.module';
import { AuditModule } from './audit/audit.module';
import { HealthController } from './health/health.controller';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    // Necessaire a AppThrottlerGuard (verification du jeton pour la cle de limitation).
    JwtModule.register({}),
    ScheduleModule.forRoot(),
    // Limite par defaut appliquee a toute route sans decorateur @Throttle
    // specifique : 60 requetes/minute par utilisateur connecte (par IP sinon,
    // voir AppThrottlerGuard). Des limites plus strictes sont posees
    // explicitement sur les routes sensibles (OTP, login, webhook).
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }]),
    PrismaModule,
    AuditModule,
    AuthModule,
    CustomersModule,
    DebtsModule,
    PaymentsModule,
    RemindersModule,
    NotificationsModule,
    DashboardModule,
    SubscriptionModule,
    ExportModule,
    SyncModule,
    CashModule,
  ],
  controllers: [HealthController],
  providers: [{ provide: APP_GUARD, useClass: AppThrottlerGuard }],
})
export class AppModule {}
