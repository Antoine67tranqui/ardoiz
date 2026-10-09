import { h, mount, append } from './dom.js';
import { initials, validate, digitsOnly } from './format.js';

let toastTimer = null;

/** Message bref annoncé aux lecteurs d'écran (région live). */
export function toast(message) {
  const region = document.getElementById('toast');
  if (!region) return;
  region.textContent = message;
  region.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => region.classList.remove('show'), 4500);
}

/** Confirmation modale ; renvoie vrai si l'utilisateur confirme. */
export function confirmDialog({ title, message, confirmLabel = 'Confirmer', destructive = false }) {
  return new Promise((resolve) => {
    const dialog = h('dialog', { class: 'modal', 'aria-labelledby': 'dlg-title' },
      h('h2', { id: 'dlg-title' }, title),
      h('p', {}, message),
      h('div', { class: 'row end' },
        h('button', { type: 'button', class: 'btn ghost', onclick: () => dialog.close('no') }, 'Annuler'),
        h('button', { type: 'button', class: `btn ${destructive ? 'danger' : 'primary'}`, onclick: () => dialog.close('yes') }, confirmLabel)));
    dialog.addEventListener('close', () => { dialog.remove(); resolve(dialog.returnValue === 'yes'); });
    dialog.addEventListener('cancel', () => { dialog.returnValue = 'no'; });
    document.body.append(dialog);
    dialog.showModal();
  });
}

export const errorBanner = (message) => h('div', { class: 'error-banner', role: 'alert' }, message);

export function emptyState({ title, message, action }) {
  return h('div', { class: 'empty' }, h('h2', {}, title), h('p', {}, message), action ?? null);
}

export const avatar = (name) => h('span', { class: 'avatar', 'aria-hidden': 'true' }, initials(name));

export function loading(label = 'Chargement…') {
  return h('p', { class: 'loading', role: 'status' }, label);
}

/** Statut d'une dette : toujours un texte et une icône (jamais la couleur seule). */
export function statusBadge(debt) {
  const [icon, label, cls] = debt.overdueDays > 0
    ? ['⚠', `En retard de ${debt.overdueDays} j`, 'overdue']
    : debt.status === 'PAID' ? ['✓', 'Soldée', 'paid']
      : debt.status === 'PARTIAL' ? ['◐', 'Partielle', 'partial']
        : ['○', 'À payer', 'pending'];
  return h('span', { class: `badge ${cls}` }, h('span', { 'aria-hidden': 'true' }, icon), ' ', label);
}

/**
 * Champ de formulaire accessible : libellé lié, aide, erreur annoncée.
 * Renvoie { el, input, error(message) }.
 */
let fieldCounter = 0;
export function field({ label, name, type = 'text', value = '', hint = null, required = false, ...attrs }) {
  const id = `f-${name}-${fieldCounter++}`;
  const input = type === 'textarea'
    ? h('textarea', { id, name, rows: 2, value, ...attrs })
    : h('input', { id, name, type, value, required, ...attrs });
  const errorEl = h('p', { class: 'field-error', id: `${id}-err`, role: 'alert', hidden: true });
  const hintEl = hint ? h('p', { class: 'hint', id: `${id}-hint` }, hint) : null;
  const el = h('div', { class: 'field' }, h('label', { for: id }, label), input, hintEl, errorEl);
  return {
    el,
    input,
    error(message) {
      errorEl.hidden = !message;
      errorEl.textContent = message ?? '';
      input.toggleAttribute('aria-invalid', Boolean(message));
      input.setAttribute('aria-describedby', [message ? errorEl.id : null, hintEl?.id].filter(Boolean).join(' '));
    },
  };
}

/** Interrupteur à cocher avec libellé. */
export function checkbox({ label, name, checked = false, hint = null }) {
  const id = `c-${name}-${fieldCounter++}`;
  const input = h('input', { id, name, type: 'checkbox', checked });
  return { el: h('div', { class: 'check' }, input, h('label', { for: id }, label), hint ? h('p', { class: 'hint' }, hint) : null), input };
}

/** Puces de choix unique (catégories, dates rapides). */
export function chips({ options, selected, onChange, label }) {
  const root = h('div', { class: 'chips', role: 'radiogroup', 'aria-label': label });
  const render = (current) => mount(root, options.map((option) => h('button', {
    type: 'button',
    class: `chip${option === current ? ' on' : ''}`,
    role: 'radio',
    'aria-checked': option === current ? 'true' : 'false',
    onclick: () => { onChange(option); render(option); },
  }, option)));
  render(selected);
  return { el: root, set: render };
}

/**
 * Formulaire avec validation, état « en cours » (pas de double envoi) et bandeau d'erreur.
 * fields : [{ validate(value) -> message|null, field }] ; submit() est appelé si tout est valide.
 */
export function form({ fields = [], submitLabel, onSubmit, extra = [], danger = false }) {
  const banner = h('div', { class: 'banner-slot' });
  const button = h('button', { type: 'submit', class: `btn ${danger ? 'danger' : 'primary'}` }, submitLabel);
  const root = h('form', { novalidate: true, class: 'form' }, fields.map((f) => f.field?.el ?? f.el ?? f), extra, banner, button);
  let busy = false;
  root.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (busy) return;
    let valid = true;
    for (const f of fields) {
      if (!f.validate) continue;
      const message = f.validate(f.field.input.value);
      f.field.error(message);
      if (message && valid) { f.field.input.focus(); valid = false; }
    }
    if (!valid) return;
    busy = true;
    button.disabled = true;
    banner.replaceChildren();
    try {
      await onSubmit();
    } catch (error) {
      banner.replaceChildren(errorBanner(error.message || 'Une erreur est survenue. Réessayez.'));
    } finally {
      busy = false;
      button.disabled = false;
    }
  });
  return root;
}

/** Champ PIN : 4 chiffres, masqué, clavier numérique, jamais mémorisé par le navigateur. */
export function pinField({ label, name, hint = null, autocomplete = 'off' }) {
  const f = field({ label, name, type: 'password', inputmode: 'numeric', maxlength: 4, pattern: '[0-9]*', autocomplete, hint });
  f.input.addEventListener('input', () => { f.input.value = digitsOnly(f.input.value).slice(0, 4); });
  return { ...f, validate: (v) => validate.pin(v) };
}

export function pageTitle(text, ...actions) {
  return h('div', { class: 'page-title' }, h('h1', {}, text), h('div', { class: 'row' }, actions));
}

export { h, mount, append };

/** Enregistre un fichier côté navigateur (export CSV/JSON) sans le faire transiter par un tiers. */
export function saveBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = h('a', { href: url, download: filename, hidden: true });
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
