// Configuration du client web. L'API est servie sur le MÊME domaine (reverse proxy) : aucune
// autorisation CORS n'est nécessaire et la CSP n'autorise que 'self'.
export const API_BASE = '/api/v1';

// Version des conditions d'utilisation et de la politique de confidentialité acceptée à
// l'inscription : doit être celle du serveur (vérifié par un test).
export const TERMS_VERSION = '2026-10-06';

export const FREE_PLAN_LIMIT = 15;
