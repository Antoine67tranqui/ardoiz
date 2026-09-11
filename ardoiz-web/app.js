// Tunnel de demo temporaire (cloudflared) : le backend et le site statique
// sont exposes sur deux sous-domaines trycloudflare.com distincts, donc on
// ne peut pas deviner l'URL de l'API a partir de l'origine de la page comme
// en local. A retirer/ajuster si l'URL du tunnel backend change.
const DEMO_TUNNEL_API_BASE = 'https://penn-director-prison-pdt.trycloudflare.com/api/v1';

const API_BASE = window.location.hostname.endsWith('trycloudflare.com')
  ? DEMO_TUNNEL_API_BASE
  : window.location.origin.replace(/:\d+$/, ':3000') + '/api/v1';

const state = {
  screen: 'splash',
  phone: null,
  otpSessionToken: null,
  accessToken: localStorage.getItem('ardoiz_access_token'),
  refreshToken: localStorage.getItem('ardoiz_refresh_token'),
  businessName: localStorage.getItem('ardoiz_business_name'),
  customers: [],
  currentCustomer: null,
  debts: [],
  currentDebt: null,
  shopSummary: null,
  subscription: null,
  error: null,
};

async function extractError(res) {
  const body = await res.json().catch(() => ({}));
  const message = Array.isArray(body?.message?.message)
    ? body.message.message.join(', ')
    : body?.message?.message || body?.message || 'Erreur inconnue';
  const error = new Error(message);
  error.code = body?.message?.code;
  return error;
}

async function api(path, options = {}, isRetry = false) {
  const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
  if (state.accessToken) headers['Authorization'] = `Bearer ${state.accessToken}`;

  const res = await fetch(API_BASE + path, { ...options, headers });

  if (res.status === 401 && state.refreshToken && !isRetry) {
    // Le jeton d'acces a expire (duree de vie courte, 15 min) : on tente
    // un rafraichissement silencieux avant de considerer l'utilisateur
    // deconnecte, pour eviter des "Unauthorized" incomprehensibles en
    // pleine saisie.
    const refreshed = await tryRefreshToken();
    if (refreshed) return api(path, options, true);
    logout();
    throw new Error('Votre session a expire, veuillez vous reconnecter.');
  }

  if (!res.ok) throw await extractError(res);
  if (res.status === 204) return null;
  return res.json();
}

async function tryRefreshToken() {
  try {
    const res = await fetch(API_BASE + '/auth/refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken: state.refreshToken }),
    });
    if (!res.ok) return false;
    const data = await res.json();
    persistSession(data);
    return true;
  } catch {
    return false;
  }
}

function persistSession(data, businessName) {
  state.accessToken = data.accessToken;
  state.refreshToken = data.refreshToken;
  localStorage.setItem('ardoiz_access_token', data.accessToken);
  localStorage.setItem('ardoiz_refresh_token', data.refreshToken);
  if (businessName) {
    state.businessName = businessName;
    localStorage.setItem('ardoiz_business_name', businessName);
  }
}

function logout() {
  state.accessToken = null;
  state.refreshToken = null;
  state.businessName = null;
  localStorage.clear();
  goTo('phone');
}

function goTo(screen, params = {}) {
  state.screen = screen;
  state.error = null;
  Object.assign(state, params);
  render();
}

function formatFcfa(amount) {
  return new Intl.NumberFormat('fr-FR').format(amount) + ' FCFA';
}

const CATEGORY_ICONS = {
  'Alimentation': '🍚',
  'Boissons': '🥤',
  'Hygiene & cosmetique': '🧴',
  'Menage': '🧹',
  'Vetements': '👕',
  'Electronique & accessoires': '🔌',
  'Autre': '🏷️',
};

function categoryIcon(category) {
  return CATEGORY_ICONS[category] || '🏷️';
}

const AVATAR_PALETTE = ['#0b6e4f', '#e8873a', '#2e6b9e', '#a34ba0', '#c2410c', '#0e7c66'];

function avatarColor(name) {
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash);
  return AVATAR_PALETTE[Math.abs(hash) % AVATAR_PALETTE.length];
}

function avatarInitial(name) {
  return (name.trim()[0] || '?').toUpperCase();
}

function toast(message, duration = 2500) {
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = message;
  document.body.appendChild(el);
  setTimeout(() => {
    el.classList.add('toast-hide');
    setTimeout(() => el.remove(), 250);
  }, duration);
}

// --- Modale generique (remplace prompt()/alert(), peu fiables et peu
// lisibles sur mobile, par une feuille en bas d'ecran coherente avec le
// design de l'app) ---

function closeModal() {
  const overlay = document.getElementById('modal-overlay');
  if (overlay) overlay.remove();
}

function openModal(innerHtml, onMount) {
  closeModal();
  const overlay = document.createElement('div');
  overlay.id = 'modal-overlay';
  overlay.className = 'modal-overlay';
  overlay.innerHTML = `<div class="modal-sheet">${innerHtml}</div>`;
  overlay.addEventListener('click', (e) => { if (e.target === overlay) closeModal(); });
  document.body.appendChild(overlay);
  if (onMount) onMount(overlay);
}

function setButtonLoading(button, loading) {
  if (!button) return;
  button.disabled = loading;
  button.classList.toggle('loading', loading);
}

// --- Screens ---

