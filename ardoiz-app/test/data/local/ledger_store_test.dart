import 'package:ardoiz/core/money.dart';
import 'package:ardoiz/data/local/app_database.dart';
import 'package:ardoiz/data/local/ledger_store.dart';
import 'package:ardoiz/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

const String key = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

void main() {
  late AppDatabase db;
  late LedgerStore store;
  final created = DateTime.utc(2026, 9, 1, 8);

  Customer customer(String id, {String name = 'Aicha', Money? limit}) =>
      Customer(id: id, name: name, phone: '+229 01 67 07 70 27', createdAt: created, creditLimit: limit);
  Debt debt(String id, String customerId, {int cents = 500000, DateTime? due}) => Debt(
        id: id,
        customerId: customerId,
        amount: Money.fromCents(cents),
        category: 'Alimentation',
        reason: 'Riz',
        createdAt: created,
        dueDate: due,
      );
  Payment payment(String id, String debtId, {int cents = 100000}) => Payment(
        id: id,
        debtId: debtId,
        amount: Money.fromCents(cents),
        method: PaymentMethod.momo,
        paidAt: created,
      );

  setUp(() {
    db = AppDatabase.openInMemory(hexKey: key);
    store = LedgerStore(db);
  });
  tearDown(() => db.close());

  test('relit à l\'identique ce qui a été écrit (montants, dates UTC, plafond)', () {
    final due = DateTime.utc(2026, 12, 25, 18, 30);
    store
      ..upsertCustomer(customer('c', limit: const Money.fromCents(1234567)))
      ..upsertDebt(debt('d', 'c', cents: 125050, due: due))
      ..upsertPayment(payment('p', 'd', cents: 25050));

    final c = store.customer('c')!;
    expect(c.name, 'Aicha');
    expect(c.creditLimit, const Money.fromCents(1234567));
    expect(c.createdAt, created);

    final d = store.debt('d')!;
    expect(d.amount, const Money.fromCents(125050));
    expect(d.dueDate, due);
    expect(d.reason, 'Riz');
    expect(d.category, 'Alimentation');

    final p = store.payment('p')!;
    expect(p.amount, const Money.fromCents(25050));
    expect(p.method, PaymentMethod.momo);
  });

  test('upsert met à jour sans supprimer les dettes du client (pas de REPLACE en cascade)', () {
    store
      ..upsertCustomer(customer('c'))
      ..upsertDebt(debt('d', 'c'))
      ..upsertPayment(payment('p', 'd'))
      ..upsertCustomer(customer('c', name: 'Nouveau nom'));

    expect(store.customer('c')!.name, 'Nouveau nom');
    expect(store.debts(), hasLength(1));
    expect(store.payments(), hasLength(1));
  });

  test('le plafond de crédit peut être effacé', () {
    store
      ..upsertCustomer(customer('c', limit: const Money.fromCents(100)))
      ..upsertCustomer(customer('c'));
    expect(store.customer('c')!.creditLimit, isNull);
  });

  test('liste les clients par nom sans tenir compte de la casse', () {
    store
      ..upsertCustomer(customer('1', name: 'bako'))
      ..upsertCustomer(customer('2', name: 'Aicha'))
      ..upsertCustomer(customer('3', name: 'Cheikh'));
    expect(store.customers().map((c) => c.name), ['Aicha', 'bako', 'Cheikh']);
  });

  test('suppressions en cascade et recherche des descendants', () {
    store
      ..upsertCustomer(customer('c'))
      ..upsertDebt(debt('d1', 'c'))
      ..upsertDebt(debt('d2', 'c'))
      ..upsertPayment(payment('p1', 'd1'))
      ..upsertPayment(payment('p2', 'd2'));

    expect(store.debtIdsOfCustomer('c'), {'d1', 'd2'});
    expect(store.paymentIdsOfCustomer('c'), {'p1', 'p2'});
    expect(store.paymentIdsOfDebt('d1'), {'p1'});

    store.deleteDebt('d1');
    expect(store.payment('p1'), isNull);
    expect(store.payment('p2'), isNotNull);

    store.deleteCustomer('c');
    expect(store.debts(), isEmpty);
    expect(store.payments(), isEmpty);
  });

  test('refuse une dette ou un paiement orphelin', () {
    expect(() => store.upsertDebt(debt('d', 'inconnu')), throwsA(anything));
    store.upsertCustomer(customer('c'));
    expect(() => store.upsertPayment(payment('p', 'inconnue')), throwsA(anything));
  });

  test('métadonnées : écriture, mise à jour, suppression', () {
    expect(store.meta('user_id'), isNull);
    store.setMeta('user_id', 'u1');
    store.setMeta('user_id', 'u2');
    expect(store.meta('user_id'), 'u2');
    store.deleteMeta('user_id');
    expect(store.meta('user_id'), isNull);
  });

  test('les écritures notifient les écrans', () {
    var notifications = 0;
    final sub = db.changes.listen((_) => notifications++);
    store.upsertCustomer(customer('c'));
    store.setMeta('a', 'b');
    expect(notifications, 2);
    sub.cancel();
  });
}
