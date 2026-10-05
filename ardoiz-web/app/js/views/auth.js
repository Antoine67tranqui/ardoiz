import { h } from '../dom.js';
import { TERMS_VERSION } from '../../config.js';
import { api, session, state, loadProfile } from '../state.js';
import { checkbox, field, form, pinField, toast, errorBanner } from '../ui.js';
import { navigate } from '../nav.js';
import { normalizeAccountPhone, validate } from '../format.js';

const legalLinks = () => h('span', {},
  h('a', { href: '../conditions.html', target: '_blank', rel: 'noopener' }, "conditions d'utilisation"), ' et la ',
  h('a', { href: '../confidentialite.html', target: '_blank', rel: 'noopener' }, 'politique de confidentialité'));

function authCard(title, subtitle, ...children) {
  return h('section', { class: 'auth' },
    h('img', { src: '../assets/logo-192.png', width: 72, height: 72, alt: '', class: 'auth-logo' }),
    h('h1', {}, title),
    subtitle ? h('p', { class: 'lead' }, subtitle) : null,
    ...children);
}

async function openSession(tokens) {
  session.save(tokens);
  await loadProfile();
  navigate(state.profile.termsAccepted ? '/clients' : '/consentement', { replace: true });
}

const phoneField = (value = '') => {
  const f = field({ label: 'Votre numéro de téléphone', name: 'phone', type: 'tel', value, inputmode: 'tel', autocomplete: 'tel', required: true, hint: "Avec l'indicatif du pays, par exemple +229 01 67 07 70 27." });
  return { ...f, validate: validate.accountPhone };
};

export function login() {
  const phone = phoneField(state.flow?.phone ?? '');
  const pin = pinField({ label: 'Code PIN (4 chiffres)', name: 'pin', autocomplete: 'current-password' });
  const node = form({
    fields: [{ field: phone, validate: phone.validate }, { field: pin, validate: pin.validate }],
    submitLabel: 'Se connecter',
    onSubmit: async () => {
      let tokens;
      try {
        tokens = await api.post('/auth/login', { phone: normalizeAccountPhone(phone.input.value), pin: pin.input.value });
      } catch (error) {
        // Le serveur ne dit volontairement pas lequel des deux est faux.
        if (error.status === 401) throw new Error('Numéro de téléphone ou code PIN incorrect.');
        throw error;
      }
      await openSession(tokens);
    },
  });
  return authCard('Connexion', 'Retrouvez votre carnet depuis ce navigateur.', node,
    h('p', { class: 'row-links' },
      h('a', { href: '#/inscription' }, 'Créer un compte'),
      h('a', { href: '#/inscription', onclick: () => { state.flow = null; } }, 'PIN oublié ?')));
}

export function requestOtp() {
  const phone = phoneField(state.flow?.phone ?? '');
  const node = form({
    fields: [{ field: phone, validate: phone.validate }],
    submitLabel: 'Recevoir le code par SMS',
    onSubmit: async () => {
      const number = normalizeAccountPhone(phone.input.value);
      const result = await api.post('/auth/otp/request', { phone: number });
      state.flow = { phone: number, devCode: result?.devCode ?? null };
      navigate('/inscription/code');
    },
  });
  return authCard('Créer un compte', 'Nous vous envoyons un code par SMS pour vérifier votre numéro. Cette étape sert aussi à choisir un nouveau PIN si vous l\'avez oublié.', node,
    h('p', { class: 'row-links' }, h('a', { href: '#/connexion' }, 'J\'ai déjà un compte')));
}

