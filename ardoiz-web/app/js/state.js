import { Api, Session } from './api.js';

export const session = new Session();
export const api = new Api(session);

/** État partagé entre les vues (en mémoire : rien n'est conservé au rechargement hors jeton de session). */
export const state = {
  profile: null,
  subscription: null,
  // Parcours d'inscription ou de PIN oublié : { phone, otpSessionToken, isNewUser, devCode }.
  flow: null,
};

export async function loadProfile() {
  state.profile = await api.get('/auth/me');
  return state.profile;
}

/** Ferme la session côté navigateur (jeton effacé, état vidé). */
export function clearLocalSession() {
  session.clear();
  state.profile = null;
  state.subscription = null;
  state.flow = null;
}