function renderSplash() {
  return `
    <div class="hero-bg hero-bg-1">
      <div class="hero-content">
        <img src="logo-icon.png" alt="Ardoiz" class="splash-logo-small anim-in" style="animation-delay:0.05s" />

        <div class="hook-questions">
          <p class="anim-in" style="animation-delay:0.15s">😩 Vous en avez marre de ne plus savoir qui vous doit de l'argent ?</p>
          <p class="anim-in" style="animation-delay:0.30s">📒 Votre carnet de credit est raye, perdu ou illisible ?</p>
          <p class="anim-in" style="animation-delay:0.45s">🤷 Vos clients "oublient" leur ardoise, et vous n'osez pas insister ?</p>
        </div>

        <div class="hook-pitch anim-in" style="animation-delay:0.6s">
          <p>
            <strong>Ardoiz</strong> vous permet de tenir un registre numerique
            de toutes les dettes de vos clients, d'etre rembourse a temps
            grace aux rappels automatiques, et de garder le controle total
            de votre tresorerie, le tout depuis votre telephone.
          </p>
        </div>

        <button class="primary anim-in" id="splash-continue-btn" style="max-width:320px;animation-delay:0.75s">Commencer</button>
      </div>
    </div>`;
}

function renderPhone() {
  return `
    <div class="hero-bg hero-bg-2">
      <header class="topbar hero-topbar">
        <button class="back-btn hero-back-btn" id="back-to-splash-btn">&larr;</button>
        <h1 style="color:#fff">Connexion</h1><span></span>
      </header>
      <div class="hero-content" style="padding-top:40px">
        <h2 class="title anim-in" style="color:#fff">Entrez votre numero de telephone</h2>
        <p class="subtitle anim-in" style="color:rgba(255,255,255,0.75);animation-delay:0.1s">
          Un code de verification vous sera envoye par SMS pour confirmer que c'est bien vous.
        </p>
        <div class="anim-in" style="animation-delay:0.2s">
          <input id="phone-input" type="tel" placeholder="+229 01 67 07 70 27" value="+229" />
        </div>
        ${state.error ? `<div class="error-text anim-in">${state.error}</div>` : ''}
        <button class="primary anim-in" id="submit-phone" style="animation-delay:0.3s">Recevoir le code</button>
      </div>
    </div>`;
}

function renderOtp() {
  return `
    <header class="topbar">
      <button class="back-btn" id="back-btn">&larr;</button>
      <h1>Verification</h1><span></span>
    </header>
    <main>
      <h2 class="title">Entrez le code recu par SMS</h2>
      <p class="subtitle">Envoye au ${state.phone}</p>
      <input id="otp-input" type="text" inputmode="numeric" pattern="[0-9]*" autocomplete="one-time-code" maxlength="6" placeholder="123456" style="text-align:center;font-size:24px;letter-spacing:8px" />
      ${state.error ? `<div class="error-text">${state.error}</div>` : ''}
      <button class="primary" id="submit-otp">Verifier</button>
    </main>`;
}

function renderPinSetup() {
  return `
    <header class="topbar"><h1>Creer votre compte</h1></header>
    <main>
      <h2 class="title">Nom de votre boutique</h2>
      <input id="business-input" type="text" autocomplete="off" placeholder="Ex: Boutique Fatou" />
      <h2 class="title">Creez votre PIN (4 chiffres)</h2>
      <input id="pin-input" class="pin-mask" type="text" inputmode="numeric" pattern="[0-9]*" autocomplete="off" maxlength="4" placeholder="1234" style="text-align:center;font-size:24px;letter-spacing:8px" />
      ${state.error ? `<div class="error-text">${state.error}</div>` : ''}
      <button class="primary" id="submit-pin-setup">Creer mon compte</button>
    </main>`;
}

function renderLoginPin() {
  return `
    <header class="topbar"><h1>Entrez votre PIN</h1></header>
    <main>
      <input id="login-pin-input" class="pin-mask" type="text" inputmode="numeric" pattern="[0-9]*" autocomplete="off" maxlength="4" placeholder="1234" style="text-align:center;font-size:24px;letter-spacing:8px" />
      ${state.error ? `<div class="error-text">${state.error}</div>` : ''}
      <button class="primary" id="submit-login-pin">Se connecter</button>
    </main>`;
}

function renderPlanBadge() {
  const s = state.subscription;
  if (!s) return '';

  if (s.plan === 'PREMIUM') {
    const expiry = s.planExpiresAt ? new Date(s.planExpiresAt).toLocaleDateString('fr-FR') : '';
    return `<div class="plan-badge premium">✓ Premium actif${expiry ? ' jusqu\'au ' + expiry : ''}</div>`;
  }

  return `
    <div class="plan-badge free">
      <span>Plan gratuit · ${s.customerCount}/${s.customerLimit} clients</span>
      <button class="link" id="plan-badge-upgrade-btn">Passer a Premium</button>
    </div>`;
}

function renderQuickStats() {
  const total = state.customers.length;
  const upToDate = state.customers.filter((c) => c.outstandingBalance <= 0).length;
  const withDebt = total - upToDate;

  return `
    <div class="quick-stats">
      <div class="stat-tile stagger-item" style="animation-delay:0s">
        <span class="stat-value" data-count-target="${total}">0</span>
        <span class="stat-label">Client${total > 1 ? 's' : ''}</span>
      </div>
      <div class="stat-tile stat-good stagger-item" style="animation-delay:0.08s">
        <span class="stat-value" data-count-target="${upToDate}">0</span>
        <span class="stat-label">A jour</span>
      </div>
      <div class="stat-tile stat-warn stagger-item" style="animation-delay:0.16s">
        <span class="stat-value" data-count-target="${withDebt}">0</span>
        <span class="stat-label">Avec ardoise</span>
      </div>
    </div>`;
}

