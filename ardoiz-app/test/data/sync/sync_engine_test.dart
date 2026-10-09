import 'package:ardoiz/data/local/outbox_store.dart';
import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/sync/sync_engine.dart';
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

  group('envoi de la file', () {
    test('envoie dans l\'ordre client → dette → paiement, vide la file et aligne le cache', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      final debt = phone.repo.addDebt(customerId: customer.id, amount: fcfa(5000), reason: 'Riz');
      phone.repo.addPayment(debtId: debt.id, amount: fcfa(2000));

      final report = await phone.sync();

      expect(report.completed, isTrue);
      expect(report.sent, 3);
      expect(report.pulled, isTrue);
      expect(backend.log, ['customer.create:${customer.id}', 'debt.create:${debt.id}', startsWith('payment.create:')]);
      expect(phone.outbox.count(), 0);
      expect(backend.debts[debt.id]!.reason, 'Riz');
      expect(phone.repo.customer(customer.id)!.outstanding, fcfa(3000));
      expect(phone.repo.customer(customer.id)!.pendingSync, isFalse);
    });

    test('conserve les identifiants locaux : aucun doublon après synchronisation (ancien bug)', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      final debt = phone.repo.addDebt(customerId: customer.id, amount: fcfa(1000));
      phone.repo.addPayment(debtId: debt.id, amount: fcfa(400));

      await phone.sync();
      await phone.sync();

      expect(phone.ledger.customers(), hasLength(1));
      expect(phone.ledger.debts(), hasLength(1));
      expect(phone.ledger.payments(), hasLength(1));
      expect(backend.customers, hasLength(1));
      expect(backend.debts, hasLength(1));
      expect(backend.payments, hasLength(1));
      expect(phone.repo.customer(customer.id)!.outstanding, fcfa(600));
    });

    test('envoie les modifications et suppressions d\'entités déjà synchronisées', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      final debt = phone.repo.addDebt(customerId: customer.id, amount: fcfa(5000));
      final payment = phone.repo.addPayment(debtId: debt.id, amount: fcfa(1000));
      await phone.sync();

      phone.repo.updateCustomer(customer.id, name: 'Aicha T.');
      phone.repo.updateDebt(debt.id, amount: fcfa(4500), clearReason: true);
      phone.repo.deletePayment(payment.id);
      await phone.sync();

      expect(backend.customers[customer.id]!.name, 'Aicha T.');
      expect(backend.debts[debt.id]!.amount, fcfa(4500));
      expect(backend.payments, isEmpty);
    });

    test('supprimer un client déjà synchronisé : une suppression, cascade serveur, plus rien en local', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      final debt = phone.repo.addDebt(customerId: customer.id, amount: fcfa(5000));
      phone.repo.addPayment(debtId: debt.id, amount: fcfa(100));
      await phone.sync();
      backend.log.clear();

      phone.repo.deleteCustomer(customer.id);
      await phone.sync();

      expect(backend.log, ['customer.delete:${customer.id}']);
      expect(backend.customers, isEmpty);
      expect(backend.debts, isEmpty);
      expect(backend.payments, isEmpty);
      expect(phone.ledger.customers(), isEmpty);
    });

    test('un client créé puis supprimé avant tout envoi n\'atteint jamais le serveur', () async {
      final customer = phone.repo.addCustomer(name: 'Erreur de saisie', phone: phoneNumber);
      phone.repo.addDebt(customerId: customer.id, amount: fcfa(100));
      phone.repo.deleteCustomer(customer.id);

      final report = await phone.sync();

      expect(report.sent, 0);
      expect(backend.log, isEmpty);
      expect(backend.customers, isEmpty);
    });

    test('les modifications faites hors ligne avant le premier envoi partent en une seule création', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      phone.repo.updateCustomer(customer.id, name: 'Aïcha Traoré');
      phone.repo.updateCustomer(customer.id, creditLimit: fcfa(20000));

      await phone.sync();

      expect(backend.log, hasLength(1));
      expect(backend.customers[customer.id]!.name, 'Aïcha Traoré');
      expect(backend.customers[customer.id]!.creditLimit, fcfa(20000));
    });
  });

  group('échec ambigu (réponse perdue après traitement par le serveur)', () {
    test('le renvoi ne crée pas de doublon : le serveur reconnaît l\'id', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      final debt = phone.repo.addDebt(customerId: customer.id, amount: fcfa(5000));
      final payment = phone.repo.addPayment(debtId: debt.id, amount: fcfa(2000));
      await phone.sync();

      final second = phone.repo.addPayment(debtId: debt.id, amount: fcfa(1000));
      backend.loseNextResponse = true;
      final failed = await phone.sync();
      expect(failed.stop, SyncStop.network);
      expect(backend.payments, hasLength(2)); // le serveur l'a bien reçu
      expect(phone.outbox.count(), 1); // l'app, elle, ne le sait pas

      phone.advance(const Duration(minutes: 1));
      final retry = await phone.sync();

      expect(retry.completed, isTrue);
      expect(backend.payments, hasLength(2)); // pas de double crédit
      expect(backend.payments.keys, containsAll([payment.id, second.id]));
      expect(phone.repo.customer(customer.id)!.outstanding, fcfa(2000));
    });

    test('une panne au milieu de la file : tout reprend sans doublon ni perte', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      final d1 = phone.repo.addDebt(customerId: customer.id, amount: fcfa(100));
      final d2 = phone.repo.addDebt(customerId: customer.id, amount: fcfa(200));
      backend.failures[2] = const NetworkException();

      final first = await phone.sync();
      expect(first.sent, 1);
      expect(first.stop, SyncStop.network);
      expect(backend.customers, hasLength(1));
      expect(backend.debts, isEmpty);

      phone.advance(const Duration(minutes: 1));
      final second = await phone.sync();
      expect(second.completed, isTrue);
      expect(backend.debts.keys, containsAll([d1.id, d2.id]));
      expect(backend.debts, hasLength(2));
    });

    test('un envoi interrompu par l\'arrêt de l\'app (in_flight) est repris au lancement suivant', () async {
      phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      phone.outbox.markInFlight(phone.outbox.all().single.seq);

      final report = await phone.sync();

      expect(report.sent, 1);
      expect(backend.customers, hasLength(1));
    });
  });

  group('échecs temporaires : file conservée, reprise espacée', () {
    test('réseau coupé : rien n\'est perdu, la file reste en tête, reprise différée', () async {
      phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      backend.downWith = const NetworkException();

      final report = await phone.sync();

      expect(report.stop, SyncStop.network);
      expect(report.pulled, isFalse);
      expect(report.retryAt, isNotNull);
      expect(phone.outbox.count(), 1);
      expect(phone.outbox.all().single.attempts, 1);
      backend.downWith = null;
      expect((await phone.sync()).sent, 0); // pas avant l'échéance
      expect(backend.customers, isEmpty);
    });

    test('délais de reprise exponentiels (5 s, 10 s, 20 s...) plafonnés à 5 minutes', () async {
      phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      backend.downWith = const ServerException(503);
      final delays = <Duration>[];

      for (var i = 0; i < 9; i++) {
        final report = await phone.sync();
        delays.add(report.retryAt!.difference(phone.time));
        phone.time = report.retryAt!;
      }

      expect(delays.take(4), [
        const Duration(seconds: 5),
        const Duration(seconds: 10),
        const Duration(seconds: 20),
        const Duration(seconds: 40),
      ]);
      expect(delays.last, const Duration(minutes: 5));
      expect(delays.every((d) => d <= const Duration(minutes: 5)), isTrue);
    });

    test('erreur serveur 5xx : même conduite (file conservée, arrêt, reprise différée)', () async {
      phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      backend.downWith = const ServerException(500);

      final report = await phone.sync();

      expect(report.stop, SyncStop.server);
      expect(phone.outbox.count(), 1);
    });

    test('l\'ordre est préservé : un échec en tête de file empêche d\'envoyer la suite', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      phone.repo.addDebt(customerId: customer.id, amount: fcfa(100));
      backend.failures[1] = const NetworkException();

      await phone.sync();

      expect(backend.calls, 1); // la dette n'a même pas été tentée
      expect(backend.log, isEmpty);
      expect(phone.outbox.count(), 2);
    });
  });

  group('session expirée', () {
    test('s\'arrête sans rien perdre ni compter d\'échec, et le signale', () async {
      phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      backend.downWith = const UnauthorizedException();

      final report = await phone.sync();

      expect(report.stop, SyncStop.unauthorized);
      final entry = phone.outbox.all().single;
      expect(entry.status, OutboxStatus.pending);
      expect(entry.attempts, 0);

      backend.downWith = null;
      expect((await phone.sync()).sent, 1);
    });
  });

  group('refus définitif du serveur', () {
    test('plan gratuit plein : le client est bloqué avec un message clair, ses dettes aussi', () async {
      backend.freePlanCustomerLimit = 0;
      final refused = phone.repo.addCustomer(name: 'Trop', phone: phoneNumber);
      final debt = phone.repo.addDebt(customerId: refused.id, amount: fcfa(500));
      phone.repo.addPayment(debtId: debt.id, amount: fcfa(100));

      final report = await phone.sync();

      expect(report.newlyBlocked, 1);
      expect(phone.outbox.blocked(), hasLength(3));
      final issues = phone.repo.issues();
      expect(issues.first.title, 'Nouveau client « Trop »');
      expect(issues.first.reason, contains('plan gratuit'));
      expect(phone.repo.blockedCount(), 3);
      expect(phone.repo.customer(refused.id), isNotNull); // le cache n'efface rien
    });

    test('un refus ne bloque pas les autres opérations indépendantes', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      final debt = phone.repo.addDebt(customerId: customer.id, amount: fcfa(1000));
      await phone.sync();

      // Un autre appareil a déjà encaissé 800 : mon paiement de 500 dépassera le solde.
      backend.seedPayment(Payment(id: 'autre', debtId: debt.id, amount: fcfa(800), method: PaymentMethod.cash, paidAt: phone.time));
      phone.repo.addPayment(debtId: debt.id, amount: fcfa(500));
      final other = phone.repo.addCustomer(name: 'Bako', phone: phoneNumber);

      final report = await phone.sync();

      expect(report.newlyBlocked, 1);
      expect(backend.customers.keys, contains(other.id));
      expect(phone.repo.issues().single.reason, contains('dépasse le solde'));
    });

    test('Réessayer relance l\'opération ; Abandonner annule ses effets locaux', () async {
      backend.freePlanCustomerLimit = 0;
      final refused = phone.repo.addCustomer(name: 'Trop', phone: phoneNumber);
      await phone.sync();
      final issue = phone.repo.issues().single;

      backend.freePlanCustomerLimit = 15;
      phone.repo.retryIssue(issue.entry);
      expect((await phone.sync()).sent, 1);
      expect(backend.customers.keys, contains(refused.id));

      backend.freePlanCustomerLimit = 1;
      final second = phone.repo.addCustomer(name: 'Encore trop', phone: phoneNumber);
      await phone.sync();
      phone.repo.discardIssue(phone.repo.issues().single.entry);

      expect(phone.repo.customer(second.id), isNull);
      expect(phone.outbox.count(), 0);
      expect(backend.customers.keys, isNot(contains(second.id)));
    });

    test('abandonner une modification refusée rétablit la version du serveur à la synchronisation suivante', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      final debt = phone.repo.addDebt(customerId: customer.id, amount: fcfa(1000));
      phone.repo.addPayment(debtId: debt.id, amount: fcfa(800));
      await phone.sync();

      // Un autre appareil a encaissé 150 de plus : ma correction à 900 passe sous les paiements (950).
      backend.seedPayment(Payment(id: 'autre', debtId: debt.id, amount: fcfa(150), method: PaymentMethod.cash, paidAt: phone.time));
      phone.repo.updateDebt(debt.id, amount: fcfa(900));
      await phone.sync();
      expect(phone.repo.issues().single.reason, contains('inférieur aux paiements'));
      expect(phone.repo.debt(debt.id)!.debt.amount, fcfa(900));

      phone.repo.discardIssue(phone.repo.issues().single.entry);
      await phone.sync();

      expect(phone.repo.debt(debt.id)!.debt.amount, fcfa(1000));
      expect(phone.outbox.count(), 0);
    });
  });

  group('suppression ou modification ailleurs', () {
    test('supprimer ce que le serveur a déjà supprimé (404) est un succès', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      await phone.sync();
      backend.customers.clear();

      phone.repo.deleteCustomer(customer.id);
      final report = await phone.sync();

      expect(report.sent, 1);
      expect(report.newlyBlocked, 0);
      expect(phone.outbox.count(), 0);
    });

    test('modifier ce que le serveur a déjà supprimé est abandonné sans erreur ; le cache s\'aligne', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      await phone.sync();
      backend.customers.clear();

      phone.repo.updateCustomer(customer.id, name: 'Nouveau');
      final report = await phone.sync();

      expect(report.newlyBlocked, 0);
      expect(phone.outbox.count(), 0);
      expect(phone.ledger.customers(), isEmpty);
    });

    test('créer une dette pour un client supprimé ailleurs : bloqué avec un message explicite', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      await phone.sync();
      backend.customers.clear();

      phone.repo.addDebt(customerId: customer.id, amount: fcfa(100));
      final report = await phone.sync();

      expect(report.newlyBlocked, 1);
      expect(phone.repo.issues().single.reason, contains('introuvable sur le serveur'));
    });
  });

  group('alignement du cache sur le serveur (pull)', () {
    test('récupère ce qui a été créé depuis un autre appareil (client, dette, paiement)', () async {
      final created = phone.time.subtract(const Duration(days: 2));
      backend.seedCustomer(Customer(id: 'c-remote', name: 'Chez Awa', phone: '+229 01 11 11 11 11', createdAt: created));
      backend.seedDebt(Debt(id: 'd-remote', customerId: 'c-remote', amount: fcfa(3000), category: 'Boissons', createdAt: created));
      backend.seedPayment(Payment(id: 'p-remote', debtId: 'd-remote', amount: fcfa(1000), method: PaymentMethod.momo, paidAt: created));

      await phone.sync();

      final view = phone.repo.customer('c-remote')!;
      expect(view.customer.name, 'Chez Awa');
      expect(view.outstanding, fcfa(2000));
      expect(view.debts.single.payments.single.method, PaymentMethod.momo);
    });

    test('applique les modifications faites ailleurs sur des entités sans envoi en attente', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      await phone.sync();
      backend.customers[customer.id] = backend.customers[customer.id]!.copyWith(name: 'Aicha (modifiée ailleurs)');

      await phone.sync();

      expect(phone.repo.customer(customer.id)!.customer.name, 'Aicha (modifiée ailleurs)');
    });

    test('retire ce qui a été supprimé ailleurs, dettes et paiements compris', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      final debt = phone.repo.addDebt(customerId: customer.id, amount: fcfa(500));
      phone.repo.addPayment(debtId: debt.id, amount: fcfa(100));
      await phone.sync();
      backend.customers.clear();
      backend.debts.clear();
      backend.payments.clear();

      await phone.sync();

      expect(phone.ledger.customers(), isEmpty);
      expect(phone.ledger.debts(), isEmpty);
      expect(phone.ledger.payments(), isEmpty);
    });

    test('LES MODIFICATIONS LOCALES EN ATTENTE NE SONT JAMAIS ÉCRASÉES par le serveur', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      await phone.sync();

      phone.repo.updateCustomer(customer.id, name: 'Nom local');
      backend.customers[customer.id] = backend.customers[customer.id]!.copyWith(name: 'Nom serveur');
      backend.downWith = const NetworkException();
      await phone.sync();

      expect(phone.repo.customer(customer.id)!.customer.name, 'Nom local');

      backend.downWith = null;
      phone.advance(const Duration(minutes: 1));
      await phone.sync();
      expect(backend.customers[customer.id]!.name, 'Nom local');
      expect(phone.repo.customer(customer.id)!.customer.name, 'Nom local');
    });

    test('une création locale pas encore envoyée n\'est pas supprimée par un pull (absente du serveur)', () async {
      final customer = phone.repo.addCustomer(name: 'Nouveau', phone: phoneNumber);
      final debt = phone.repo.addDebt(customerId: customer.id, amount: fcfa(100));
      phone.repo.addPayment(debtId: debt.id, amount: fcfa(10));
      backend.failures[1] = const NetworkException();
      await phone.sync(); // l'envoi échoue : reprise différée

      await phone.engine.run(); // avant l'échéance : seul le pull s'exécute

      expect(phone.ledger.customers(), hasLength(1));
      expect(phone.ledger.debts(), hasLength(1));
      expect(phone.ledger.payments(), hasLength(1));
    });

    test('un client supprimé localement (envoi en attente) ne ressuscite pas via le pull', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      phone.repo.addDebt(customerId: customer.id, amount: fcfa(100));
      await phone.sync();

      phone.repo.deleteCustomer(customer.id);
      backend.failures[backend.calls + 1] = const NetworkException(); // la suppression ne part pas
      await phone.sync();
      await phone.engine.run(); // pull seul

      expect(phone.ledger.customers(), isEmpty);
      expect(phone.ledger.debts(), isEmpty);
    });

    test('un client dont une dette est en attente n\'est pas supprimé par un pull même s\'il a disparu du serveur', () async {
      final customer = phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);
      await phone.sync();
      backend.customers.clear();
      phone.repo.addDebt(customerId: customer.id, amount: fcfa(100));

      backend.failures[backend.calls + 1] = const NetworkException();
      await phone.sync();
      await phone.engine.run();

      expect(phone.ledger.customer(customer.id), isNotNull);
      expect(phone.ledger.debts(), hasLength(1));
    });

    test('mémorise la date de dernière synchronisation réussie', () async {
      expect(phone.ledger.meta(SyncEngine.lastSyncMetaKey), isNull);
      await phone.sync();
      expect(DateTime.parse(phone.ledger.meta(SyncEngine.lastSyncMetaKey)!), phone.time);
    });
  });

  group('une seule synchronisation à la fois', () {
    test('des appels simultanés rejoignent la même passe (aucun envoi en double)', () async {
      phone.repo.addCustomer(name: 'Aicha', phone: phoneNumber);

      await Future.wait([phone.sync(), phone.sync(), phone.sync()]);

      expect(backend.log, hasLength(1));
    });
  });
}
