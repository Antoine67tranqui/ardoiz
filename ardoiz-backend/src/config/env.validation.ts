const PLACEHOLDER = /^change-?me/i;
const MIN_SECRET_LENGTH = 32;

const ALWAYS_REQUIRED = ['DATABASE_URL', 'JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET'];
const PRODUCTION_SECRETS = [
  'JWT_ACCESS_SECRET',
  'JWT_REFRESH_SECRET',
  'JWT_OTP_SECRET',
  'MOMO_WEBHOOK_SECRET',
];

/**
 * Valide la configuration au demarrage : l'application refuse de demarrer
 * plutot que de tourner avec une configuration dangereuse. En production, un
 * secret copie depuis .env.example ("change-me-...") ou trop court rendrait
 * les jetons et la signature du webhook de paiement falsifiables.
 */
export function validateEnv(config: Record<string, unknown>): Record<string, unknown> {
  const errors: string[] = [];
  const value = (key: string): string => String(config[key] ?? '').trim();

  for (const key of ALWAYS_REQUIRED) {
    if (!value(key)) errors.push(`${key} est requis`);
  }

  const trustProxy = value('TRUST_PROXY');
  if (trustProxy && !/^\d+$/.test(trustProxy)) {
    errors.push('TRUST_PROXY doit etre un entier (nombre de proxys de confiance)');
  }

  if (value('NODE_ENV') === 'production') {
    for (const key of PRODUCTION_SECRETS) {
      const secret = value(key);
      if (!secret) {
        // MOMO_WEBHOOK_SECRET absent = webhook ferme (refuse tout), acceptable
        // tant qu'aucun agregateur n'est branche ; les autres sont obligatoires.
        if (key !== 'MOMO_WEBHOOK_SECRET') errors.push(`${key} est requis en production`);
        continue;
      }
      if (PLACEHOLDER.test(secret)) {
        errors.push(`${key} contient encore la valeur d'exemple de .env.example`);
      } else if (secret.length < MIN_SECRET_LENGTH) {
        errors.push(`${key} est trop court (minimum ${MIN_SECRET_LENGTH} caracteres)`);
      }
    }

    const distinct = ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET', 'JWT_OTP_SECRET']
      .map(value)
      .filter(Boolean);
    if (new Set(distinct).size !== distinct.length) {
      errors.push('JWT_ACCESS_SECRET, JWT_REFRESH_SECRET et JWT_OTP_SECRET doivent etre differents');
    }

    if (value('MOMO_API_KEY') && !value('MOMO_WEBHOOK_SECRET')) {
      errors.push('MOMO_WEBHOOK_SECRET est requis des que MOMO_API_KEY est renseigne');
    }
  }

  if (errors.length > 0) {
    throw new Error(`Configuration invalide :\n- ${errors.join('\n- ')}`);
  }
  return config;
}