function renderOnboardingChecklist() {
  return `
    <div class="onboarding-card">
      <div class="onboarding-emoji">👋</div>
      <h2 class="title" style="margin-top:4px">Bienvenue sur Ardoiz !</h2>
      <p class="subtitle">Voici comment demarrer en moins d'une minute :</p>
      <div class="onboarding-steps">
        <div class="onboarding-step"><span class="step-num">1</span> Ajoutez votre premier client</div>
        <div class="onboarding-step"><span class="step-num">2</span> Enregistrez sa premiere ardoise</div>
        <div class="onboarding-step"><span class="step-num">3</span> Encaissez et relancez en un clic</div>
      </div>
      <button class="primary" id="onboarding-add-customer-btn">+ Ajouter mon premier client</button>
    </div>`;
}

function renderDashboard() {
  const rows = state.customers.length
    ? state.customers.map((c, i) => {
        const hasDebt = c.outstandingBalance > 0;
        const color = hasDebt ? 'var(--status-partial)' : 'var(--status-paid)';
        return `
          <div class="card stagger-item" style="animation-delay:${Math.min(i * 0.05, 0.4)}s" data-customer-id="${c.id}">
            <div class="avatar" style="background:${avatarColor(c.name)}">${avatarInitial(c.name)}</div>
            <div class="info">
              <div class="name">${c.name}</div>
              ${c.phone ? `<div class="phone">${c.phone}</div>` : ''}
            </div>
            <div class="balance" style="color:${color}">${hasDebt ? formatFcfa(c.outstandingBalance) : '✓ A jour'}</div>
          </div>`;
      }).join('')
    : '';

  return `
    <header class="topbar">
      <div style="display:flex;align-items:center;gap:10px">
        <img src="logo-icon.png" alt="Ardoiz" class="topbar-logo" />
        <h1>${state.businessName || 'Ardoiz'}</h1>
      </div>
    </header>
    ${renderPlanBadge()}
    <main id="customer-list">
      ${state.customers.length ? renderQuickStats() : ''}
      ${state.customers.length ? rows : renderOnboardingChecklist()}
    </main>
    ${state.customers.length ? '<button class="fab" id="add-customer-fab">+ Client</button>' : ''}`;
}

function renderShopDashboard() {
  const s = state.shopSummary;
  if (!s) return `<header class="topbar"><h1>Tableau de bord</h1></header><main></main>`;

  if (s.locked) {
    return `
      <header class="topbar"><h1>Bilan de la boutique</h1></header>
      <main>
        <div class="card" style="cursor:default;flex-direction:column;align-items:stretch;gap:10px;text-align:center;padding:32px 20px">
          <div style="font-size:40px">🔒</div>
          <h2 class="title" style="margin:0">Fonctionnalite Premium</h2>
          <p class="subtitle" style="margin:0">
            Le tableau de bord (total du, categories, retardataires) est
            reserve aux comptes Premium.
          </p>
          <button class="primary" id="upgrade-from-dashboard-btn">Passer a Premium</button>
        </div>
      </main>`;
  }

  const categoryRows = s.byCategory.length
    ? s.byCategory.map((c, i) => {
        const pct = s.totalOutstanding > 0 ? Math.round((c.totalOutstanding / s.totalOutstanding) * 100) : 0;
        return `
          <div class="card stagger-item" style="cursor:default;animation-delay:${Math.min(i * 0.06, 0.4)}s">
            <div class="avatar" style="background:var(--surface);border:1px solid rgba(0,0,0,0.06);font-size:20px">${categoryIcon(c.category)}</div>
            <div class="info">
              <div class="name">${c.category}</div>
              <div class="phone">${c.count} dette(s) en cours</div>
              <div class="progress-track">
                <div class="progress-fill" data-pct="${pct}" style="width:0%"></div>
              </div>
            </div>
            <div class="balance" style="color:var(--status-partial)">${formatFcfa(c.totalOutstanding)}</div>
          </div>`;
      }).join('')
    : `<div class="empty-state">Aucune dette enregistree.</div>`;

  const overdueRows = s.overdueDebts.length
    ? s.overdueDebts.map((d, i) => `
        <div class="debt-card stagger-item" style="animation-delay:${Math.min(i * 0.06, 0.4)}s">
          <div class="debt-amount">${categoryIcon(d.category)} ${d.customerName} · ${formatFcfa(d.outstanding)}</div>
          <div class="debt-reason">${d.category}</div>
          <div class="debt-status" style="color:var(--status-overdue)">En retard de ${d.daysOverdue} jour(s) (echeance ${new Date(d.dueDate).toLocaleDateString('fr-FR')})</div>
          <div class="debt-actions">
            <button class="outline" data-remind-debt="${d.debtId}" style="margin-top:8px">Relancer ${d.customerName}</button>
          </div>
        </div>`).join('')
    : `<div class="empty-state">🎉 Aucun retardataire. Bravo !</div>`;

  return `
    <header class="topbar"><h1>Bilan de la boutique</h1></header>
    <main>
      <div class="card hero-stat-card" style="cursor:default;flex-direction:column;align-items:stretch;gap:4px">
        <span class="phone">Total du par vos clients</span>
        <span style="font-size:28px;font-weight:700;color:var(--status-partial)">${formatFcfa(s.totalOutstanding)}</span>
        <span class="phone">${s.customersWithDebt} client(s) endette(s) sur ${s.totalCustomers}</span>
      </div>

      <h2 class="title" style="margin-top:24px">Par categorie de produit</h2>
      ${categoryRows}

      <h2 class="title" style="margin-top:24px">Retardataires</h2>
      ${overdueRows}
    </main>`;
}