export function verifyOtp() {
  if (!state.flow?.phone) { navigate('/inscription', { replace: true }); return h('div'); }
  const code = field({ label: 'Code reçu par SMS (6 chiffres)', name: 'code', inputmode: 'numeric', maxlength: 6, autocomplete: 'one-time-code', required: true });
  code.input.addEventListener('input', () => { code.input.value = code.input.value.replace(/\D/g, '').slice(0, 6); });
  const node = form({
    fields: [{ field: code, validate: validate.otp }],
    submitLabel: 'Vérifier',
    onSubmit: async () => {
      const result = await api.post('/auth/otp/verify', { phone: state.flow.phone, code: code.input.value });
      state.flow = { ...state.flow, otpSessionToken: result.otpSessionToken, isNewUser: result.isNewUser };
      navigate('/inscription/pin');
    },
  });
  return authCard('Vérifiez votre numéro', `Un code a été envoyé au ${state.flow.phone}.`,
    state.flow.devCode ? h('p', { class: 'hint', role: 'note' }, `Mode développement : code ${state.flow.devCode}`) : null,
    node,
    h('p', { class: 'row-links' }, h('a', { href: '#/inscription' }, 'Changer de numéro')));
}

export function setupPin() {
  const flow = state.flow;
  if (!flow?.otpSessionToken) { navigate('/inscription', { replace: true }); return h('div'); }
  const name = field({ label: 'Nom de votre boutique', name: 'business', value: '', placeholder: 'Boutique Fatou', autocomplete: 'organization', required: true });
  const pin = pinField({ label: 'Code PIN (4 chiffres)', name: 'pin', autocomplete: 'new-password' });
  const confirm = pinField({ label: 'Confirmez le code PIN', name: 'confirm', autocomplete: 'new-password' });
  const consent = checkbox({ name: 'consent', label: h('span', {}, "J'ai lu et j'accepte les ", legalLinks(), '.') });
  const consentError = h('p', { class: 'field-error', role: 'alert', hidden: true }, 'Vous devez accepter pour continuer.');
  consent.input.addEventListener('change', () => { consentError.hidden = consent.input.checked; });
  const node = form({
    fields: [
      { field: name, validate: validate.businessName },
      { field: pin, validate: pin.validate },
      { field: confirm, validate: (v) => (v !== pin.input.value ? 'Les deux codes PIN ne correspondent pas.' : validate.pin(v)) },
    ],
    extra: [consent.el, consentError],
    submitLabel: flow.isNewUser ? 'Créer mon compte' : 'Enregistrer le nouveau PIN',
    onSubmit: async () => {
      if (!consent.input.checked) { consentError.hidden = false; consent.input.focus(); return; }
      const tokens = await api.post('/auth/pin/setup', {
        otpSessionToken: flow.otpSessionToken,
        businessName: name.input.value.trim(),
        pin: pin.input.value,
        termsVersion: TERMS_VERSION,
      });
      state.flow = null;
      await openSession(tokens);
    },
  });
  return authCard(flow.isNewUser ? 'Créez votre compte' : 'Choisissez un nouveau PIN',
    flow.isNewUser ? 'Dernière étape : le nom de votre boutique et un code PIN que vous seul connaissez.'
      : 'Votre numéro est vérifié. Les autres appareils devront se reconnecter avec le nouveau PIN.', node);
}

/** Nouvelle version des conditions : l'accès au carnet reste bloqué tant qu'elle n'est pas acceptée. */
export function reconsent() {
  const consent = checkbox({ name: 'consent', label: h('span', {}, "J'ai lu et j'accepte les ", legalLinks(), '.') });
  const node = form({
    extra: [consent.el],
    submitLabel: 'Accepter et continuer',
    onSubmit: async () => {
      if (!consent.input.checked) throw new Error('Vous devez accepter pour continuer.');
      state.profile = { ...state.profile, ...(await api.post('/auth/consent', { termsVersion: TERMS_VERSION })) };
      toast('Merci, votre choix est enregistré.');
      navigate('/clients', { replace: true });
    },
  });
  return authCard('Conditions mises à jour', "Pour continuer à utiliser Carné, vous devez accepter la version en vigueur. Vos données restent intactes.", node,
    h('p', { class: 'row-links' }, h('a', { href: '#/connexion', onclick: logoutLocal }, 'Me déconnecter')));
}

function logoutLocal() {
  session.clear();
  state.profile = null;
}

export { errorBanner };
