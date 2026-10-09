import { h } from '../dom.js';
import { api, state, clearLocalSession } from '../state.js';
import { confirmDialog, emptyState, field, form as buildForm, pageTitle, pinField, saveBlob, toast } from '../ui.js';
import { formatDate, formatMoney, formatTime, validate } from '../format.js';
import { activityLabel } from '../model.js';
import { navigate } from '../nav.js';

const today = () => new Date().toISOString().slice(0, 10);

async function download(path, filename, type) {
  const blob = await api.download(path);
  saveBlob(new Blob([blob], { type }), filename);
  toast('Fichier enregistré sur votre appareil.');
}

function back() { return h('p', {}, h('a', { href: '#/reglages' }, '← Réglages')); }

export async function main() {
  const subscription = await api.get('/subscription/status');
  state.subscription = subscription;
  const profile = state.profile;
  const premium = subscription.plan === 'PREMIUM';
  const guard = (fn) => async () => { try { await fn(); } catch (e) { toast(e.message); } };

  const upgrade = guard(async () => {
    const ok = await confirmDialog({ title: 'Passer à Premium ?', message: `${formatMoney(subscription.monthlyPriceFcfa * 100)} pour 30 jours, payés par Mobile Money.`, confirmLabel: 'Continuer' });
    if (!ok) return;
    const result = await api.post('/subscription/upgrade');
    toast(result?.message ?? 'Demande envoyée.');
    state.subscription = null;
    state.profile = null;
    navigate('/reglages');
  });
  const logout = guard(async () => {
    try { await api.post('/auth/logout'); } catch { /* la session locale est fermée dans tous les cas */ }
    clearLocalSession();
    navigate('/connexion');
  });

  return h('section', {},
    pageTitle('Réglages'),
    h('div', { class: 'card' },
      h('h2', {}, 'Mon compte'),
      h('p', {}, h('strong', {}, profile.businessName), h('br'), profile.phone),
      h('div', { class: 'row wrap' },
        h('a', { class: 'btn ghost', href: '#/reglages/boutique' }, 'Changer le nom'),
        h('a', { class: 'btn ghost', href: '#/reglages/pin' }, 'Changer le code PIN'))),
    h('div', { class: 'card' },
      h('h2', {}, 'Formule'),
      premium
        ? h('p', {}, `Premium actif jusqu'au ${formatDate(subscription.planExpiresAt)}.`)
        : h('p', {}, `Gratuite : ${subscription.customerCount} client(s) sur ${subscription.customerLimit}. Le bilan et les relances automatiques sont réservés à Premium.`),
      !premium && subscription.paymentsAvailable ? h('button', { type: 'button', class: 'btn primary', onclick: upgrade }, 'Passer à Premium') : null,
      !premium && !subscription.paymentsAvailable ? h('p', { class: 'hint' }, "Le paiement de la formule Premium n'est pas encore ouvert.") : null),
    h('div', { class: 'card' },
      h('h2', {}, 'Mes données'),
      h('p', { class: 'hint' }, 'Vos données vous appartiennent : téléchargez-les à tout moment.'),
      h('div', { class: 'row wrap' },
        h('button', { type: 'button', class: 'btn ghost', onclick: guard(() => download('/auth/export', `carne-mes-donnees-${today()}.json`, 'application/json')) }, 'Toutes mes données (JSON)'),
        h('button', { type: 'button', class: 'btn ghost', onclick: guard(() => download('/export/history', `carne-historique-${today()}.csv`, 'text/csv')) }, 'Historique (tableur CSV)'),
        h('button', { type: 'button', class: 'btn ghost', onclick: guard(() => download('/export/cash', `carne-caisse-${today()}.csv`, 'text/csv')) }, 'Caisse (tableur CSV)')),
      h('p', {}, h('a', { href: '#/reglages/activite' }, "Voir l'activité de mon compte"))),
    h('div', { class: 'card' },
      h('h2', {}, 'Confidentialité'),
      h('p', {}, h('a', { href: '../confidentialite.html' }, 'Politique de confidentialité'), h('br'), h('a', { href: '../conditions.html' }, "Conditions d'utilisation"), h('br'), h('a', { href: '../mentions-legales.html' }, 'Mentions légales')),
      profile.acceptedAt ? h('p', { class: 'hint' }, `Version ${profile.termsVersion} acceptée le ${formatDate(profile.acceptedAt)}.`) : null),
    h('div', { class: 'row wrap' },
      h('button', { type: 'button', class: 'btn ghost', onclick: logout }, 'Me déconnecter'),
      h('a', { class: 'btn danger-ghost', href: '#/reglages/suppression' }, 'Supprimer mon compte')),
    h('div', { class: 'about' },
      h('img', { class: 'civora', src: '../assets/civora-logo.png', width: 112, height: 114, alt: 'Logo CIVORA Conseil et Solutions' }),
      h('p', {}, h('strong', {}, 'Carné'), ' · conçu et développé par ', h('strong', {}, 'CIVORA CONSEIL ET SOLUTIONS'), '.')));
}

