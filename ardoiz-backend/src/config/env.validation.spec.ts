import { validateEnv } from './env.validation';

describe('validateEnv', () => {
  const strong = (seed: string) => `${seed}-${'x'.repeat(40)}`;
  const base = {
    DATABASE_URL: 'postgresql://u:p@localhost/db',
    JWT_ACCESS_SECRET: strong('access'),
    JWT_REFRESH_SECRET: strong('refresh'),
  };
  const production = {
    ...base,
    NODE_ENV: 'production',
    JWT_OTP_SECRET: strong('otp'),
    MOMO_WEBHOOK_SECRET: strong('webhook'),
  };

  it('accepte une configuration de developpement minimale, secrets courts compris', () => {
    expect(() =>
      validateEnv({ DATABASE_URL: 'x', JWT_ACCESS_SECRET: 'a', JWT_REFRESH_SECRET: 'b' }),
    ).not.toThrow();
  });

  it('exige DATABASE_URL et les secrets JWT, dans tous les environnements', () => {
    expect(() => validateEnv({})).toThrow(/DATABASE_URL est requis[\s\S]*JWT_ACCESS_SECRET est requis/);
  });

  it('refuse un TRUST_PROXY non numerique', () => {
    expect(() => validateEnv({ ...base, TRUST_PROXY: 'oui' })).toThrow(/TRUST_PROXY/);
    expect(() => validateEnv({ ...base, TRUST_PROXY: '1' })).not.toThrow();
  });

  describe('en production', () => {
    it('accepte une configuration complete', () => {
      expect(() => validateEnv(production)).not.toThrow();
    });

    it("refuse les valeurs d'exemple de .env.example", () => {
      expect(() => validateEnv({ ...production, MOMO_WEBHOOK_SECRET: 'change-me-webhook-secret' })).toThrow(
        /MOMO_WEBHOOK_SECRET contient encore la valeur d'exemple/,
      );
      expect(() => validateEnv({ ...production, JWT_ACCESS_SECRET: 'change-me-access-secret' })).toThrow(
        /JWT_ACCESS_SECRET contient encore/,
      );
    });

    it('refuse un secret trop court', () => {
      expect(() => validateEnv({ ...production, JWT_REFRESH_SECRET: 'court' })).toThrow(
        /JWT_REFRESH_SECRET est trop court/,
      );
    });

    it('exige JWT_OTP_SECRET', () => {
      const { JWT_OTP_SECRET: _omit, ...withoutOtp } = production;
      expect(() => validateEnv(withoutOtp)).toThrow(/JWT_OTP_SECRET est requis en production/);
    });

    it('refuse de reutiliser le meme secret pour plusieurs usages', () => {
      expect(() => validateEnv({ ...production, JWT_OTP_SECRET: production.JWT_ACCESS_SECRET })).toThrow(
        /doivent etre differents/,
      );
    });

    it("tolere l'absence de MOMO_WEBHOOK_SECRET (webhook ferme) tant qu'aucun agregateur n'est configure", () => {
      const { MOMO_WEBHOOK_SECRET: _omit, ...withoutWebhook } = production;
      expect(() => validateEnv(withoutWebhook)).not.toThrow();
      expect(() => validateEnv({ ...withoutWebhook, MOMO_API_KEY: 'cle' })).toThrow(
        /MOMO_WEBHOOK_SECRET est requis des que MOMO_API_KEY/,
      );
    });

    it('liste toutes les erreurs a la fois', () => {
      expect(() => validateEnv({ NODE_ENV: 'production', ...base, JWT_ACCESS_SECRET: 'x', JWT_OTP_SECRET: '' })).toThrow(
        /JWT_ACCESS_SECRET est trop court[\s\S]*JWT_OTP_SECRET est requis/,
      );
    });
  });
});
