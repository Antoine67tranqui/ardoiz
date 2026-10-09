import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { ThrottlerGuard } from '@nestjs/throttler';

/**
 * Limitation de debit par utilisateur authentifie, par IP sinon.
 *
 * Sur les reseaux mobiles d'Afrique de l'Ouest, de nombreux abonnes partagent
 * une meme adresse IP publique (NAT operateur) : une limite purement par IP
 * bloquerait des commercants sans rapport entre eux. Le jeton d'acces est
 * verifie (signature incluse) avant d'etre utilise comme cle : un jeton forge
 * ne permet donc pas d'echapper a la limite, il retombe simplement sur l'IP.
 */
@Injectable()
export class AppThrottlerGuard extends ThrottlerGuard {
  @Inject(JwtService) private readonly jwt!: JwtService;
  @Inject(ConfigService) private readonly config!: ConfigService;

  protected async getTracker(req: Record<string, any>): Promise<string> {
    const header: unknown = req.headers?.authorization;
    if (typeof header === 'string' && header.startsWith('Bearer ')) {
      try {
        const payload = this.jwt.verify<{ sub?: string }>(header.slice(7), {
          secret: this.config.get<string>('JWT_ACCESS_SECRET'),
        });
        if (payload.sub) return `user:${payload.sub}`;
      } catch {
        // jeton invalide ou expire : on retombe sur l'IP.
      }
    }
    return req.ip;
  }
}
