import { API_BASE } from '../config.js';

export class ApiError extends Error {
  constructor(status, message, code = null) {
    super(message);
    this.status = status;
    this.code = code;
  }
  get isNetwork() { return this.status === 0; }
  get isUnauthorized() { return this.status === 401; }
}

const REFRESH_KEY = 'carne_refresh_token';
// Routes publiques : un 401 y signifie « identifiants refusés », pas « session expirée ».
const PUBLIC = ['/auth/otp/request', '/auth/otp/verify', '/auth/pin/setup', '/auth/login', '/auth/refresh'];

function storage() {
  try { return window.sessionStorage; } catch { return null; }
}

/**
 * Session du client web. Le jeton d'accès (15 min) ne vit qu'en mémoire ; le jeton de
 * rafraîchissement est dans sessionStorage : il disparaît à la fermeture de l'onglet et
 * n'est jamais partagé entre onglets. (Pas de localStorage : une session ne survit pas à
 * la fermeture du navigateur.)
 */
export class Session {
  accessToken = null;
  #refreshing = null;
  onExpired = () => {};

  get refreshToken() { return storage()?.getItem(REFRESH_KEY) ?? null; }
  get hasSession() { return Boolean(this.accessToken || this.refreshToken); }

  save({ accessToken, refreshToken }) {
    this.accessToken = accessToken;
    try { storage()?.setItem(REFRESH_KEY, refreshToken); } catch { /* stockage indisponible : session limitée à cet onglet */ }
  }

  clear() {
    this.accessToken = null;
    try { storage()?.removeItem(REFRESH_KEY); } catch { /* rien à effacer */ }
  }

  /** Renouvelle le jeton d'accès ; un seul renouvellement à la fois, jamais de boucle. */
  refresh() {
    this.#refreshing ??= (async () => {
      const token = this.refreshToken;
      if (!token) throw new ApiError(401, 'Session expirée.');
      const res = await rawFetch('POST', '/auth/refresh', { refreshToken: token });
      this.save(res);
    })().finally(() => { this.#refreshing = null; });
    return this.#refreshing;
  }
}

async function rawFetch(method, path, body, { query, responseType = 'json', token } = {}) {
  const url = new URL(API_BASE + path, window.location.origin);
  for (const [k, v] of Object.entries(query ?? {})) if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
  let response;
  try {
    response = await fetch(url, {
      method,
      headers: {
        Accept: responseType === 'json' ? 'application/json' : '*/*',
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      credentials: 'omit',
      cache: 'no-store',
    });
  } catch {
    throw new ApiError(0, 'Pas de connexion au serveur. Vérifiez votre réseau et réessayez.');
  }

  if (response.ok) {
    if (responseType === 'blob') return response.blob();
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  }

  let message = `Erreur inattendue (${response.status}).`;
  let code = null;
  try {
    const data = await response.json();
    const raw = data?.message;
    if (typeof raw === 'string') message = raw;
    else if (raw && typeof raw === 'object') {
      code = raw.code ?? null;
      message = Array.isArray(raw.message) ? raw.message.join(' ') : (raw.message ?? message);
    }
  } catch { /* corps non JSON */ }
  if (response.status >= 500 && code !== 'FEATURE_UNAVAILABLE') message = 'Le serveur est momentanément indisponible. Réessayez dans un instant.';
  if (response.status === 429) message = 'Trop de demandes. Patientez un instant avant de réessayer.';
  throw new ApiError(response.status, message, code);
}

export class Api {
  constructor(session) { this.session = session; }

  async request(method, path, body, options = {}) {
    if (PUBLIC.includes(path)) return rawFetch(method, path, body, options);
    if (!this.session.accessToken) await this.session.refresh().catch(() => {});
    try {
      return await rawFetch(method, path, body, { ...options, token: this.session.accessToken });
    } catch (error) {
      if (!(error instanceof ApiError) || !error.isUnauthorized) throw error;
      try {
        await this.session.refresh();
        return await rawFetch(method, path, body, { ...options, token: this.session.accessToken });
      } catch (second) {
        if (second instanceof ApiError && second.isUnauthorized) {
          this.session.clear();
          this.session.onExpired();
        }
        throw second;
      }
    }
  }

  get = (path, query, options) => this.request('GET', path, undefined, { query, ...options });
  post = (path, body) => this.request('POST', path, body ?? {});
  patch = (path, body) => this.request('PATCH', path, body);
  delete = (path) => this.request('DELETE', path);
  download = (path) => this.request('GET', path, undefined, { responseType: 'blob' });
}

/** Génère un identifiant UUID v4 (créations idempotentes comme dans l'application mobile). */
export function newId() {
  return crypto.randomUUID();
}
