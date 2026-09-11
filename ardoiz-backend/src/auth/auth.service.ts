import {
  BadRequestException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';

const OTP_TTL_MINUTES = 5;
const PIN_SALT_ROUNDS = 10;
// Un PIN a 4 chiffres n'offre que 10 000 combinaisons : sans verrouillage,
// un attaquant ayant vole/trouve le telephone peut le brute-forcer en
// quelques minutes. On verrouille temporairement le compte au-dela du seuil.
const MAX_PIN_ATTEMPTS = 5;
const PIN_LOCKOUT_MINUTES = 15;

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

interface OtpSessionPayload {
  phone: string;
  purpose: 'otp-verified';
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly notifications: NotificationsService,
  ) {}

  private generateOtpCode(): string {
    return Math.floor(100000 + Math.random() * 900000).toString();
  }

  async requestOtp(phone: string): Promise<{ message: string; devCode?: string }> {
    const code = this.generateOtpCode();
    const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000);

    await this.prisma.user.upsert({
      where: { phone },
      update: { otpCode: code, otpExpiresAt: expiresAt },
      create: {
        phone,
        otpCode: code,
        otpExpiresAt: expiresAt,
        // Compte cree en etat "incomplet" : pinHash/businessName sont
        // finalises lors de l'etape setup-pin pour un nouvel utilisateur.
        pinHash: '',
        businessName: '',
      },
    });

    await this.notifications.sendOtp(phone, code);

    // Aucun fournisseur SMS reel n'est configure (SMS_API_KEY absent) :
    // le code est simule et loggue cote serveur uniquement. On le renvoie
    // ici pour rester testable sans acces aux logs backend. A retirer des
    // qu'un vrai fournisseur SMS est branche (voir NotificationsService).
    // Les deux variables sont requises par NotificationsService.sendSms pour
    // emettre un SMS reel (cf. sa propre verification) : ne tester que l'une
    // des deux ferait croire a tort qu'un SMS reel a ete envoye et priverait
    // l'utilisateur de tout moyen (devCode) de recuperer son code.
    const smsIsSimulated =
      !this.config.get<string>('SMS_API_KEY') ||
      !this.config.get<string>('SMS_USERNAME');
    return {
      message: 'Code OTP envoye par SMS',
      ...(smsIsSimulated ? { devCode: code } : {}),
    };
  }

  async verifyOtp(phone: string, code: string): Promise<{
    otpSessionToken: string;
    isNewUser: boolean;
  }> {
    const user = await this.prisma.user.findUnique({ where: { phone } });

    if (!user || !user.otpCode || !user.otpExpiresAt) {
      throw new BadRequestException('Aucun code OTP en attente pour ce numero');
    }
    if (user.otpExpiresAt < new Date()) {
      throw new BadRequestException('Code OTP expire, veuillez en redemander un');
    }
    if (user.otpCode !== code) {
      throw new BadRequestException('Code OTP invalide');
    }

    await this.prisma.user.update({
      where: { phone },
      data: { otpCode: null, otpExpiresAt: null },
    });

    const otpSessionToken = this.jwt.sign(
      { phone, purpose: 'otp-verified' } satisfies OtpSessionPayload,
      {
        secret: this.config.get<string>('JWT_ACCESS_SECRET'),
        expiresIn: '10m',
      },
    );

    return { otpSessionToken, isNewUser: user.pinHash === '' };
  }

  async setupPin(
    otpSessionToken: string,
    businessName: string,
    pin: string,
  ): Promise<TokenPair> {
    const payload = this.decodeOtpSession(otpSessionToken);

    const pinHash = await bcrypt.hash(pin, PIN_SALT_ROUNDS);
    const user = await this.prisma.user.update({
      where: { phone: payload.phone },
      data: { businessName, pinHash },
    });

    return this.issueTokens(user.id, user.phone);
  }

  async login(phone: string, pin: string): Promise<TokenPair> {
    const user = await this.prisma.user.findUnique({ where: { phone } });
    if (!user || !user.pinHash) {
      throw new UnauthorizedException('Identifiants invalides');
    }

    if (user.pinLockedUntil && user.pinLockedUntil > new Date()) {
      const minutesLeft = Math.ceil(
        (user.pinLockedUntil.getTime() - Date.now()) / 60000,
      );
      throw new UnauthorizedException(
        `Trop de tentatives echouees. Reessayez dans ${minutesLeft} minute(s).`,
      );
    }

    const pinMatches = await bcrypt.compare(pin, user.pinHash);
    if (!pinMatches) {
      const attempts = user.pinFailedAttempts + 1;
      const lockedOut = attempts >= MAX_PIN_ATTEMPTS;
      await this.prisma.user.update({
        where: { id: user.id },
        data: {
          pinFailedAttempts: lockedOut ? 0 : attempts,
          pinLockedUntil: lockedOut
            ? new Date(Date.now() + PIN_LOCKOUT_MINUTES * 60 * 1000)
            : null,
        },
      });
      if (lockedOut) {
        throw new UnauthorizedException(
          `Trop de tentatives echouees. Compte verrouille ${PIN_LOCKOUT_MINUTES} minutes.`,
        );
      }
      throw new UnauthorizedException('Identifiants invalides');
    }

    if (user.pinFailedAttempts > 0 || user.pinLockedUntil) {
      await this.prisma.user.update({
        where: { id: user.id },
        data: { pinFailedAttempts: 0, pinLockedUntil: null },
      });
    }

    return this.issueTokens(user.id, user.phone);
  }

  /** Changement de PIN par un utilisateur deja connecte, apres verification de l'ancien. */
  async changePin(userId: string, currentPin: string, newPin: string): Promise<{ message: string }> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });

    const currentMatches = await bcrypt.compare(currentPin, user.pinHash);
    if (!currentMatches) {
      throw new UnauthorizedException('PIN actuel incorrect');
    }

    const pinHash = await bcrypt.hash(newPin, PIN_SALT_ROUNDS);
    await this.prisma.user.update({
      where: { id: userId },
      data: { pinHash, pinFailedAttempts: 0, pinLockedUntil: null },
    });

    return { message: 'PIN mis a jour' };
  }

  async refresh(refreshToken: string): Promise<TokenPair> {
    try {
      const payload = this.jwt.verify<{ sub: string; phone: string }>(
        refreshToken,
        { secret: this.config.get<string>('JWT_REFRESH_SECRET') },
      );
      return this.issueTokens(payload.sub, payload.phone);
    } catch {
      throw new UnauthorizedException('Jeton de rafraichissement invalide');
    }
  }

  private decodeOtpSession(token: string): OtpSessionPayload {
    try {
      const payload = this.jwt.verify<OtpSessionPayload>(token, {
        secret: this.config.get<string>('JWT_ACCESS_SECRET'),
      });
      if (payload.purpose !== 'otp-verified') {
        throw new Error('invalid purpose');
      }
      return payload;
    } catch {
      throw new UnauthorizedException('Session OTP invalide ou expiree');
    }
  }

  private issueTokens(userId: string, phone: string): TokenPair {
    const accessToken = this.jwt.sign(
      { sub: userId, phone },
      {
        secret: this.config.get<string>('JWT_ACCESS_SECRET'),
        expiresIn: this.config.get<string>('JWT_ACCESS_EXPIRES_IN') ?? '15m',
      },
    );
    const refreshToken = this.jwt.sign(
      { sub: userId, phone },
      {
        secret: this.config.get<string>('JWT_REFRESH_SECRET'),
        expiresIn: this.config.get<string>('JWT_REFRESH_EXPIRES_IN') ?? '30d',
      },
    );
    return { accessToken, refreshToken };
  }
}