export async function activity() {
  const items = await api.get('/auth/activity');
  return h('section', {}, back(), pageTitle("Activité de mon compte"),
    h('p', { class: 'hint' }, "Les 100 derniers événements, conservés 12 mois. Aucun contenu de votre carnet ni adresse IP n'y figure."),
    items.length === 0 ? emptyState({ title: 'Aucune activité', message: '' })
      : h('ul', { class: 'cards' }, items.map((i) => h('li', { class: 'card row-card' }, h('span', { class: 'grow' }, activityLabel(i.action)), h('small', {}, `${formatDate(i.createdAt)} à ${formatTime(i.createdAt)}`)))));
}

export function changePin() {
  const current = pinField({ label: 'Code PIN actuel', name: 'current', autocomplete: 'current-password' });
  const next = pinField({ label: 'Nouveau code PIN', name: 'next', autocomplete: 'new-password' });
  const confirm = pinField({ label: 'Confirmez le nouveau code PIN', name: 'confirm', autocomplete: 'new-password' });
  return h('section', {}, back(), pageTitle('Changer le code PIN'),
    h('p', { class: 'hint' }, 'Après le changement, tous les autres appareils devront se reconnecter.'),
    buildForm({
      fields: [
        { field: current, validate: current.validate },
        { field: next, validate: next.validate },
        { field: confirm, validate: (v) => (v !== next.input.value ? 'Les deux codes PIN ne correspondent pas.' : validate.pin(v)) },
      ],
      submitLabel: 'Changer le PIN',
      onSubmit: async () => {
        await api.post('/auth/pin/change', { currentPin: current.input.value, newPin: next.input.value });
        // Le serveur révoque toutes les sessions : on se reconnecte.
        clearLocalSession();
        toast('PIN modifié. Reconnectez-vous avec le nouveau code.');
        navigate('/connexion');
      },
    }));
}

export function businessName() {
  const name = field({ label: 'Nom de votre boutique', name: 'business', value: state.profile.businessName, required: true, maxlength: 100 });
  return h('section', {}, back(), pageTitle('Nom de la boutique'),
    buildForm({
      fields: [{ field: name, validate: validate.businessName }],
      submitLabel: 'Enregistrer',
      onSubmit: async () => {
        state.profile = { ...state.profile, ...(await api.patch('/auth/me', { businessName: name.input.value.trim() })) };
        toast('Nom enregistré.');
        navigate('/reglages');
      },
    }));
}

export function deleteAccount() {
  const pin = pinField({ label: 'Code PIN pour confirmer', name: 'pin', autocomplete: 'current-password' });
  return h('section', {}, back(), pageTitle('Supprimer mon compte'),
    h('div', { class: 'warn card' },
      h('p', {}, h('strong', {}, 'Cette action est définitive.')),
      h('p', {}, 'Votre compte, vos clients, fournisseurs, ardoises, remboursements et opérations de caisse seront effacés des serveurs de Carné. Téléchargez d\'abord vos données si vous en avez besoin.')),
    buildForm({
      fields: [{ field: pin, validate: pin.validate }],
      submitLabel: 'Supprimer définitivement mon compte',
      danger: true,
      onSubmit: async () => {
        const ok = await confirmDialog({ title: 'Supprimer définitivement ?', message: 'Il sera impossible de récupérer ces données.', confirmLabel: 'Oui, tout supprimer', destructive: true });
        if (!ok) return;
        await api.post('/auth/account/delete', { pin: pin.input.value });
        clearLocalSession();
        toast('Votre compte a été supprimé.');
        navigate('/connexion');
      },
    }));
}