function renderCustomerDetail() {
  const c = state.currentCustomer;
  const now = new Date();
  const rows = state.debts.length
    ? state.debts.map((d, i) => {
        const statusLabel = { PENDING: 'En attente', PARTIAL: 'Partiellement remboursee', PAID: 'Remboursee' }[d.status];
        const isOverdue = d.status !== 'PAID' && d.dueDate && new Date(d.dueDate) < now;
        const statusColor = isOverdue
          ? 'var(--status-overdue)'
          : { PENDING: 'var(--text-secondary)', PARTIAL: 'var(--status-partial)', PAID: 'var(--status-paid)' }[d.status];
        const daysOverdue = isOverdue ? Math.floor((now - new Date(d.dueDate)) / 86400000) : 0;
        return `
          <div class="debt-card stagger-item" style="animation-delay:${Math.min(i * 0.06, 0.4)}s">
            <div class="debt-amount">${formatFcfa(d.amount)}</div>
            ${d.category ? `<div class="debt-reason">${categoryIcon(d.category)} ${d.category}${d.reason ? ' · ' + d.reason : ''}</div>` : (d.reason ? `<div class="debt-reason">${d.reason}</div>` : '')}
            <div class="debt-date">Enregistree le ${new Date(d.createdAt).toLocaleDateString('fr-FR')}</div>
            ${d.dueDate ? `<div class="debt-date">Echeance : ${new Date(d.dueDate).toLocaleDateString('fr-FR')}</div>` : ''}
            <div class="debt-status" style="color:${statusColor}">${isOverdue ? `En retard de ${daysOverdue} jour(s)` : statusLabel}</div>
            ${d.status !== 'PAID' ? `
              <div class="debt-actions" style="display:flex;gap:8px">
                <button class="outline" style="flex:1;margin-top:0" data-pay-debt="${d.id}" data-amount="${d.amount}">Encaisser</button>
                <button class="outline" style="flex:1;margin-top:0" data-remind-debt="${d.id}">Relancer</button>
              </div>` : ''}
          </div>`;
      }).join('')
    : `<div class="empty-state">Aucune dette enregistree pour ce client.</div>`;

  return `
    <header class="topbar">
      <button class="back-btn" id="back-btn">&larr;</button>
      <h1>${c.name}</h1>
      <button class="back-btn" id="edit-customer-btn" title="Modifier">&#9998;</button>
    </header>
    <main>
      <p class="subtitle" style="margin-top:-10px">${c.phone}</p>
      ${rows}
    </main>
    <button class="fab" id="add-debt-fab">+ Ardoise</button>`;
}

const DEBT_CATEGORIES = ['Alimentation', 'Boissons', 'Hygiene & cosmetique', 'Menage', 'Vetements', 'Electronique & accessoires'];

function getCustomCategories() {
  try {
    return JSON.parse(localStorage.getItem('ardoiz_custom_categories') || '[]');
  } catch {
    return [];
  }
}

function addCustomCategory(name) {
  const custom = getCustomCategories();
  if (!custom.includes(name) && !DEBT_CATEGORIES.includes(name)) {
    custom.push(name);
    localStorage.setItem('ardoiz_custom_categories', JSON.stringify(custom));
  }
}

function allCategories() {
  return [...DEBT_CATEGORIES, ...getCustomCategories(), 'Autre'];
}

function defaultDueDate() {
  const d = new Date();
  d.setDate(d.getDate() + 7);
  return d.toISOString().slice(0, 10);
}

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

function renderAddDebt() {
  return `
    <header class="topbar">
      <button class="back-btn" id="back-btn">&larr;</button>
      <h1>Nouvelle ardoise</h1><span></span>
    </header>
    <main>
      <p class="subtitle">Montant (FCFA)</p>
      <input id="debt-amount-input" type="number" placeholder="2500" style="font-size:22px;font-weight:700" />
      <p class="subtitle">Categorie de produit</p>
      <select id="debt-category-input">
        ${allCategories().map((cat) => `<option value="${cat}">${categoryIcon(cat)} ${cat}</option>`).join('')}
      </select>
      <div id="debt-new-category-wrap" style="display:none">
        <input id="debt-new-category-input" type="text" placeholder="Nom de la nouvelle categorie" autocomplete="off" />
      </div>
      <p class="subtitle">Motif (optionnel)</p>
      <input id="debt-reason-input" type="text" placeholder="Ex: Riz + huile" />
      <p class="subtitle">Date a laquelle le client doit rembourser</p>
      <input id="debt-duedate-input" type="date" value="${defaultDueDate()}" min="${todayIso()}" />
      <div id="debt-error-slot">${state.error ? `<div class="error-text">${state.error}</div>` : ''}</div>
      <button class="primary" id="submit-add-debt">Enregistrer</button>
    </main>`;
}

function renderPayment() {
  const d = state.currentDebt;
  return `
    <header class="topbar">
      <button class="back-btn" id="back-btn">&larr;</button>
      <h1>Encaisser</h1><span></span>
    </header>
    <main>
      <h2 class="title">Solde du : ${formatFcfa(d.amount)}</h2>
      <p class="subtitle">Montant recu</p>
      <input id="payment-amount-input" type="number" value="${d.amount}" style="font-size:22px;font-weight:700" />
      ${state.error ? `<div class="error-text">${state.error}</div>` : ''}
      <button class="primary" id="submit-cash-payment">Encaisser en especes</button>
      <button class="outline" id="momo-info-btn">Demander via Mobile Money</button>
    </main>`;
}

