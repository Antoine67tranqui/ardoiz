import { ServiceUnavailableException } from '@nestjs/common';

/**
 * Fonctionnalite pas (encore) disponible dans cet environnement. Le code permet
 * a l'application d'afficher le message tel quel plutot qu'un "serveur indisponible"
 * generique qui laisserait croire qu'un nouvel essai pourrait reussir.
 */
export class FeatureUnavailableException extends ServiceUnavailableException {
  constructor(message: string) {
    super({ code: 'FEATURE_UNAVAILABLE', message });
  }
}
