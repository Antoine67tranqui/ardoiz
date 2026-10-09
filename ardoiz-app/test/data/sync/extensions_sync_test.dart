import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/repositories/ledger_repository.dart';
import 'package:ardoiz/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_backend.dart';
import '../../support/harness.dart';

const String phoneNumber = '+229 01 67 07 70 27';

void main() {
  late FakeBackend backend;
  late Device phone;

  setUp(() {
    backend = FakeBackend();
    phone = Device(backend);
  });
  tearDown(() => phone.dispose());

  group('fournisseurs et opposition aux relances', () {
    test('un fournisseur est créé comme un client, avec son type, et revient identique après synchronisation', () async {
      final supplier = phone.repo.addCustomer(name: 'Grossiste Dossou', phone: phoneNumber, kind: PartyKind.supplier);
      expect(phone.repo.customer(supplier.id)!.customer.isSupplier, isTrue);

      await phone.sync();

      expect(backend.customers[supplier.id]!.kind, PartyKind.supplier);
      expect(phone.ledger.customer(supplier.id)!.kind, PartyKind.supplier);
    });

    test('la dette d\'un fournisseur se rembourse et se synchronise comme les autres', () async {
      final supplier = phone.repo.addCustomer(name: 'Grossiste', phone: phoneNumber, kind: PartyKind.supplier);
      final debt = phone.repo.addDebt(customerId: supplier.id, amount: fcfa(10000), reason: 'Sacs de riz');
      phone.repo.addPayment(debtId: debt.id, amount: fcfa(4000));

      await phone.sync();

      expect(phone.repo.customer(supplier.id)!.outstanding, fcfa(6000));
      expect(backend.payments.values.single.amount, fcfa(4000));
    });

    test('l\'opposition aux relances part avec la création et avec les modifications', () async {
      final client = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber, reminderOptOut: true);
      await phone.sync();
      expect(backend.customers[client.id]!.reminderOptOut, isTrue);

      phone.repo.updateCustomer(client.id, reminderOptOut: false);
      await phone.sync();
      expect(backend.customers[client.id]!.reminderOptOut, isFalse);
      expect(phone.ledger.customer(client.id)!.reminderOptOut, isFalse);
    });

    test('le plan gratuit refuse le 16e fournisseur avec un message propre aux fournisseurs, sans toucher aux clients', () async {
      for (var i = 0; i < 15; i++) {
        phone.repo.addCustomer(name: 'Fournisseur $i', phone: phoneNumber, kind: PartyKind.supplier);
      }
      phone.repo.addCustomer(name: 'Un client', phone: phoneNumber);
      final sixteenth = phone.repo.addCustomer(name: 'Fournisseur 16', phone: phoneNumber, kind: PartyKind.supplier);

      final report = await phone.sync();

      expect(report.newlyBlocked, 1);
      final issue = phone.repo.issues().single;
      expect(issue.entry.entityId, sixteenth.id);
      expect(issue.reason, contains('15 fournisseurs'));
      expect(backend.customers.values.where((c) => c.kind == PartyKind.client), hasLength(1));
    });

    test('un ancien envoi en file (avant l\'arrivée des fournisseurs, sans « kind ») part comme un client', () async {
      final client = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      // Simule une file écrite par une version précédente de l'application.
      phone.db.write((d) => d.execute("UPDATE outbox SET payload = json_remove(payload, '\$.kind', '\$.reminderOptOut')"));

      await phone.sync();

      expect(backend.customers[client.id]!.kind, PartyKind.client);
    });
  });

  group('journal de caisse', () {
    test('vente et dépense : écriture locale immédiate, envoi idempotent, aucun doublon après deux synchronisations', () async {
      final sale = phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(1500), label: 'Riz', category: 'Alimentation');
      final expense = phone.repo.addCashEntry(type: CashType.expense, amount: fcfa(500), category: 'Transport');
      expect(phone.repo.cashEntries(), hasLength(2));
      expect(phone.outbox.count(), 2);

      await phone.sync();
      await phone.sync();

      expect(backend.cashEntries.keys, unorderedEquals(<String>[sale.id, expense.id]));
      expect(phone.repo.cashEntries(), hasLength(2));
      expect(phone.outbox.count(), 0);
      expect(backend.cashEntries[sale.id]!.label, 'Riz');
    });

    test('réponse perdue après traitement : le renvoi ne duplique pas l\'écriture', () async {
      phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(100));
      backend.loseNextResponse = true;

      final first = await phone.sync();
      expect(first.stop.name, 'network');
      await phone.sync(); // renvoi
      phone.advance(const Duration(minutes: 10));
      await phone.sync();

      expect(backend.cashEntries, hasLength(1));
      expect(phone.repo.cashEntries(), hasLength(1));
    });

    test('modification (montant, libellé effacé) et suppression partent et s\'alignent', () async {
      final entry = phone.repo.addCashEntry(type: CashType.expense, amount: fcfa(500), label: 'Taxi', category: 'Transport');
      await phone.sync();

      phone.repo.updateCashEntry(entry.id, amount: fcfa(700), clearLabel: true);
      await phone.sync();
      expect(backend.cashEntries[entry.id]!.amount, fcfa(700));
      expect(backend.cashEntries[entry.id]!.label, isNull);

      phone.repo.deleteCashEntry(entry.id);
      await phone.sync();
      expect(backend.cashEntries, isEmpty);
      expect(phone.repo.cashEntries(), isEmpty);
    });

    test('une écriture créée puis supprimée avant tout envoi n\'atteint jamais le serveur', () async {
      final entry = phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(100));
      phone.repo.deleteCashEntry(entry.id);

      await phone.sync();

      expect(backend.cashEntries, isEmpty);
      expect(backend.log.where((l) => l.startsWith('cashEntry')), isEmpty);
    });

    test('le pull récupère les écritures d\'un autre appareil, retire celles supprimées ailleurs, et respecte les envois en attente', () async {
      final remote = CashEntry(id: 'r1', type: CashType.sale, amount: fcfa(900), category: 'Autre', occurredAt: DateTime.utc(2026, 10, 3));
      backend.seedCash(remote);
      final local = phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(100));
      await phone.sync();
      expect(phone.repo.cashEntries().map((e) => e.id), containsAll(<String>['r1', local.id]));

      backend.cashEntries.remove('r1'); // supprimée depuis un autre appareil
      final pending = phone.repo.addCashEntry(type: CashType.expense, amount: fcfa(50)); // pas encore envoyée
      backend.downWith = const NetworkException(); // l'envoi échoue, le pull aussi
      await phone.sync();
      backend.downWith = null;
      await phone.sync();

      final ids = phone.repo.cashEntries().map((e) => e.id).toSet();
      expect(ids, isNot(contains('r1')));
      expect(ids, containsAll(<String>[local.id, pending.id]));
    });

    test('modifier une écriture que le serveur n\'a plus (404) est abandonné sans erreur', () async {
      final entry = phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(100));
      await phone.sync();
      backend.cashEntries.remove(entry.id);
      phone.repo.updateCashEntry(entry.id, amount: fcfa(200));

      final report = await phone.sync();

      expect(report.newlyBlocked, 0);
      expect(phone.outbox.count(), 0);
      expect(phone.repo.cashEntries(), isEmpty, reason: 'le cache s\'aligne sur le serveur');
    });

    test('une saisie refusée apparaît dans les modifications à vérifier et « Abandonner » la retire de la caisse', () async {
      final entry = phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(100));
      phone.outbox.block(phone.outbox.all().single, 'Refusé');

      final issue = phone.repo.issues().single;
      expect(issue.title, contains('Vente de'));
      phone.repo.discardIssue(issue.entry);

      expect(phone.repo.cashEntries(), isEmpty);
      expect(phone.ledger.cashEntry(entry.id), isNull);
    });

    test('règles de saisie : montant, libellé, catégorie, dates bornées comme au serveur', () {
      expect(() => phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(0)), throwsA(isA<DomainException>()));
      expect(() => phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(1), label: 'x' * 201), throwsA(isA<DomainException>()));
      expect(() => phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(1), category: 'c' * 51), throwsA(isA<DomainException>()));

      final future = phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(1), occurredAt: phone.time.add(const Duration(days: 30)));
      expect(future.occurredAt, phone.time.toUtc(), reason: 'pas de date future (le serveur la ramènerait à aujourd\'hui)');
      final old = phone.repo.addCashEntry(type: CashType.sale, amount: fcfa(1), occurredAt: DateTime.utc(2001));
      expect(old.occurredAt, phone.time.toUtc().subtract(const Duration(days: 366)));
      final defaulted = phone.repo.addCashEntry(type: CashType.expense, amount: fcfa(1), category: '  ');
      expect(defaulted.category, fallbackDebtCategory);
    });
  });
}
