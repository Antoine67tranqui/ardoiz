import { h } from '../dom.js';
import { api } from '../state.js';
import { avatar, chips, checkbox, confirmDialog, emptyState, field, form as buildForm, pageTitle, saveBlob, statusBadge, toast } from '../ui.js';
import { fold, formatDate, formatMoney, moneyInput, parseAmount, fromCents, validate, toCents } from '../format.js';
import { debtView, partyBalance } from '../model.js';
import { navigate } from '../nav.js';

const WORDS = {
  CLIENT: { plural: 'Clients', one: 'client', add: 'Ajouter un client', route: '#/clients', owed: 'Ce qu\'on me doit', newDebt: 'Nouvelle ardoise', none: 'Aucun client pour le moment', hint: 'Ajoutez votre premier client pour noter ce qu\'il vous doit.' },
  SUPPLIER: { plural: 'Fournisseurs', one: 'fournisseur', add: 'Ajouter un fournisseur', route: '#/fournisseurs', owed: 'Ce que je dois', newDebt: 'Nouvel achat à crédit', none: 'Aucun fournisseur pour le moment', hint: 'Ajoutez un fournisseur pour suivre ce que vous lui devez.' },
};
export const wordsFor = (kind) => WORDS[kind];

const SORTS = {
  Récents: (a, b) => new Date(b.createdAt) - new Date(a.createdAt),
  Nom: (a, b) => a.name.localeCompare(b.name, 'fr'),
  'Solde décroissant': (a, b) => b.balance - a.balance,
};

export async function list(ctx, kind) {
  const words = WORDS[kind];
  const items = (await api.get('/customers', { kind })).map((c) => ({ ...c, balance: toCents(c.outstandingBalance) }));
  let query = '';
  let sort = 'Récents';
  let overdueOnly = false;

  const total = h('p', { class: 'total' });
  const results = h('ul', { class: 'cards', 'aria-live': 'polite' });
  const search = h('input', { type: 'search', 'aria-label': `Rechercher un ${words.one}`, placeholder: `Rechercher un ${words.one}`, autocomplete: 'off' });
  const overdueBox = kind === 'CLIENT' ? checkbox({ name: 'overdue', label: 'En retard seulement' }) : null;

  function paint() {
    const needle = fold(query);
    const shown = items
      .filter((c) => !needle || fold(c.name).includes(needle) || c.phone.replace(/\D/g, '').includes(needle.replace(/\D/g, '') || '\u0000'))
      .filter((c) => !overdueOnly || c.hasOverdueDebt)
      .sort(SORTS[sort]);
    total.replaceChildren(h('span', {}, words.owed, ' : '), h('strong', {}, formatMoney(items.reduce((s, c) => s + c.balance, 0))));
    results.replaceChildren(...shown.map((c) => h('li', {},
      h('a', { class: 'card row-card', href: `#/contacts/${encodeURIComponent(c.id)}` },
        avatar(c.name),
        h('span', { class: 'grow' }, h('strong', {}, c.name), h('br'), h('small', {}, c.phone)),
        h('span', { class: 'amount' },
          h('strong', {}, formatMoney(c.balance)),
          c.hasOverdueDebt ? h('small', { class: 'overdue' }, '⚠ En retard') : c.creditLimitExceeded ? h('small', { class: 'overdue' }, '⚠ Plafond dépassé') : null)))));
  }
  search.addEventListener('input', () => { query = search.value; paint(); });
  overdueBox?.input.addEventListener('change', () => { overdueOnly = overdueBox.input.checked; paint(); });

  const sortChips = chips({ options: Object.keys(SORTS), selected: sort, label: 'Trier par', onChange: (s) => { sort = s; paint(); } });
  paint();
  return h('section', {},
    pageTitle(words.plural, h('a', { class: 'btn primary', href: `${words.route}/nouveau` }, words.add)),
    items.length === 0
      ? emptyState({ title: words.none, message: words.hint })
      : [total, h('div', { class: 'toolbar' }, search, sortChips.el, overdueBox?.el ?? null), results]);
}

