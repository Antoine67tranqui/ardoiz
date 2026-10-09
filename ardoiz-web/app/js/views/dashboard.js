import { h } from '../dom.js';
import { api } from '../state.js';
import { ApiError } from '../api.js';
import { emptyState, pageTitle } from '../ui.js';
import { formatDate, formatMoney, monthName, toCents } from '../format.js';

function bar(value, max) {
  const fill = h('span', { class: 'fill' });
  fill.style.width = `${max > 0 ? Math.max(2, Math.round((value / max) * 100)) : 0}%`;
  return h('span', { class: 'bar', 'aria-hidden': 'true' }, fill);
}

export async function view() {
  let s;
  try {
    s = await api.get('/dashboard/summary');
  } catch (error) {
    if (error instanceof ApiError && error.code === 'PREMIUM_REQUIRED') {
      return h('section', {}, pageTitle('Bilan'), emptyState({
        title: 'Le bilan est réservé à la formule Premium',
        message: 'Il montre ce qu\'on vous doit, ce que vous devez, les retards et l\'évolution mois par mois.',
        action: h('a', { class: 'btn primary', href: '#/reglages' }, 'Voir la formule Premium'),
      }));
    }
    throw error;
  }
  const money = (v) => formatMoney(toCents(v));
  const maxCategory = Math.max(0, ...s.byCategory.map((c) => c.totalOutstanding));
  const maxTrend = Math.max(0, ...s.monthlyTrend.flatMap((m) => [m.amountGranted, m.amountRecovered]));
  const kpi = (label, value, cls = '') => h('div', { class: `card kpi ${cls}` }, h('span', {}, label), h('strong', { class: 'big' }, value));

  return h('section', {},
    pageTitle('Bilan'),
    h('div', { class: 'grid2' },
      kpi('Ce qu\'on me doit', money(s.totalOutstanding)),
      kpi('Ce que je dois', money(s.totalPayable)),
      kpi('Clients avec une ardoise', `${s.customersWithDebt} sur ${s.totalCustomers}`),
      kpi('Remboursés à temps', s.recoveryRate === null ? 'Pas encore de donnée' : `${Math.round(s.recoveryRate * 100)} %`)),
    s.payableOverdue > 0 ? h('p', { class: 'overdue' }, `⚠ Dont ${money(s.payableOverdue)} à payer en retard à vos fournisseurs.`) : null,
    h('h2', {}, 'Ardoises par catégorie'),
    s.byCategory.length === 0 ? h('p', { class: 'hint' }, 'Aucune donnée.')
      : h('ul', { class: 'plain bars' }, s.byCategory.map((c) => h('li', {}, h('span', {}, `${c.category} (${c.count})`), bar(c.totalOutstanding, maxCategory), h('strong', {}, money(c.totalOutstanding))))),
    h('h2', {}, 'Six derniers mois'),
    h('table', { class: 'table' },
      h('caption', { class: 'sr' }, 'Crédit accordé et argent recouvré par mois'),
      h('thead', {}, h('tr', {}, ['Mois', 'Accordé', 'Recouvré'].map((t) => h('th', { scope: 'col' }, t)))),
      h('tbody', {}, s.monthlyTrend.map((m) => {
        const [y, mo] = m.month.split('-').map(Number);
        return h('tr', {}, h('th', { scope: 'row' }, `${monthName(mo - 1)} ${y}`), h('td', {}, bar(m.amountGranted, maxTrend), money(m.amountGranted)), h('td', {}, bar(m.amountRecovered, maxTrend), money(m.amountRecovered)));
      }))),
    h('h2', {}, 'Ardoises en retard'),
    s.overdueDebts.length === 0 ? h('p', { class: 'hint' }, 'Aucune ardoise en retard.')
      : h('ul', { class: 'cards' }, s.overdueDebts.map((d) => h('li', {}, h('a', { class: 'card row-card', href: `#/dettes/${encodeURIComponent(d.debtId)}` },
        h('span', { class: 'grow' }, h('strong', {}, d.customerName), h('br'), h('small', {}, `échéance ${formatDate(d.dueDate)} · ${d.daysOverdue} j de retard`)),
        h('strong', { class: 'overdue' }, money(d.outstanding)))))),
    s.atRiskCustomers.length > 0 ? h('div', {}, h('h2', {}, 'Clients à surveiller'),
      h('ul', { class: 'plain' }, s.atRiskCustomers.map((c) => h('li', {}, h('a', { href: `#/contacts/${encodeURIComponent(c.customerId)}` }, c.customerName), ` : ${c.overdueDebtCount} ardoise(s) en retard, ${money(c.totalOverdueAmount)}`)))) : null);
}
