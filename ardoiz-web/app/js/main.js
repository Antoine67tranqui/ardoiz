import { h, mount } from './dom.js';
import { errorBanner, loading, toast } from './ui.js';
import { api, session, state, loadProfile } from './state.js';
import { navigate } from './nav.js';
import { ApiError } from './api.js';
import * as auth from './views/auth.js';
import * as parties from './views/parties.js';
import * as debts from './views/debts.js';
import * as cash from './views/cash.js';
import * as dashboard from './views/dashboard.js';
import * as settings from './views/settings.js';

const view = document.getElementById('view');
const tabs = document.getElementById('tabs');
const business = document.getElementById('business');

const TABS = [
  ['#/clients', 'Clients'],
  ['#/fournisseurs', 'Fournisseurs'],
  ['#/caisse', 'Caisse'],
  ['#/bilan', 'Bilan'],
  ['#/reglages', 'Réglages'],
];

// [motif, vue, publique ?, onglet actif]
const ROUTES = [
  [/^\/connexion$/, auth.login, true],
  [/^\/inscription$/, auth.requestOtp, true],
  [/^\/inscription\/code$/, auth.verifyOtp, true],
  [/^\/inscription\/pin$/, auth.setupPin, true],
  [/^\/consentement$/, auth.reconsent, false],
  [/^\/clients$/, (c) => parties.list(c, 'CLIENT'), false, '#/clients'],
  [/^\/clients\/nouveau$/, (c) => parties.form(c, { kind: 'CLIENT' }), false, '#/clients'],
  [/^\/fournisseurs$/, (c) => parties.list(c, 'SUPPLIER'), false, '#/fournisseurs'],
  [/^\/fournisseurs\/nouveau$/, (c) => parties.form(c, { kind: 'SUPPLIER' }), false, '#/fournisseurs'],
  [/^\/contacts\/([^/]+)$/, parties.detail, false, 'party'],
  [/^\/contacts\/([^/]+)\/modifier$/, (c) => parties.form(c, { editId: c.params[0] }), false, 'party'],
  [/^\/contacts\/([^/]+)\/dette$/, (c) => debts.form(c, { partyId: c.params[0] }), false, 'party'],
  [/^\/dettes\/([^/]+)$/, debts.detail, false, 'party'],
  [/^\/dettes\/([^/]+)\/modifier$/, (c) => debts.form(c, { debtId: c.params[0] }), false, 'party'],
  [/^\/caisse$/, cash.view, false, '#/caisse'],
  [/^\/bilan$/, dashboard.view, false, '#/bilan'],
  [/^\/reglages$/, settings.main, false, '#/reglages'],
  [/^\/reglages\/activite$/, settings.activity, false, '#/reglages'],
  [/^\/reglages\/pin$/, settings.changePin, false, '#/reglages'],
  [/^\/reglages\/boutique$/, settings.businessName, false, '#/reglages'],
  [/^\/reglages\/suppression$/, settings.deleteAccount, false, '#/reglages'],
];

function renderTabs(active) {
  tabs.hidden = !active;
  mount(tabs, active ? TABS.map(([href, label]) => h('a', { href, 'aria-current': href === active ? 'page' : null }, label)) : []);
}

let renderToken = 0;

async function render() {
  const token = ++renderToken;
  const path = location.hash.replace(/^#/, '') || '/';
  const match = ROUTES.map((r) => [r, r[0].exec(path)]).find(([, m]) => m);

  if (!match) return navigate(session.hasSession ? '/clients' : '/connexion', { replace: true });
  const [[, handler, isPublic, tab], m] = match;

  if (!isPublic) {
    if (!session.hasSession) return navigate('/connexion', { replace: true });
    try {
      if (!state.profile) {
        await loadProfile();
        business.textContent = state.profile.businessName;
      }
    } catch (error) {
      if (token !== renderToken) return;
      if (error instanceof ApiError && error.isUnauthorized) return;
      mount(view, errorBanner(error.message));
      return;
    }
    if (token !== renderToken) return;
    if (!state.profile.termsAccepted && path !== '/consentement') return navigate('/consentement', { replace: true });
  } else if (session.hasSession && state.profile && path === '/connexion') {
    return navigate('/clients', { replace: true });
  }

  business.textContent = isPublic ? '' : state.profile?.businessName ?? '';
  renderTabs(isPublic || path === '/consentement' ? null : tab === 'party' ? '#/clients' : tab);

  mount(view, loading());
  const ctx = { params: m.slice(1).map(decodeURIComponent), navigate, setTab: renderTabs, current: () => token === renderToken };
  try {
    const node = await handler(ctx);
    if (token !== renderToken) return;
    mount(view, node);
  } catch (error) {
    if (token !== renderToken) return;
    if (error instanceof ApiError && error.isUnauthorized) return;
    mount(view, errorBanner(error.message || 'Une erreur est survenue.'),
      h('button', { class: 'btn ghost', type: 'button', onclick: render }, 'Réessayer'));
  }
  view.focus({ preventScroll: true });
  window.scrollTo(0, 0);
}

session.onExpired = () => {
  state.profile = null;
  toast('Votre session a expiré. Reconnectez-vous.');
  navigate('/connexion', { replace: true });
};

// Reconnexion automatique à l'ouverture : le jeton de rafraîchissement de l'onglet suffit.
window.addEventListener('hashchange', render);
const offline = document.getElementById('offline');
const syncOnline = () => { offline.hidden = navigator.onLine; };
window.addEventListener('online', () => { syncOnline(); render(); });
window.addEventListener('offline', syncOnline);
syncOnline();

if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('sw.js').catch(() => { /* pas de cache hors ligne : sans gravité */ });
}

render();
