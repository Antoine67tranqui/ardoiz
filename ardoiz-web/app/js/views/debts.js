import { h, mount } from '../dom.js';
import { api, state } from '../state.js';
import { chips, confirmDialog, emptyState, errorBanner, field, form as buildForm, pageTitle, statusBadge, toast } from '../ui.js';
import { DEBT_CATEGORIES, dateInputValue, endOfLocalDay, formatDate, formatMoney, formatTime, fromCents, moneyInput, parseAmount, toCents, validate } from '../format.js';
import { debtView } from '../model.js';
import { navigate } from '../nav.js';
import { wordsFor } from './parties.js';

const addDays = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return dateInputValue(d); };

export async function form(ctx, { partyId, debtId }) {
  const existing = debtId ? debtView(await api.get(`/debts/${encodeURIComponent(debtId)}`)) : null;
  const party = existing ? existing.customer : await api.get(`/customers/${encodeURIComponent(partyId)}`);
  const words = wordsFor(party.kind);
  ctx.setTab(words.route);
  const id = crypto.randomUUID();
  const supplier = party.kind === 'SUPPLIER';

  const amount = field({ label: 'Montant (FCFA)', name: 'amount', value: existing ? moneyInput(existing.amount) : '', inputmode: 'decimal', required: true,
    hint: existing && existing.paid > 0 ? `Au moins ${formatMoney(existing.paid)} (déjà ${supplier ? 'payé' : 'remboursé'}).` : null });
  const reason = field({ label: supplier ? 'Marchandise achetée (facultatif)' : 'Motif (facultatif)', name: 'reason', type: 'textarea', value: existing?.reason ?? '', maxlength: 500, placeholder: 'Riz, huile…' });
  let category = existing?.category ?? 'Alimentation';
  const category_ = chips({ options: DEBT_CATEGORIES, selected: DEBT_CATEGORIES.includes(category) ? category : 'Autre', label: 'Catégorie', onChange: (c) => { category = c; } });
  const due = field({ label: 'Date limite de remboursement (facultatif)', name: 'due', type: 'date', value: existing?.dueDate ? dateInputValue(existing.dueDate) : '' });
  const quick = h('div', { class: 'chips', role: 'group', 'aria-label': 'Échéances rapides' },
    [[7, 'Dans 7 jours'], [15, 'Dans 15 jours'], [30, 'Dans 30 jours']].map(([n, label]) =>
      h('button', { type: 'button', class: 'chip', onclick: () => { due.input.value = addDays(n); } }, label)),
    h('button', { type: 'button', class: 'chip', onclick: () => { due.input.value = ''; } }, 'Aucune'));

  const node = buildForm({
    fields: [
      { field: amount, validate: (v) => { const e = validate.amount(v); if (e) return e; return existing && parseAmount(v) < existing.paid ? `Le montant ne peut pas être inférieur à ${formatMoney(existing.paid)}.` : null; } },
      { field: reason, validate: validate.reason },
    ],
    extra: [category_.el, due.el, quick],
    submitLabel: existing ? 'Enregistrer' : words.newDebt,
    onSubmit: async () => {
      const dueValue = due.input.value ? endOfLocalDay(due.input.value).toISOString() : null;
      const text = reason.input.value.trim();
      if (existing) {
        await api.patch(`/debts/${encodeURIComponent(existing.id)}`, { amount: fromCents(parseAmount(amount.input.value)), reason: text || null, category, dueDate: dueValue });
        toast('Modifications enregistrées.');
        navigate(`/dettes/${encodeURIComponent(existing.id)}`);
      } else {
        const created = await api.post('/debts', { id, customerId: party.id, amount: fromCents(parseAmount(amount.input.value)), ...(text ? { reason: text } : {}), category, ...(dueValue ? { dueDate: dueValue } : {}) });
        toast('Enregistré.');
        navigate(`/dettes/${encodeURIComponent(created.id)}`);
      }
    },
  });
  return h('section', {},
    pageTitle(existing ? 'Corriger cette opération' : words.newDebt),
    h('p', { class: 'lead' }, supplier ? 'Fournisseur : ' : 'Client : ', h('strong', {}, party.name)),
    node,
    h('p', {}, h('a', { href: existing ? `#/dettes/${encodeURIComponent(existing.id)}` : `#/contacts/${encodeURIComponent(party.id)}` }, 'Annuler')));
}

