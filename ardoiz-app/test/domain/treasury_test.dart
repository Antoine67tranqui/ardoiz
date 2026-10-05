import 'package:ardoiz/core/money.dart';
import 'package:ardoiz/domain/ledger.dart';
import 'package:ardoiz/domain/models.dart';
import 'package:ardoiz/domain/treasury.dart';
import 'package:flutter_test/flutter_test.dart';

Money fcfa(int v) => Money.fromCents(v * 100);

void main() {
  final from = DateTime.utc(2026, 10, 1);
  final to = DateTime.utc(2026, 11, 1);
  final now = DateTime.utc(2026, 10, 15, 12);

  CustomerView party(
    String id,
    PartyKind kind,
    List<(int amount, DateTime created, List<(int, DateTime)> payments)> debts,
  ) {
    var seq = 0;
    final customer = Customer(id: id, name: id, phone: '+22901', createdAt: now, kind: kind);
    final ds = <Debt>[];
    final ps = <Payment>[];
    for (final (amount, created, payments) in debts) {
      final d = Debt(id: '$id-d${seq++}', customerId: id, amount: fcfa(amount), category: 'Autre', createdAt: created);
      ds.add(d);
      for (final (i, p) in payments.indexed) {
        ps.add(Payment(id: '${d.id}-p$i', debtId: d.id, amount: fcfa(p.$1), method: PaymentMethod.cash, paidAt: p.$2));
      }
    }
    return Ledger.customerViews(customers: [customer], debts: ds, payments: ps, pendingIds: const <String>{}, now: now).single;
  }

  CashEntry entry(CashType type, int amount, {String category = 'Autre', DateTime? at, String id = 'e'}) =>
      CashEntry(id: id + amount.toString() + category, type: type, amount: fcfa(amount), category: category, occurredAt: at ?? DateTime.utc(2026, 10, 5));

  TreasurySummary compute(List<CustomerView> customers, List<CashEntry> cash) =>
      TreasuryCalculator.compute(customers: customers, cashEntries: cash, from: from, to: to);

  test('période vide : tout à zéro', () {
    final s = compute(const <CustomerView>[], const <CashEntry>[]);
    expect(s.net, Money.zero);
    expect(s.isEmpty, isTrue);
    expect(s.expensesByCategory, isEmpty);
  });

  test('entrées = ventes + remboursements reçus ; sorties = dépenses + paiements aux fournisseurs', () {
    final s = compute(
      <CustomerView>[
        party('aicha', PartyKind.client, [(5000, DateTime.utc(2026, 10, 2), [(2000, DateTime.utc(2026, 10, 9))])]),
        party('grossiste', PartyKind.supplier, [(9000, DateTime.utc(2026, 10, 3), [(3000, DateTime.utc(2026, 10, 10))])]),
      ],
      <CashEntry>[entry(CashType.sale, 10000), entry(CashType.expense, 1500, category: 'Transport'), entry(CashType.expense, 500, category: 'Loyer')],
    );
    expect(s.sales, fcfa(10000));
    expect(s.collected, fcfa(2000));
    expect(s.cashIn, fcfa(12000));
    expect(s.expenses, fcfa(2000));
    expect(s.paidToSuppliers, fcfa(3000));
    expect(s.cashOut, fcfa(5000));
    expect(s.net, fcfa(7000));
    expect(s.creditGranted, fcfa(5000), reason: 'une dette accordée n\'est pas un encaissement');
    expect(s.creditReceived, fcfa(9000), reason: 'un achat à crédit n\'est pas une sortie de caisse');
    expect(s.expensesByCategory.map((c) => (c.category, c.total)), [('Transport', fcfa(1500)), ('Loyer', fcfa(500))]);
  });

  test('seul ce qui tombe dans la période compte (bornes : début inclus, fin exclue)', () {
    final s = compute(
      <CustomerView>[
        party('a', PartyKind.client, [(1000, DateTime.utc(2026, 9, 30), [(400, from), (100, to), (50, DateTime.utc(2026, 9, 30, 23, 59))])]),
      ],
      <CashEntry>[entry(CashType.sale, 10, at: from, id: 'debut'), entry(CashType.sale, 20, at: to, id: 'fin'), entry(CashType.sale, 30, at: DateTime.utc(2026, 9, 30, 23, 59), id: 'avant')],
    );
    expect(s.sales, fcfa(10));
    expect(s.collected, fcfa(400));
    expect(s.creditGranted, Money.zero);
  });

  test('monthRange : mois civil local, y compris décembre vers janvier', () {
    final (a, b) = TreasuryCalculator.monthRange(DateTime(2026, 12, 15));
    expect(a, DateTime(2026, 12));
    expect(b, DateTime(2027, 1));
  });

  test('un trop-perçu ou une écriture sans libellé ne casse pas le calcul', () {
    final s = compute(<CustomerView>[], <CashEntry>[entry(CashType.expense, 1), entry(CashType.expense, 1, category: 'Autre', id: 'z')]);
    expect(s.expenses, fcfa(2));
  });
}
