import 'package:ardoiz/core/money.dart';
import 'package:ardoiz/domain/ledger.dart';
import 'package:ardoiz/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Money fcfa(int amount) => Money.fromCents(amount * 100);

void main() {
  final now = DateTime.utc(2026, 10, 4, 12);
  final created = DateTime.utc(2026, 9, 1);

  Customer customer(String id, {Money? limit}) => Customer(
        id: id,
        name: 'Client $id',
        phone: '+229 01 67 07 70 27',
        createdAt: created,
        creditLimit: limit,
      );
  Debt debt(String id, String customerId, int amount, {DateTime? due, DateTime? at}) => Debt(
        id: id,
        customerId: customerId,
        amount: fcfa(amount),
        category: 'Autre',
        createdAt: at ?? created,
        dueDate: due,
      );
  Payment payment(String id, String debtId, int amount) => Payment(
        id: id,
        debtId: debtId,
        amount: fcfa(amount),
        method: PaymentMethod.cash,
        paidAt: created,
      );

  group('statusOf', () {
    test('PENDING, PARTIAL, PAID selon les paiements, trop-perçu compris', () {
      expect(Ledger.statusOf(fcfa(5000), Money.zero), DebtStatus.pending);
      expect(Ledger.statusOf(fcfa(5000), fcfa(1)), DebtStatus.partial);
      expect(Ledger.statusOf(fcfa(5000), fcfa(4999)), DebtStatus.partial);
      expect(Ledger.statusOf(fcfa(5000), fcfa(5000)), DebtStatus.paid);
      expect(Ledger.statusOf(fcfa(5000), fcfa(6000)), DebtStatus.paid);
    });

    test('exact au centime : 0,10 + 0,70 solde bien une dette de 0,80', () {
      const amount = Money.fromCents(80);
      final paid = Money.sum(const [Money.fromCents(10), Money.fromCents(70)]);
      expect(Ledger.statusOf(amount, paid), DebtStatus.paid);
    });
  });

  group('overdueDays', () {
    test('0 sans échéance ou échéance à venir', () {
      expect(Ledger.overdueDays(null, now), 0);
      expect(Ledger.overdueDays(now.add(const Duration(days: 1)), now), 0);
      expect(Ledger.overdueDays(now, now), 0);
    });

    test('jours entiers écoulés depuis l\'échéance', () {
      expect(Ledger.overdueDays(now.subtract(const Duration(hours: 23)), now), 0);
      expect(Ledger.overdueDays(now.subtract(const Duration(days: 1)), now), 1);
      expect(Ledger.overdueDays(now.subtract(const Duration(days: 10, hours: 5)), now), 10);
    });
  });

  group('debtView', () {
    test('calcule payé, restant, statut ; le restant ne descend jamais sous zéro', () {
      final view = Ledger.debtView(debt('d', 'c', 5000), [payment('p1', 'd', 2000), payment('p2', 'd', 4000)], now);
      expect(view.paid, fcfa(6000));
      expect(view.remaining, Money.zero);
      expect(view.status, DebtStatus.paid);
    });

    test('une dette soldée n\'est jamais en retard', () {
      final due = now.subtract(const Duration(days: 30));
      final view = Ledger.debtView(debt('d', 'c', 1000, due: due), [payment('p', 'd', 1000)], now);
      expect(view.isOverdue, isFalse);
    });

    test('en retard dès l\'échéance dépassée (1 jour minimum affiché)', () {
      final view = Ledger.debtView(debt('d', 'c', 1000, due: now.subtract(const Duration(hours: 2))), const [], now);
      expect(view.isOverdue, isTrue);
      expect(view.overdueDays, 1);
      final older = Ledger.debtView(debt('d', 'c', 1000, due: now.subtract(const Duration(days: 12))), const [], now);
      expect(older.overdueDays, 12);
    });
  });

  group('customerViews', () {
    test('un client qui a remboursé 4000 sur 5000 doit 1000, pas 5000', () {
      final views = Ledger.customerViews(
        customers: [customer('c')],
        debts: [debt('d', 'c', 5000)],
        payments: [payment('p', 'd', 4000)],
        pendingIds: const {},
        now: now,
      );
      expect(views.single.outstanding, fcfa(1000));
      expect(views.single.isUpToDate, isFalse);
    });

    test('somme le restant de plusieurs dettes, ignore les soldées, trie les dettes par date', () {
      final views = Ledger.customerViews(
        customers: [customer('c')],
        debts: [
          debt('old', 'c', 1000, at: DateTime.utc(2026, 8)),
          debt('new', 'c', 2000, at: DateTime.utc(2026, 9, 20)),
          debt('paid', 'c', 9999),
        ],
        payments: [payment('p1', 'paid', 9999), payment('p2', 'old', 400)],
        pendingIds: const {},
        now: now,
      );
      final view = views.single;
      expect(view.outstanding, fcfa(2600)); // 600 + 2000
      expect(view.debts.map((d) => d.debt.id), ['new', 'paid', 'old']);
    });

    test('client à jour : aucune dette, ou toutes soldées', () {
      final views = Ledger.customerViews(
        customers: [customer('a'), customer('b')],
        debts: [debt('d', 'b', 100)],
        payments: [payment('p', 'd', 100)],
        pendingIds: const {},
        now: now,
      );
      expect(views.every((v) => v.isUpToDate), isTrue);
    });

    test('plafond de crédit : dépassé seulement au-delà (strictement), net des paiements', () {
      List<CustomerView> run(int paid) => Ledger.customerViews(
            customers: [customer('c', limit: fcfa(2000))],
            debts: [debt('d', 'c', 3000)],
            payments: [if (paid > 0) payment('p', 'd', paid)],
            pendingIds: const {},
            now: now,
          );
      expect(run(0).single.creditLimitExceeded, isTrue); // 3000 > 2000
      expect(run(1000).single.creditLimitExceeded, isFalse); // 2000 = plafond
      expect(run(1500).single.creditLimitExceeded, isFalse);
    });

    test('retard maximal et indicateur de retard du client', () {
      final views = Ledger.customerViews(
        customers: [customer('c')],
        debts: [
          debt('a', 'c', 100, due: now.subtract(const Duration(days: 3))),
          debt('b', 'c', 100, due: now.subtract(const Duration(days: 9))),
          debt('c', 'c', 100, due: now.add(const Duration(days: 9))),
        ],
        payments: const [],
        pendingIds: const {},
        now: now,
      );
      expect(views.single.maxOverdueDays, 9);
      expect(views.single.hasOverdue, isTrue);
    });

    test('envoi en attente : signalé sur le client, la dette ou l\'un de ses paiements', () {
      List<CustomerView> run(Set<String> pending) => Ledger.customerViews(
            customers: [customer('c')],
            debts: [debt('d', 'c', 100)],
            payments: [payment('p', 'd', 10)],
            pendingIds: pending,
            now: now,
          );
      expect(run(const {}).single.pendingSync, isFalse);
      expect(run(const {'c'}).single.pendingSync, isTrue);
      expect(run(const {'d'}).single.debts.single.pendingSync, isTrue);
      expect(run(const {'p'}).single.debts.single.pendingSync, isTrue);
      expect(run(const {'p'}).single.pendingSync, isTrue);
    });
  });
}