export async function detail(ctx) {
  const debtId = ctx.params[0];
  const [raw, subscription] = await Promise.all([
    api.get(`/debts/${encodeURIComponent(debtId)}`),
    state.subscription ? Promise.resolve(state.subscription) : api.get('/subscription/status').catch(() => null),
  ]);
  state.subscription = subscription;
  const debt = debtView(raw);
  const party = raw.customer;
  const supplier = party.kind === 'SUPPLIER';
  const words = wordsFor(party.kind);
  ctx.setTab(words.route);
  const root = h('section', {});
  const reload = () => ctx.navigate(`/dettes/${encodeURIComponent(debtId)}`);

  const act = (fn) => async () => {
    try { await fn(); } catch (e) { toast(e.message); }
  };

  // --- Paiement ---
  let method = 'CASH';
  const methodLabels = { 'Espèces': 'CASH', 'Mobile Money': 'MOMO' };
  const payAmount = field({ label: supplier ? 'Montant payé (FCFA)' : 'Montant reçu (FCFA)', name: 'pay', value: '', inputmode: 'decimal', required: true, hint: `Reste à payer : ${formatMoney(debt.outstanding)}` });
  const methodChips = chips({ options: Object.keys(methodLabels), selected: 'Espèces', label: 'Moyen de paiement', onChange: (l) => { method = methodLabels[l]; } });
  const payId = crypto.randomUUID();
  const payForm = buildForm({
    fields: [{ field: payAmount, validate: (v) => validate.amount(v, debt.outstanding) }],
    extra: [methodChips.el, h('button', { type: 'button', class: 'btn ghost', onclick: () => { payAmount.input.value = moneyInput(debt.outstanding); } }, 'Tout solder')],
    submitLabel: supplier ? 'Enregistrer le paiement' : 'Enregistrer le remboursement',
    onSubmit: async () => {
      await api.post('/payments', { id: payId, debtId: debt.id, amount: fromCents(parseAmount(payAmount.input.value)), method });
      toast('Enregistré.');
      reload();
    },
  });

  // --- Relance et paiement Mobile Money (clients seulement) ---
  const remind = act(async () => {
    const ok = await confirmDialog({ title: 'Envoyer une relance ?', message: `Un SMS poli rappelant ${formatMoney(debt.outstanding)} sera envoyé à ${party.name}.`, confirmLabel: 'Envoyer' });
    if (!ok) return;
    const reminder = await api.post(`/debts/${encodeURIComponent(debt.id)}/reminders`, { channel: 'SMS' });
    toast(reminder?.status === 'FAILED' ? "L'envoi a échoué. Réessayez plus tard." : 'Relance envoyée.');
    reload();
  });
  const momo = act(async () => {
    const ok = await confirmDialog({ title: 'Demander un paiement Mobile Money ?', message: `${party.name} recevra une demande de ${formatMoney(debt.outstanding)} sur son téléphone.`, confirmLabel: 'Envoyer la demande' });
    if (!ok) return;
    const result = await api.post('/payments/momo-request', { debtId: debt.id });
    toast(result?.message ?? 'Demande envoyée.');
  });

  const removeDebt = act(async () => {
    const ok = await confirmDialog({ title: 'Supprimer cette opération ?', message: 'Ses remboursements seront aussi supprimés. Cette action est irréversible.', confirmLabel: 'Supprimer', destructive: true });
    if (!ok) return;
    await api.delete(`/debts/${encodeURIComponent(debt.id)}`);
    toast('Supprimé.');
    navigate(`/contacts/${encodeURIComponent(party.id)}`);
  });
  const removePayment = (p) => act(async () => {
    const ok = await confirmDialog({ title: 'Supprimer ce paiement ?', message: `${formatMoney(p.cents)} du ${formatDate(p.paidAt)} sera retiré. Le solde sera recalculé.`, confirmLabel: 'Supprimer', destructive: true });
    if (!ok) return;
    await api.delete(`/payments/${encodeURIComponent(p.id)}`);
    toast('Paiement supprimé.');
    reload();
  });

  const payments = [...debt.payments].sort((a, b) => new Date(b.paidAt) - new Date(a.paidAt));
  const canRemind = !supplier && debt.outstanding > 0 && !party.reminderOptOut;
  mount(root,
    h('p', {}, h('a', { href: `#/contacts/${encodeURIComponent(party.id)}` }, `← ${party.name}`)),
    h('h1', {}, debt.reason || debt.category || 'Ardoise'),
    h('div', { class: 'balance card' },
      h('span', {}, supplier ? 'Reste à payer' : 'Reste à recevoir'),
      h('strong', { class: 'big' }, formatMoney(debt.outstanding)),
      statusBadge(debt),
      h('small', {}, `Montant initial ${formatMoney(debt.amount)}, ${supplier ? 'déjà payé' : 'déjà remboursé'} ${formatMoney(debt.paid)}`),
      h('small', {}, `Enregistré le ${formatDate(debt.createdAt)}${debt.dueDate ? ` · échéance ${formatDate(debt.dueDate)}` : ''} · ${debt.category}`)),
    h('div', { class: 'row wrap' },
      h('a', { class: 'btn ghost', href: `#/dettes/${encodeURIComponent(debt.id)}/modifier` }, 'Corriger'),
      canRemind ? h('button', { type: 'button', class: 'btn ghost', onclick: remind }, 'Envoyer une relance') : null,
      !supplier && debt.outstanding > 0 && subscription?.paymentsAvailable ? h('button', { type: 'button', class: 'btn ghost', onclick: momo }, 'Demander un paiement Mobile Money') : null,
      h('button', { type: 'button', class: 'btn danger-ghost', onclick: removeDebt }, 'Supprimer')),
    !supplier && party.reminderOptOut ? h('p', { class: 'hint' }, 'Cette personne refuse les relances : aucun message ne peut lui être envoyé.') : null,
    debt.outstanding > 0 ? h('div', {}, h('h2', {}, supplier ? 'Enregistrer un paiement' : 'Enregistrer un remboursement'), payForm) : null,
    h('h2', {}, supplier ? 'Paiements effectués' : 'Remboursements reçus'),
    payments.length === 0
      ? emptyState({ title: 'Aucun paiement', message: 'Rien n\'a encore été enregistré sur cette opération.' })
      : h('ul', { class: 'cards' }, payments.map((p) => h('li', { class: 'card row-card' },
        h('span', { class: 'grow' }, h('strong', {}, formatMoney(p.cents)), h('br'), h('small', {}, `${formatDate(p.paidAt)} à ${formatTime(p.paidAt)} · ${p.method === 'MOMO' ? 'Mobile Money' : 'Espèces'}`)),
        h('button', { type: 'button', class: 'btn danger-ghost small', 'aria-label': `Supprimer le paiement de ${formatMoney(p.cents)}`, onclick: removePayment(p) }, 'Supprimer')))),
    (raw.reminders?.length ?? 0) > 0 ? h('div', {}, h('h2', {}, 'Relances'),
      h('ul', { class: 'plain' }, [...raw.reminders].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt)).map((r) =>
        h('li', {}, `${formatDate(r.createdAt)} · ${r.status === 'SENT' ? 'envoyée' : r.status === 'FAILED' ? 'échec' : 'en attente'}`)))) : null);
  return root;
}

