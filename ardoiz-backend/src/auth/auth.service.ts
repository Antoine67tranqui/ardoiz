import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Prisma } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import * as crypto from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { isPremiumActive } from '../subscription/subscription.utils';

const OTP_TTL_MINUTES = 5;
// Delai minimal entre deux envois de code pour un meme numero : empeche de
// "bombarder" de SMS le telephone d'une victime depuis plusieurs adresses IP
// (la limite par IP seule ne le prevoit pas).
const OTP_RESEND_COOLDOWN_SECONDS = 60;
// Un code a 6 chiffres = 1 000 000 de combinaisons : on l'invalide apres
// quelques essais errones, par compte et non par IP (un attaquant disposant de
// nombreuses IP contournerait sinon la limite de debit).
const MAX_OTP_ATTEMPTS = 5;
const PIN_SALT_ROUNDS = 10;
// Un PIN a 4 chiffres n'offre que 10 000 combinaisons : sans verrouillage,
// un attaquant ayant vole/trouve le telephone peut le brute-forcer en
// quelques minutes. On verrouille temporairement le compte au-dela du seuil.
const MAX_PIN_ATTEMPTS = 5;
const PIN_LOCKOUT_MINUTES = 15;
const UNIQUE_CONSTRAINT_VIOLATION = 'P2002';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