function renderSettings() {
  const s = state.subscription;
  const planLabel = s?.plan === 'PREMIUM'
    ? `Premium${s.planExpiresAt ? ' (jusqu\'au ' + new Date(s.planExpiresAt).toLocaleDateString('fr-FR') + ')' : ''}`
    : `Gratuit (${s?.customerCount ?? 0}/${s?.customerLimit ?? '-'} clients)`;

  return `
    <header class="topbar"><h1>Reglages</h1></header>
    <main>
      <div class="list-row"><span>Boutique</span><strong>${state.businessName || '-'}</strong></div>
      <div class="list-row"><span>Abonnement</span><strong>${planLabel}</strong></div>
      ${s?.plan !== 'PREMIUM' ? '<button class="primary" id="settings-upgrade-btn" style="margin-top:16px">Passer a Premium</button>' : ''}
      <button class="outline" id="download-history-btn" style="margin-top:16px">⬇ Telecharger mon historique (CSV)</button>
      <button class="logout-btn" id="logout-btn">Deconnexion</button>
    </main>`;
}

const TAB_SCREENS = ['dashboard', 'shop-dashboard', 'settings'];

function renderBottomNav() {
  const tabs = [
    { screen: 'dashboard', icon: '👥', label: 'Clients' },
    { screen: 'shop-dashboard', icon: '📊', label: 'Bilan' },
    { screen: 'settings', icon: '⚙️', label: 'Reglages' },
  ];
  return `
    <nav class="bottom-nav">
      ${tabs.map((t) => `
        <button class="nav-item${state.screen === t.screen ? ' active' : ''}" data-nav-target="${t.screen}">
          <span class="nav-icon">${t.icon}</span>
          <span class="nav-label">${t.label}</span>
        </button>`).join('')}
    </nav>`;
}

function render() {
  const app = document.getElementById('app');
  const renderers = {
    splash: renderSplash,
    phone: renderPhone,
    otp: renderOtp,
    'pin-setup': renderPinSetup,
    'login-pin': renderLoginPin,
    dashboard: renderDashboard,
    'shop-dashboard': renderShopDashboard,
    'customer-detail': renderCustomerDetail,
    'add-debt': renderAddDebt,
    payment: renderPayment,
    settings: renderSettings,
  };
  const isTabScreen = TAB_SCREENS.includes(state.screen);
  app.innerHTML = renderers[state.screen]() + (isTabScreen ? renderBottomNav() : '');
  app.classList.toggle('with-bottom-nav', isTabScreen);

  // Petite animation de transition entre ecrans (relance l'animation CSS
  // en forcant un reflow, car on reutilise le meme element a chaque rendu).
  app.classList.remove('screen-fade');
  void app.offsetWidth;
  app.classList.add('screen-fade');

  attachHandlers();
  runEntryAnimations();
}

