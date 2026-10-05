import { h, mount } from '../dom.js';
import { api } from '../state.js';
import { chips, emptyState, field, form as buildForm, pageTitle, toast } from '../ui.js';
import { EXPENSE_CATEGORIES, formatDate, formatMoney, formatTime, fromCents, parseAmount, toCents, validate } from '../format.js';
import { periodRange } from '../model.js';

const PERIODS = { "Aujourd'hui": 'today', 'Cette semaine': 'week', 'Ce mois': 'month' };

export async function view(ctx) {
  let period = 'today';
  const root = h('section', {});

  const summaryBox = h('div', {});
  const listBox = h('div', {});
  const formBox = h('div', {});

  async function load() {
    const [from, to] = periodRange(period).map((d) => d.toISOString());
    const [summary, entries] = await Promise.all([api.get('/cash/summary', { from, to }), api.get('/cash', { from, to })]);
    const row = (label, value, cls = '') => h('div', { class: `kv ${cls}` }, h('span', {}, label), h('strong', {}, formatMoney(toCents(value))));
    mount(summaryBox,
      h('div', { class: 'balance card' },
        h('span', {}, 'Solde de la période (entrées moins sorties)'),
        h('strong', { class: `big ${summary.net < 0 ? 'overdue' : ''}` }, formatMoney(toCents(summary.net))),
        h('small', {}, 'Ventes comptant et remboursements reçus, moins dépenses et paiements aux fournisseurs.')),
      h('div', { class: 'grid2' },
        h('div', { class: 'card' }, h('h2', {}, 'Entrées'), row('Ventes au comptant', summary.sales), row('Remboursements reçus', summary.collected), row('Total', summary.cashIn, 'total')),
        h('div', { class: 'card' }, h('h2', {}, 'Sorties'), row('Dépenses', summary.expenses), row('Payé aux fournisseurs', summary.paidToSuppliers), row('Total', summary.cashOut, 'total'))),
      h('p', { class: 'hint' }, `Crédit accordé sur la période : ${formatMoney(toCents(summary.creditGranted))} (ce n'est pas de l'argent encaissé). Achats à crédit : ${formatMoney(toCents(summary.creditReceived))}.`),
      summary.expensesByCategory.length > 0
        ? h('div', {}, h('h2', {}, 'Dépenses par catégorie'), h('ul', { class: 'plain' }, summary.expensesByCategory.map((c) => h('li', {}, `${c.category} : `, h('strong', {}, formatMoney(toCents(c.total)))))))
        : null);

    mount(listBox,
      h('h2', {}, 'Opérations'),
      entries.length === 0
        ? emptyState({ title: 'Aucune opération sur cette période', message: 'Notez vos ventes au comptant et vos dépenses pour connaître votre vraie trésorerie.' })
        : h('ul', { class: 'cards' }, entries.map((e) => h('li', { class: 'card row-card' },
          h('span', { class: 'grow' },
            h('strong', {}, e.label || e.category), h('br'),
            h('small', {}, `${e.type === 'SALE' ? 'Vente' : 'Dépense'} · ${formatDate(e.occurredAt)} à ${formatTime(e.occurredAt)}${e.label ? ` · ${e.category}` : ''}`)),
          h('strong', { class: e.type === 'SALE' ? 'plus' : 'minus' }, `${e.type === 'SALE' ? '+' : '-'}${formatMoney(toCents(e.amount))}`),
          h('button', { type: 'button', class: 'btn danger-ghost small', 'aria-label': 'Supprimer cette opération', onclick: async () => {
            try { await api.delete(`/cash/${encodeURIComponent(e.id)}`); toast('Supprimé.'); await load(); } catch (error) { toast(error.message); }
          } }, 'Supprimer')))));
  }

  function showForm() {
    let type = 'SALE';
    let category = 'Achat de marchandises';
    const id = crypto.randomUUID();
    const amount = field({ label: 'Montant (FCFA)', name: 'cash-amount', value: '', inputmode: 'decimal', required: true });
    const label = field({ label: 'Libellé (facultatif)', name: 'cash-label', value: '', maxlength: 200, placeholder: 'Sacs de riz' });
    const typeChips = chips({ options: ['Vente', 'Dépense'], selected: 'Vente', label: 'Nature', onChange: (v) => { type = v === 'Vente' ? 'SALE' : 'EXPENSE'; categoryChips.el.hidden = type === 'SALE'; } });
    const categoryChips = chips({ options: EXPENSE_CATEGORIES, selected: category, label: 'Catégorie de dépense', onChange: (c) => { category = c; } });
    categoryChips.el.hidden = true;
    mount(formBox, buildForm({
      fields: [{ field: amount, validate: (v) => validate.amount(v) }, { field: label, validate: validate.label }],
      extra: [typeChips.el, categoryChips.el],
      submitLabel: 'Enregistrer',
      onSubmit: async () => {
        const text = label.input.value.trim();
        await api.post('/cash', { id, type, amount: fromCents(parseAmount(amount.input.value)), ...(text ? { label: text } : {}), ...(type === 'EXPENSE' ? { category } : {}) });
        toast('Enregistré.');
        mount(formBox, h('button', { type: 'button', class: 'btn primary', onclick: showForm }, 'Noter une vente ou une dépense'));
        await load();
      },
    }));
  }

  const periodChips = chips({ options: Object.keys(PERIODS), selected: "Aujourd'hui", label: 'Période', onChange: (p) => { period = PERIODS[p]; load().catch((e) => toast(e.message)); } });
  mount(formBox, h('button', { type: 'button', class: 'btn primary', onclick: showForm }, 'Noter une vente ou une dépense'));
  await load();
  mount(root, pageTitle('Caisse'), periodChips.el, summaryBox, formBox, listBox);
  return root;
}