interface OtpSessionPayload {
  phone: string;
  purpose: 'otp-verified';
  // Version de jeton du compte au moment de la verification : setupPin() la
  // consomme (incrementation), ce qui rend la session OTP a usage unique.
  tokenVersion?: number;
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
    // crypto.randomInt et non Math.random() : ce dernier est previsible et ne
    // doit jamais servir a generer un secret d'authentification.
    return crypto.randomInt(100000, 1000000).toString();
  }

  // Empreinte HMAC liee au numero : la base ne contient jamais le code en
  // clair, et une empreinte copiee d'un autre compte ne valide rien.
  private hashOtp(phone: string, code: string): string {
    return crypto
      .createHmac('sha256', this.getOtpSessionSecret() ?? '')
      .update(`${phone}:${code}`)
      .digest('hex');
  }

  private otpMatches(phone: string, code: string, storedHash: string): boolean {
    const expected = Buffer.from(this.hashOtp(phone, code));
    const actual = Buffer.from(storedHash);
    return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
  }

  private tooManyOtpRequests(): HttpException {
    return new HttpException(
      `Un code vient d'etre envoye. Patientez ${OTP_RESEND_COOLDOWN_SECONDS} secondes avant d'en redemander un.`,
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }

  async requestOtp(phone: string): Promise<{ message: string; devCode?: string }> {
    const code = this.generateOtpCode();
    const now = Date.now();
    const expiresAt = new Date(now + OTP_TTL_MINUTES * 60 * 1000);
    const otpHash = this.hashOtp(phone, code);

    // Mise a jour atomique, acceptee seulement si le dernier code a plus de
    // OTP_RESEND_COOLDOWN_SECONDS (ou a expire) : deux requetes concurrentes
    // ne peuvent pas contourner le delai.
    const cooldownThreshold = new Date(
      now + (OTP_TTL_MINUTES * 60 - OTP_RESEND_COOLDOWN_SECONDS) * 1000,
    );
    const updated = await this.prisma.user.updateMany({
      where: {
        phone,
        OR: [{ otpExpiresAt: null }, { otpExpiresAt: { lt: cooldownThreshold } }],
      },
      data: { otpCode: otpHash, otpExpiresAt: expiresAt, otpFailedAttempts: 0 },
    });

    if (updated.count === 0) {
      const existing = await this.prisma.user.findUnique({
        where: { phone },
        select: { id: true },
      });
      if (existing) {
        throw this.tooManyOtpRequests();
      }
      try {
        await this.prisma.user.create({
          data: {
            phone,
            otpCode: otpHash,
            otpExpiresAt: expiresAt,
            // Compte cree en etat "incomplet" : pinHash/businessName sont
            // finalises lors de l'etape setup-pin pour un nouvel utilisateur.
            pinHash: '',
            businessName: '',
          },
        });
      } catch (error) {
        // Deux premieres demandes simultanees pour le meme numero.
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === UNIQUE_CONSTRAINT_VIOLATION
        ) {
          throw this.tooManyOtpRequests();
        }
        throw error;
      }
    }

    try {
      await this.notifications.sendOtp(phone, code);
    } catch {
      // Le code n'a pas pu partir : l'invalider pour que l'utilisateur puisse
      // reessayer tout de suite, sans attendre le delai anti-spam.
      await this.prisma.user.updateMany({
        where: { phone, otpCode: otpHash },
        data: { otpCode: null, otpExpiresAt: null },
      });
      throw new ServiceUnavailableException(
        "L'envoi du SMS a echoue. Veuillez reessayer dans un instant.",
      );
    }

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
    // Ne jamais renvoyer le code dans la reponse HTTP en production, meme si
    // SMS_API_KEY/SMS_USERNAME sont temporairement absents par erreur de
    // configuration : un devCode expose en prod permettrait de prendre le
    // controle de n'importe quel compte sans jamais recevoir le SMS.
    const isProduction = this.config.get<string>('NODE_ENV') === 'production';
    return {
      message: 'Code OTP envoye par SMS',
      ...(smsIsSimulated && !isProduction ? { devCode: code } : {}),
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
    if (!this.otpMatches(phone, code, user.otpCode)) {
      // Incrementation atomique : des essais concurrents ne peuvent pas
      // sous-compter les echecs.
      const { otpFailedAttempts } = await this.prisma.user.update({
        where: { phone },
        data: { otpFailedAttempts: { increment: 1 } },
        select: { otpFailedAttempts: true },
      });
      if (otpFailedAttempts >= MAX_OTP_ATTEMPTS) {
        await this.prisma.user.update({
          where: { phone },
          data: { otpCode: null, otpExpiresAt: null, otpFailedAttempts: 0 },
        });
        throw new BadRequestException(
          'Trop d\'essais errones : ce code est invalide, veuillez en redemander un',
        );
      }
      throw new BadRequestException('Code OTP invalide');
    }

    // Consommation atomique : un code ne peut valider qu'une seule fois, meme
    // si deux requetes l'envoient en meme temps.
    const consumed = await this.prisma.user.updateMany({
      where: { phone, otpCode: user.otpCode },
      data: { otpCode: null, otpExpiresAt: null, otpFailedAttempts: 0 },
    });
    if (consumed.count === 0) {
      throw new BadRequestException('Aucun code OTP en attente pour ce numero');
    }

    const otpSessionToken = this.jwt.sign(
      {
        phone,
        purpose: 'otp-verified',
        tokenVersion: user.tokenVersion,
      } satisfies OtpSessionPayload,
      {
        secret: this.getOtpSessionSecret(),
        expiresIn: '10m',
      },
    );

    return { otpSessionToken, isNewUser: user.pinHash === '' };
  }

  /**
   * Cree le PIN d'un nouveau compte, ou le reinitialise apres un OTP valide
   * (PIN oublie). La session OTP est a usage unique, la reinitialisation
   * deverrouille le compte et revoque toutes les sessions deja ouvertes
   * (un telephone perdu ne doit pas rester connecte apres un nouveau PIN).
   */
  async setupPin(
    otpSessionToken: string,
    businessName: string,
    pin: string,
  ): Promise<TokenPair> {
    const payload = this.decodeOtpSession(otpSessionToken);

    const pinHash = await bcrypt.hash(pin, PIN_SALT_ROUNDS);
    const consumed = await this.prisma.user.updateMany({
      where: { phone: payload.phone, tokenVersion: payload.tokenVersion },
      data: {
        businessName,
        pinHash,
        pinFailedAttempts: 0,
        pinLockedUntil: null,
        tokenVersion: { increment: 1 },
      },
    });
    if (consumed.count === 0) {
      throw new UnauthorizedException('Session OTP invalide ou expiree');
    }

    const user = await this.prisma.user.findUniqueOrThrow({
      where: { phone: payload.phone },
    });
    return this.issueTokens(user.id, user.phone, user.tokenVersion);
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

    return this.issueTokens(user.id, user.phone, user.tokenVersion);
  }

  /** Changement de PIN par un utilisateur deja connecte, apres verification de l'ancien. */
  async changePin(userId: string, currentPin: string, newPin: string): Promise<{ message: string }> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });

    // 400 et non 401 : un 401 signifie « session invalide » pour les clients,
    // qui tenteraient alors de renouveler le jeton au lieu d'afficher l'erreur.
    const currentMatches = await bcrypt.compare(currentPin, user.pinHash);
    if (!currentMatches) {
      throw new BadRequestException('PIN actuel incorrect');
    }

    const pinHash = await bcrypt.hash(newPin, PIN_SALT_ROUNDS);
    await this.prisma.user.update({
      where: { id: userId },
      data: {
        pinHash,
        pinFailedAttempts: 0,
        pinLockedUntil: null,
        // Un changement de PIN doit invalider tout jeton deja emis (ex: vol
        // de telephone suivi d'un changement de PIN par le proprietaire
        // legitime) : incrementer tokenVersion les fait tous echouer, sans
        // avoir a les lister/stocker.
        tokenVersion: { increment: 1 },
      },
    });

    return { message: 'PIN mis a jour' };
  }

  /** Profil du commercant connecte (le plan est celui effectivement actif : un Premium expire est FREE). */
  async getProfile(userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    const premium = isPremiumActive(user);
    return {
      id: user.id,
      phone: user.phone,
      businessName: user.businessName,
      plan: premium ? 'PREMIUM' : 'FREE',
      planExpiresAt: premium ? user.planExpiresAt : null,
    };
  }

  async updateProfile(userId: string, businessName: string) {
    await this.prisma.user.update({ where: { id: userId }, data: { businessName } });
    return this.getProfile(userId);
  }

  /** Revoque tous les jetons (acces et refresh) en circulation pour cet utilisateur. */
  async logout(userId: string): Promise<{ message: string }> {
    await this.prisma.user.update({
      where: { id: userId },
      data: { tokenVersion: { increment: 1 } },
    });
    return { message: 'Deconnecte' };
  }

  async refresh(refreshToken: string): Promise<TokenPair> {
    try {
      const payload = this.jwt.verify<{
        sub: string;
        phone: string;
        tokenVersion: number;
      }>(refreshToken, { secret: this.config.get<string>('JWT_REFRESH_SECRET') });

      const user = await this.prisma.user.findUniqueOrThrow({
        where: { id: payload.sub },
      });
      // Un refresh token emis avant un logout() ou changePin() porte encore
      // l'ancienne valeur de tokenVersion : il doit etre rejete meme si sa
      // signature et son expiration sont valides.
      if (user.tokenVersion !== payload.tokenVersion) {
        throw new Error('refresh token revoque');
      }

      return this.issueTokens(user.id, user.phone, user.tokenVersion);
    } catch {
      throw new UnauthorizedException('Jeton de rafraichissement invalide');
    }
  }

  private decodeOtpSession(token: string): OtpSessionPayload {
    try {
      const payload = this.jwt.verify<OtpSessionPayload>(token, {
        secret: this.getOtpSessionSecret(),
      });
      if (payload.purpose !== 'otp-verified') {
        throw new Error('invalid purpose');
      }
      return payload;
    } catch {
      throw new UnauthorizedException('Session OTP invalide ou expiree');
    }
  }

  // Secret dedie aux jetons de session OTP (courte duree, etape intermediaire
  // entre la verification du code et la creation/connexion du compte), separe
  // de JWT_ACCESS_SECRET : la verification du `purpose` protege deja contre
  // la confusion de jetons, mais reutiliser un meme secret pour deux types de
  // jetons distincts reste un risque si un futur chemin de code verifie un
  // jeton sans en controler le `purpose`. Se replie sur JWT_ACCESS_SECRET si
  // JWT_OTP_SECRET n'est pas defini hors production (la validation de la
  // configuration l'exige en production, voir config/env.validation.ts).
  private getOtpSessionSecret(): string | undefined {
    return (
      this.config.get<string>('JWT_OTP_SECRET') ??
      this.config.get<string>('JWT_ACCESS_SECRET')
    );
  }

  private issueTokens(
    userId: string,
    phone: string,
    tokenVersion: number,
  ): TokenPair {
    // tokenVersion dans les deux jetons : un logout ou un changement de PIN
    // invalide immediatement les jetons d'acces (verifie par JwtStrategy), pas
    // seulement les refresh tokens a leur prochain renouvellement.
    const accessToken = this.jwt.sign(
      { sub: userId, phone, tokenVersion },
      {
        secret: this.config.get<string>('JWT_ACCESS_SECRET'),
        expiresIn: this.config.get<string>('JWT_ACCESS_EXPIRES_IN') ?? '15m',
      },
    );
    const refreshToken = this.jwt.sign(
      { sub: userId, phone, tokenVersion },
      {
        secret: this.config.get<string>('JWT_REFRESH_SECRET'),
        expiresIn: this.config.get<string>('JWT_REFRESH_EXPIRES_IN') ?? '30d',
      },
    );
    return { accessToken, refreshToken };
  }
}