function animateCountUp(el, target, duration = 700) {
  if (!target) { el.textContent = '0'; return; }
  const start = performance.now();
  function step(now) {
    const progress = Math.min((now - start) / duration, 1);
    const eased = 1 - Math.pow(1 - progress, 3);
    el.textContent = Math.round(target * eased);
    if (progress < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}

function runEntryAnimations() {
  // Barres de progression : demarrent a 0 puis transitionnent vers leur
  // largeur cible pour un effet de remplissage plutot qu'un affichage brut.
  requestAnimationFrame(() => {
    document.querySelectorAll('.progress-fill[data-pct]').forEach((el) => {
      el.style.width = el.dataset.pct + '%';
    });
  });

  // Compteurs animes sur le bandeau de statistiques.
  document.querySelectorAll('.stat-value[data-count-target]').forEach((el) => {
    animateCountUp(el, parseInt(el.dataset.countTarget, 10));
  });
}

function attachHandlers() {
  const on = (id, event, fn) => {
    const el = document.getElementById(id);
    if (el) el.addEventListener(event, fn);
  };

  on('back-btn', 'click', async () => {
    if (state.screen === 'customer-detail' || state.screen === 'settings' || state.screen === 'shop-dashboard') return loadCustomers();
    if (state.screen === 'add-debt' || state.screen === 'payment') return openCustomer(state.currentCustomer.id);
    if (state.screen === 'otp') return goTo('phone');
  });

  document.querySelectorAll('[data-nav-target]').forEach((el) => {
    el.addEventListener('click', () => {
      if (state.screen === el.dataset.navTarget) return;
      if (el.dataset.navTarget === 'shop-dashboard') return loadShopDashboard();
      if (el.dataset.navTarget === 'dashboard') return loadCustomers();
      goTo(el.dataset.navTarget);
    });
  });

  on('splash-continue-btn', 'click', () => goTo('phone'));
  on('back-to-splash-btn', 'click', () => goTo('splash'));
  on('settings-btn', 'click', () => goTo('settings'));
  on('shop-dashboard-btn', 'click', loadShopDashboard);
  on('logout-btn', 'click', logout);
  on('plan-badge-upgrade-btn', 'click', openUpgradeModal);
  on('upgrade-from-dashboard-btn', 'click', openUpgradeModal);
  on('settings-upgrade-btn', 'click', openUpgradeModal);
  on('download-history-btn', 'click', downloadHistoryCsv);

  on('submit-phone', 'click', async () => {
    const btn = document.getElementById('submit-phone');
    const phone = document.getElementById('phone-input').value.trim();
    if (!phone || phone.length < 8) { state.error = 'Entrez un numero de telephone valide.'; render(); return; }
    setButtonLoading(btn, true);
    try {
      const result = await api('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone }) });
      state.phone = phone;
      goTo('otp');
      // Aucun fournisseur SMS reel configure cote backend : le code est
      // simule et renvoye ici uniquement pour permettre de tester le
      // parcours sans reception SMS reelle.
      if (result.devCode) toast(`[Test] Code OTP : ${result.devCode}`, 15000);
    } catch (e) { state.error = e.message; render(); }
  });

  on('submit-otp', 'click', async () => {
    const btn = document.getElementById('submit-otp');
    const code = document.getElementById('otp-input').value.trim();
    if (code.length !== 6) { state.error = 'Le code doit contenir 6 chiffres.'; render(); return; }
    setButtonLoading(btn, true);
    try {
      const result = await api('/auth/otp/verify', { method: 'POST', body: JSON.stringify({ phone: state.phone, code }) });
      state.otpSessionToken = result.otpSessionToken;
      goTo(result.isNewUser ? 'pin-setup' : 'login-pin');
    } catch (e) { state.error = e.message; render(); }
  });

  on('submit-pin-setup', 'click', async () => {
    const btn = document.getElementById('submit-pin-setup');
    const businessName = document.getElementById('business-input').value.trim();
    const pin = document.getElementById('pin-input').value.trim();
    if (!businessName) { state.error = 'Le nom de votre boutique est obligatoire.'; render(); return; }
    if (!/^\d{4}$/.test(pin)) { state.error = 'Le PIN doit contenir exactement 4 chiffres.'; render(); return; }
    setButtonLoading(btn, true);
    try {
      const data = await api('/auth/pin/setup', {
        method: 'POST',
        body: JSON.stringify({ otpSessionToken: state.otpSessionToken, businessName, pin }),
      });
      persistSession(data, businessName);
      await enterDashboard();
    } catch (e) { state.error = e.message; render(); }
  });

  on('submit-login-pin', 'click', async () => {
    const btn = document.getElementById('submit-login-pin');
    const pin = document.getElementById('login-pin-input').value.trim();
    if (!/^\d{4}$/.test(pin)) { state.error = 'Le PIN doit contenir exactement 4 chiffres.'; render(); return; }
    setButtonLoading(btn, true);
    try {
      const data = await api('/auth/login', { method: 'POST', body: JSON.stringify({ phone: state.phone, pin }) });
      persistSession(data);
      await enterDashboard();
    } catch (e) { state.error = e.message; render(); }
  });

  document.querySelectorAll('[data-customer-id]').forEach((el) => {
    el.addEventListener('click', () => openCustomer(el.dataset.customerId));
  });

  on('add-customer-fab', 'click', openAddCustomerModal);
  on('onboarding-add-customer-btn', 'click', openAddCustomerModal);

  on('add-debt-fab', 'click', () => goTo('add-debt'));

  on('debt-category-input', 'change', (e) => {
    const wrap = document.getElementById('debt-new-category-wrap');
    if (!wrap) return;
    wrap.style.display = e.target.value === 'Autre' ? 'block' : 'none';
    if (e.target.value === 'Autre') document.getElementById('debt-new-category-input')?.focus();
  });

  on('submit-add-debt', 'click', async () => {
    // Affiche l'erreur dans le slot dedie plutot que via un render() complet :
    // un re-rendu du formulaire effacerait ce que l'utilisateur vient de
    // saisir (montant, categorie personnalisee, motif...).
    const showFormError = (message) => {
      const slot = document.getElementById('debt-error-slot');
      if (slot) slot.innerHTML = `<div class="error-text">${message}</div>`;
    };

    const amount = parseFloat(document.getElementById('debt-amount-input').value);
    const selectedCategory = document.getElementById('debt-category-input').value;
    const newCategoryName = document.getElementById('debt-new-category-input')?.value.trim();
    const reason = document.getElementById('debt-reason-input').value.trim() || undefined;
    const dueDate = document.getElementById('debt-duedate-input').value;
    if (!amount || amount <= 0) return showFormError('Entrez un montant valide.');
    if (selectedCategory === 'Autre' && !newCategoryName) {
      return showFormError('Precisez le nom de la nouvelle categorie.');
    }
    if (!dueDate) return showFormError('La date de remboursement est obligatoire.');

    const category = selectedCategory === 'Autre' ? newCategoryName : selectedCategory;
    const btn = document.getElementById('submit-add-debt');
    setButtonLoading(btn, true);
    try {
      await api('/debts', {
        method: 'POST',
        body: JSON.stringify({ customerId: state.currentCustomer.id, amount, category, reason, dueDate }),
      });
      if (selectedCategory === 'Autre') addCustomCategory(newCategoryName);
      toast('Ardoise enregistree');
      await openCustomer(state.currentCustomer.id);
    } catch (e) {
      showFormError(e.message);
      setButtonLoading(btn, false);
    }
  });

  document.querySelectorAll('[data-pay-debt]').forEach((el) => {
    el.addEventListener('click', () => {
      state.currentDebt = { id: el.dataset.payDebt, amount: parseFloat(el.dataset.amount) };
      goTo('payment');
    });
  });

  document.querySelectorAll('[data-remind-debt]').forEach((el) => {
    el.addEventListener('click', () => sendReminder(el.dataset.remindDebt, el));
  });

  on('edit-customer-btn', 'click', () => openEditCustomerModal(state.currentCustomer));

  on('submit-cash-payment', 'click', async () => {
    const amount = parseFloat(document.getElementById('payment-amount-input').value);
    if (!amount || amount <= 0) { state.error = 'Entrez un montant valide.'; render(); return; }
    const btn = document.getElementById('submit-cash-payment');
    setButtonLoading(btn, true);
    try {
      await api('/payments', {
        method: 'POST',
        body: JSON.stringify({ debtId: state.currentDebt.id, amount, method: 'CASH' }),
      });
      const isFullyPaid = amount >= state.currentDebt.amount;
      const customerName = state.currentCustomer.name;
      await openCustomer(state.currentCustomer.id);
      if (isFullyPaid) openCelebrationModal(customerName, amount);
      else toast('Paiement enregistre');
    } catch (e) { state.error = e.message; render(); }
  });

  on('momo-info-btn', 'click', async () => {
    const btn = document.getElementById('momo-info-btn');
    setButtonLoading(btn, true);
    try {
      const result = await api('/payments/momo-request', {
        method: 'POST',
        body: JSON.stringify({ debtId: state.currentDebt.id }),
      });
      openModal(`
        <button class="modal-close" id="modal-close-btn">Fermer &times;</button>
        <h3>Demande de paiement envoyee</h3>
        <p class="hint">${result.message}</p>
        <p class="hint" style="font-family:monospace">Reference : ${result.reference}</p>
        <button class="primary" id="modal-ok-btn">Compris</button>
      `, (overlay) => {
        overlay.querySelector('#modal-close-btn').addEventListener('click', closeModal);
        overlay.querySelector('#modal-ok-btn').addEventListener('click', closeModal);
      });
    } catch (e) {
      toast(e.message);
    } finally {
      setButtonLoading(btn, false);
    }
  });
}

async function sendReminder(debtId, buttonEl) {
  setButtonLoading(buttonEl, true);
  try {
    const reminder = await api(`/debts/${debtId}/reminders`, {
      method: 'POST',
      body: JSON.stringify({ channel: 'SMS' }),
    });
    toast(reminder.status === 'SENT' ? 'Rappel envoye au client' : "Echec de l'envoi du rappel");
  } catch (e) {
    toast(e.message);
  } finally {
    setButtonLoading(buttonEl, false);
  }
}

function openCelebrationModal(customerName, amount) {
  openModal(`
    <div class="celebration">
      <div class="celebration-badge">✓</div>
      <h3 style="margin-top:14px">Ardoise soldee !</h3>
      <p class="hint">
        ${customerName} vient de rembourser ${formatFcfa(amount)}.
        Cette dette est maintenant entierement remboursee, bravo pour le suivi !
      </p>
      <button class="primary" id="celebration-ok-btn">Continuer</button>
    </div>
  `, (overlay) => {
    overlay.querySelector('#celebration-ok-btn').addEventListener('click', closeModal);
  });
}

function openUpgradeModal() {
  const price = state.subscription?.monthlyPriceFcfa ?? 2000;
  openModal(`
    <button class="modal-close" id="modal-close-btn">Fermer &times;</button>
    <h3>Passer a Premium</h3>
    <p class="hint">
      Clients illimites, tableau de bord (total du, categories, retardataires)
      et relances automatiques quotidiennes.
    </p>
    <p style="font-size:26px;font-weight:700;margin:4px 0 18px">${formatFcfa(price)} / mois</p>
    <div id="upgrade-error" class="error-text" style="display:none"></div>
    <button class="primary" id="upgrade-confirm-btn">Payer via Mobile Money</button>
  `, (overlay) => {
    overlay.querySelector('#modal-close-btn').addEventListener('click', closeModal);
    const errorEl = overlay.querySelector('#upgrade-error');
    const confirmBtn = overlay.querySelector('#upgrade-confirm-btn');

    confirmBtn.addEventListener('click', async () => {
      setButtonLoading(confirmBtn, true);
      try {
        const result = await api('/subscription/upgrade', { method: 'POST' });
        if (result.activated) {
          state.subscription = await api('/subscription/status');
          closeModal();
          toast('Abonnement Premium active !');
          if (state.screen === 'shop-dashboard') await loadShopDashboard();
          else render();
        } else {
          errorEl.textContent = result.message;
          errorEl.style.display = 'block';
          setButtonLoading(confirmBtn, false);
        }
      } catch (e) {
        errorEl.textContent = e.message;
        errorEl.style.display = 'block';
        setButtonLoading(confirmBtn, false);
      }
    });
  });
}

function openEditCustomerModal(customer) {
  openModal(`
    <button class="modal-close" id="modal-close-btn">Fermer &times;</button>
    <h3>Modifier le client</h3>
    <input id="modal-edit-name" type="text" placeholder="Nom du client" autocomplete="off" value="${customer.name}" />
    <input id="modal-edit-phone" type="tel" placeholder="Telephone" autocomplete="off" value="${customer.phone || ''}" />
    <div id="modal-edit-error" class="error-text" style="display:none"></div>
    <div class="modal-actions">
      <button class="outline" id="modal-cancel-btn" style="flex:1">Annuler</button>
      <button class="primary" id="modal-submit-btn" style="flex:1">Enregistrer</button>
    </div>
  `, (overlay) => {
    const nameInput = overlay.querySelector('#modal-edit-name');
    const phoneInput = overlay.querySelector('#modal-edit-phone');
    const errorEl = overlay.querySelector('#modal-edit-error');
    const submitBtn = overlay.querySelector('#modal-submit-btn');

    overlay.querySelector('#modal-close-btn').addEventListener('click', closeModal);
    overlay.querySelector('#modal-cancel-btn').addEventListener('click', closeModal);

    submitBtn.addEventListener('click', async () => {
      const name = nameInput.value.trim();
      const phone = phoneInput.value.trim();
      errorEl.style.display = 'none';
      if (!name) { errorEl.textContent = 'Le nom est obligatoire.'; errorEl.style.display = 'block'; return; }
      if (!phone) { errorEl.textContent = 'Le telephone est obligatoire.'; errorEl.style.display = 'block'; return; }
      setButtonLoading(submitBtn, true);
      try {
        await api(`/customers/${customer.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ name, phone }),
        });
        closeModal();
        toast('Client mis a jour');
        await openCustomer(customer.id);
      } catch (e) {
        errorEl.textContent = e.message;
        errorEl.style.display = 'block';
        setButtonLoading(submitBtn, false);
      }
    });
  });
}

function openAddCustomerModal() {
  openModal(`
    <button class="modal-close" id="modal-close-btn">Fermer &times;</button>
    <h3>Nouveau client</h3>
    <p class="hint">Ajoutez un client pour commencer a suivre son ardoise.</p>
    <input id="modal-customer-name" type="text" placeholder="Nom du client" autocomplete="off" />
    <input id="modal-customer-phone" type="tel" placeholder="Telephone (obligatoire)" autocomplete="off" />
    <div id="modal-customer-error" class="error-text" style="display:none"></div>
    <div class="modal-actions">
      <button class="outline" id="modal-cancel-btn" style="flex:1">Annuler</button>
      <button class="primary" id="modal-submit-btn" style="flex:1">Ajouter</button>
    </div>
  `, (overlay) => {
    const nameInput = overlay.querySelector('#modal-customer-name');
    const phoneInput = overlay.querySelector('#modal-customer-phone');
    const errorEl = overlay.querySelector('#modal-customer-error');
    const submitBtn = overlay.querySelector('#modal-submit-btn');

    nameInput.focus();
    overlay.querySelector('#modal-close-btn').addEventListener('click', closeModal);
    overlay.querySelector('#modal-cancel-btn').addEventListener('click', closeModal);

    submitBtn.addEventListener('click', async () => {
      const name = nameInput.value.trim();
      const phone = phoneInput.value.trim();
      errorEl.style.display = 'none';
      if (!name) {
        errorEl.textContent = 'Le nom du client est obligatoire.';
        errorEl.style.display = 'block';
        return;
      }
      if (!phone) {
        errorEl.textContent = 'Le telephone du client est obligatoire (relances et Mobile Money).';
        errorEl.style.display = 'block';
        return;
      }
      setButtonLoading(submitBtn, true);
      try {
        await api('/customers', {
          method: 'POST',
          body: JSON.stringify({ name, phone }),
        });
        closeModal();
        toast(`${name} a ete ajoute a vos clients`);
        await loadCustomers();
      } catch (e) {
        if (e.code === 'FREE_PLAN_LIMIT_REACHED') {
          closeModal();
          openUpgradeModal();
          return;
        }
        errorEl.textContent = e.message;
        errorEl.style.display = 'block';
        setButtonLoading(submitBtn, false);
      }
    });
  });
}

async function loadCustomers() {
  try {
    const [customers, subscription] = await Promise.all([
      api('/customers'),
      api('/subscription/status'),
    ]);
    state.customers = customers;
    state.subscription = subscription;
  } catch (e) {
    if (e.message.includes('401')) return logout();
    toast(e.message);
  }
  goTo('dashboard');
}

async function loadShopDashboard() {
  goTo('shop-dashboard');
  try {
    state.shopSummary = await api('/dashboard/summary');
  } catch (e) {
    state.shopSummary = { locked: true };
  }
  render();
}

async function downloadHistoryCsv() {
  const btn = document.getElementById('download-history-btn');
  setButtonLoading(btn, true);
  try {
    let res = await fetch(API_BASE + '/export/history', {
      headers: { Authorization: `Bearer ${state.accessToken}` },
    });
    if (res.status === 401) {
      const refreshed = await tryRefreshToken();
      if (!refreshed) return logout();
      res = await fetch(API_BASE + '/export/history', {
        headers: { Authorization: `Bearer ${state.accessToken}` },
      });
    }
    if (!res.ok) throw await extractError(res);

    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    const date = new Date().toISOString().slice(0, 10);
    link.download = `ardoiz-historique-${date}.csv`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
    toast('Historique telecharge');
  } catch (e) {
    toast(e.message || "Impossible de telecharger l'historique");
  } finally {
    setButtonLoading(btn, false);
  }
}

async function openCustomer(id) {
  try {
    const c = await api(`/customers/${id}`);
    state.currentCustomer = c;
    state.debts = c.debts || [];
    goTo('customer-detail');
  } catch (e) { toast(e.message); }
}

async function enterDashboard() {
  await loadCustomers();
}

async function init() {
  if (state.accessToken) {
    // Utilisateur deja connecte : pas besoin de repasser par l'accroche
    // marketing, on l'emmene directement a son tableau de bord.
    goTo('splash');
    setTimeout(() => enterDashboard(), 400);
    return;
  }

  // Aucune transition automatique : l'utilisateur decide quand avancer,
  // en cliquant "Commencer" (gere dans attachHandlers).
  goTo('splash');
}

init();
