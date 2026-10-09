import 'package:ardoiz/core/money.dart';
import 'package:ardoiz/domain/dashboard.dart';
import 'package:ardoiz/domain/ledger.dart';
import 'package:ardoiz/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Money fcfa(int v) => Money.fromCents(v * 100);

final DateTime now = DateTime.utc(2026, 10, 15, 12);

Customer supplierOf(String name) => Customer(id: 's-$name', name: name, phone: '+22905', createdAt: now, kind: PartyKind.supplier);

void main() {
  int seq = 0;
  Customer customer(String name) => Customer(id: 'c-$name', name: name, phone: '+22901', createdAt: now);

  /// Construit une dette (avec paiements) pour un client donné.
  (Customer, Debt, List<Payment>) entry(
    String name,
    int amount, {
    String category = 'Alimentation',
    DateTime? due,
    DateTime? created,
    List<(int, DateTime)> payments = const <(int, DateTime)>[],
  }) {
    final id = 'd${seq++}';
    final debt = Debt(
      id: id,
      customerId: 'c-$name',
      amount: fcfa(amount),
      category: category,
      dueDate: due,
      createdAt: created ?? now,
    );
    final pays = <Payment>[
      for (final (i, p) in payments.indexed)
        Payment(id: '$id-p$i', debtId: id, amount: fcfa(p.$1), method: PaymentMethod.cash, paidAt: p.$2),
    ];
    return (customer(name), debt, pays);
  }

  DashboardSummary compute(List<(Customer, Debt, List<Payment>)> entries, {List<Customer> extra = const <Customer>[]}) {
    final byCustomer = <String, Customer>{for (final c in extra) c.id: c};
    for (final e in entries) {
      byCustomer[e.$1.id] = e.$1;
    }
    final views = Ledger.customerViews(
      customers: byCustomer.values.toList(),
      debts: entries.map((e) => e.$2).toList(),
      payments: entries.expand((e) => e.$3).toList(),
      pendingIds: const <String>{},
      now: now,
    );
    return DashboardCalculator.compute(views, now);
  }

  setUp(() => seq = 0);

  test('carnet vide : tout à zéro, aucun taux de recouvrement', () {
    final s = compute(const <(Customer, Debt, List<Payment>)>[]);
    expect(s.totalOutstanding, Money.zero);
    expect(s.totalCustomers, 0);
    expect(s.recoveryRate, isNull);
    expect(s.overdue, isEmpty);
    expect(s.trend, hasLength(6));
    expect(s.trend.last.month, '2026-10');
    expect(s.trend.first.month, '2026-05');
  });

  test('total et clients avec dette : les dettes soldées ne comptent pas', () {
    final s = compute(
      <(Customer, Debt, List<Payment>)>[
        entry('A', 5000, payments: [(2000, now)]),
        entry('B', 1000, payments: [(1000, now)]),
      ],
      extra: <Customer>[customer('C')],
    );
    expect(s.totalOutstanding, fcfa(3000));
    expect(s.totalCustomers, 3);
    expect(s.customersWithDebt, 1);
  });

  test('catégories : montants dus et nombre de dettes encore dues, triées par montant', () {
    final s = compute(<(Customer, Debt, List<Payment>)>[
      entry('A', 1000, category: 'Boissons'),
      entry('B', 4000, category: 'Alimentation'),
      entry('C', 500, category: 'Alimentation', payments: [(500, now)]),
    ]);
    expect(s.byCategory.map((c) => c.category), <String>['Alimentation', 'Boissons']);
    expect(s.byCategory.first.outstanding, fcfa(4000));
    expect(s.byCategory.first.count, 1, reason: 'la dette soldée de C ne compte pas');
  });

  test('retards : jours entiers, dettes soldées exclues, tri décroissant', () {
    final s = compute(<(Customer, Debt, List<Payment>)>[
      entry('A', 1000, due: now.subtract(const Duration(days: 3, hours: 5))),
      entry('B', 1000, due: now.subtract(const Duration(days: 10))),
      entry('C', 1000, due: now.subtract(const Duration(days: 20)), payments: [(1000, now)]),
      entry('D', 1000, due: now.add(const Duration(days: 2))),
      entry('E', 1000, due: now.subtract(const Duration(hours: 5))),
    ]);
    expect(s.overdue.map((o) => (o.customerName, o.daysOverdue)), <(String, int)>[('B', 10), ('A', 3), ('E', 0)]);
  });

  test('clients à risque : par nombre de dettes en retard, puis ancienneté', () {
    final s = compute(<(Customer, Debt, List<Payment>)>[
      entry('A', 1000, due: now.subtract(const Duration(days: 30))),
      entry('B', 1000, due: now.subtract(const Duration(days: 5))),
      entry('B', 2000, due: now.subtract(const Duration(days: 8)), payments: [(500, now)]),
    ]);
    expect(s.atRisk.map((a) => a.customerName), <String>['B', 'A']);
    expect(s.atRisk.first.overdueCount, 2);
    expect(s.atRisk.first.overdueAmount, fcfa(2500));
    expect(s.atRisk.first.maxDaysOverdue, 8);
  });

  test('taux de recouvrement : payées à temps (ou sans échéance) sur dettes soldées', () {
    final due = DateTime.utc(2026, 10, 1);
    final s = compute(<(Customer, Debt, List<Payment>)>[
      entry('A', 1000, due: due, payments: [(1000, DateTime.utc(2026, 9, 30))]), // à temps
      entry('B', 1000, due: due, payments: [(1000, DateTime.utc(2026, 10, 5))]), // en retard
      entry('C', 1000, payments: [(1000, now)]), // sans échéance
      entry('D', 1000, due: due), // non soldée : ignorée
    ]);
    expect(s.recoveryRate, closeTo(2 / 3, 1e-9));
  });

  test('tendance : mois civils, crédit accordé et remboursements', () {
    final s = compute(<(Customer, Debt, List<Payment>)>[
      entry('A', 5000, created: DateTime.utc(2026, 8, 10, 12), payments: [(2000, DateTime.utc(2026, 9, 5, 12)), (1000, DateTime.utc(2026, 10, 2, 12))]),
      entry('B', 3000, created: DateTime.utc(2026, 10, 3, 12)),
      entry('C', 900, created: DateTime.utc(2025, 1, 3, 12)), // hors fenêtre de 6 mois
    ]);
    Money granted(String m) => s.trend.firstWhere((t) => t.month == m).granted;
    Money recovered(String m) => s.trend.firstWhere((t) => t.month == m).recovered;
    expect(granted('2026-08'), fcfa(5000));
    expect(granted('2026-10'), fcfa(3000));
    expect(recovered('2026-09'), fcfa(2000));
    expect(recovered('2026-10'), fcfa(1000));
    expect(s.trend.fold(Money.zero, (a, t) => a + t.granted), fcfa(8000));
  });

  test('un mois de décembre est suivi de janvier (franchissement d\'année)', () {
    final january = DateTime.utc(2027, 1, 10, 12);
    final views = <CustomerView>[];
    final s = DashboardCalculator.compute(views, january);
    expect(s.trend.map((t) => t.month), <String>['2026-08', '2026-09', '2026-10', '2026-11', '2026-12', '2027-01']);
  });

  test('un trop-perçu ne rend pas le total négatif (reste plafonné à zéro par dette)', () {
    final s = compute(<(Customer, Debt, List<Payment>)>[
      entry('A', 1000, payments: [(1500, now)]),
      entry('B', 2000),
    ]);
    expect(s.totalOutstanding, fcfa(2000));
  });
  test('les fournisseurs sont totalisés à part : ni créance, ni retard client, ni client compté', () {
    final supplier = supplierOf('Grossiste');
    final debts = <Debt>[
      Debt(id: 'f1', customerId: supplier.id, amount: fcfa(8000), category: 'Alimentation', dueDate: now.subtract(const Duration(days: 2)), createdAt: now),
      Debt(id: 'f2', customerId: supplier.id, amount: fcfa(1000), category: 'Alimentation', createdAt: now),
      Debt(id: 'f3', customerId: supplier.id, amount: fcfa(500), category: 'Alimentation', createdAt: now),
    ];
    final payments = <Payment>[
      Payment(id: 'p1', debtId: 'f2', amount: fcfa(1000), method: PaymentMethod.cash, paidAt: now), // soldée
      Payment(id: 'p2', debtId: 'f3', amount: fcfa(200), method: PaymentMethod.cash, paidAt: now),
    ];
    final client = customer('Aicha');
    final views = Ledger.customerViews(
      customers: <Customer>[supplier, client],
      debts: <Debt>[...debts, Debt(id: 'c1', customerId: client.id, amount: fcfa(300), category: 'Autre', createdAt: now)],
      payments: payments,
      pendingIds: const <String>{},
      now: now,
    );

    final s = DashboardCalculator.compute(views, now);

    expect(s.totalOutstanding, fcfa(300), reason: 'seulement ce que les clients me doivent');
    expect(s.totalCustomers, 1);
    expect(s.customersWithDebt, 1);
    expect(s.overdue, isEmpty);
    expect(s.totalPayable, fcfa(8300)); // 8000 + 300 restant sur f3
    expect(s.payableOverdue, fcfa(8000));
    expect(s.suppliersWithDebt, 1);
    expect(s.byCategory.map((c) => c.category), <String>['Autre'], reason: 'les achats fournisseurs ne comptent pas dans les catégories de créances');
  });
}