export async function form(ctx, { kind, editId }) {
  const existing = editId ? await api.get(`/customers/${encodeURIComponent(editId)}`) : null;
  const k = existing?.kind ?? kind;
  const words = WORDS[k];
  const id = crypto.randomUUID();
  ctx.setTab(words.route);

  const name = field({ label: 'Nom', name: 'name', value: existing?.name ?? '', autocomplete: 'off', required: true, maxlength: 100 });
  const phone = field({ label: 'Téléphone', name: 'phone', type: 'tel', value: existing?.phone ?? '', inputmode: 'tel', autocomplete: 'off', required: true, hint: k === 'CLIENT' ? 'Nécessaire pour les relances par SMS.' : null });
  const limit = k === 'CLIENT'
    ? field({ label: 'Plafond de crédit (FCFA, facultatif)', name: 'limit', value: existing?.creditLimit != null ? moneyInput(toCents(existing.creditLimit)) : '', inputmode: 'decimal', hint: 'Vous êtes alerté au-delà de ce montant, sans blocage de la saisie.' })
    : null;
  const optOut = k === 'CLIENT'
    ? checkbox({ name: 'optout', checked: existing?.reminderOptOut ?? false, label: 'Cette personne refuse les relances', hint: 'Cochez si elle vous a demandé de ne plus la contacter : plus aucune relance ne lui sera envoyée.' })
    : null;

  const fields = [
    { field: name, validate: validate.name },
    { field: phone, validate: validate.customerPhone },
    ...(limit ? [{ field: limit, validate: validate.optionalAmount }] : []),
  ];
  const node = buildForm({
    fields,
    extra: optOut ? [optOut.el] : [],
    submitLabel: existing ? 'Enregistrer' : words.add,
    onSubmit: async () => {
      const cents = limit ? parseAmount(limit.input.value) : null;
      const body = {
        name: name.input.value.trim(),
        phone: phone.input.value.trim(),
        ...(k === 'CLIENT' ? { creditLimit: cents === null ? (existing ? null : undefined) : fromCents(cents), reminderOptOut: optOut.input.checked } : {}),
      };
      const saved = existing
        ? await api.patch(`/customers/${encodeURIComponent(existing.id)}`, body)
        : await api.post('/customers', { id, kind: k, ...body });
      toast(existing ? 'Modifications enregistrées.' : `${words.one[0].toUpperCase()}${words.one.slice(1)} ajouté.`);
      navigate(`/contacts/${encodeURIComponent(saved.id)}`);
    },
  });
  return h('section', {},
    pageTitle(existing ? `Modifier ${existing.name}` : words.add),
    node,
    h('p', {}, h('a', { href: existing ? `#/contacts/${encodeURIComponent(existing.id)}` : words.route }, 'Annuler')));
}

export async function detail(ctx) {
  const party = await api.get(`/customers/${encodeURIComponent(ctx.params[0])}`);
  const words = WORDS[party.kind];
  ctx.setTab(words.route);
  const debts = party.debts.map((d) => debtView(d));
  const balance = partyBalance(debts);
  const limit = party.creditLimit == null ? null : toCents(party.creditLimit);
  const id = encodeURIComponent(party.id);

  const exportData = async () => {
    const data = await api.get(`/auth/export/customers/${id}`);
    saveBlob(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }), `carne-${party.kind === 'CLIENT' ? 'client' : 'fournisseur'}.json`);
    toast('Fichier enregistré sur votre appareil.');
  };
  const remove = async () => {
    const ok = await confirmDialog({
      title: `Supprimer ${party.name} ?`,
      message: `Toutes ses ardoises et tous ses remboursements seront définitivement supprimés. Cette action est irréversible.`,
      confirmLabel: 'Supprimer', destructive: true,
    });
    if (!ok) return;
    await api.delete(`/customers/${id}`);
    toast('Supprimé.');
    navigate(words.route.slice(1));
  };
  const guard = (fn) => async (event) => {
    try { await fn(); } catch (e) { toast(e.message); }
    event.target.blur?.();
  };

  const sorted = [...debts].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  return h('section', {},
    h('p', {}, h('a', { href: words.route }, `← ${words.plural}`)),
    h('div', { class: 'party-head' },
      avatar(party.name),
      h('div', {}, h('h1', {}, party.name), h('p', {}, h('a', { href: `tel:${party.phone.replace(/[^\d+]/g, '')}` }, party.phone)))),
    h('div', { class: 'balance card' },
      h('span', {}, party.kind === 'CLIENT' ? 'Il vous doit' : 'Vous lui devez'),
      h('strong', { class: 'big' }, formatMoney(balance)),
      limit !== null ? h('small', { class: balance > limit ? 'overdue' : '' }, balance > limit ? `⚠ Plafond de ${formatMoney(limit)} dépassé` : `Plafond : ${formatMoney(limit)}`) : null,
      party.reminderOptOut ? h('small', {}, 'Cette personne refuse les relances.') : null),
    h('div', { class: 'row wrap' },
      h('a', { class: 'btn primary', href: `#/contacts/${id}/dette` }, words.newDebt),
      h('a', { class: 'btn ghost', href: `#/contacts/${id}/modifier` }, 'Modifier')),
    h('h2', {}, 'Historique'),
    sorted.length === 0
      ? emptyState({ title: 'Aucune opération', message: party.kind === 'CLIENT' ? 'Notez la première ardoise de ce client.' : 'Notez le premier achat à crédit chez ce fournisseur.' })
      : h('ul', { class: 'cards' }, sorted.map((d) => h('li', {},
        h('a', { class: 'card row-card', href: `#/dettes/${encodeURIComponent(d.id)}` },
          h('span', { class: 'grow' },
            h('strong', {}, d.reason || d.category || 'Ardoise'), h('br'),
            h('small', {}, `${formatDate(d.createdAt)}${d.dueDate ? ` · échéance ${formatDate(d.dueDate)}` : ''}`)),
          h('span', { class: 'amount' }, h('strong', {}, formatMoney(d.outstanding)), h('small', {}, `sur ${formatMoney(d.amount)}`), statusBadge(d)))))),
    h('h2', {}, 'Données de cette personne'),
    h('p', { class: 'hint' }, "Si cette personne demande à voir ce que vous avez enregistré sur elle, vous pouvez en télécharger une copie."),
    h('div', { class: 'row wrap' },
      h('button', { type: 'button', class: 'btn ghost', onclick: guard(exportData) }, 'Télécharger ses données'),
      h('button', { type: 'button', class: 'btn danger-ghost', onclick: guard(remove) }, 'Supprimer')));
}

