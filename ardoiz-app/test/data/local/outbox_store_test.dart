import 'package:ardoiz/data/local/app_database.dart';
import 'package:ardoiz/data/local/outbox_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'database_directory.dart';

const String key = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

void main() {
  late AppDatabase db;
  late OutboxStore outbox;
  final now = DateTime.utc(2026, 10, 4, 12);

  void enqueue(OutboxEntity entity, String id, OutboxOp op, {Map<String, Object?> payload = const {}, Set<String> descendants = const {}}) =>
      outbox.enqueue(entity: entity, entityId: id, op: op, now: now, payload: payload, descendantIds: descendants);

  List<String> summary() => outbox.all().map((e) => '${e.entity.name}.${e.op.name}:${e.entityId}').toList();

  setUp(() {
    db = AppDatabase.openInMemory(hexKey: key);
    outbox = OutboxStore(db);
  });
  tearDown(() => db.close());

  group('compaction à l\'ajout', () {
    test('conserve l\'ordre des opérations (client avant dette avant paiement)', () {
      enqueue(OutboxEntity.customer, 'c', OutboxOp.create, payload: {'name': 'A'});
      enqueue(OutboxEntity.debt, 'd', OutboxOp.create, payload: {'customerId': 'c', 'amountCents': 100});
      enqueue(OutboxEntity.payment, 'p', OutboxOp.create, payload: {'debtId': 'd', 'amountCents': 50});
      expect(summary(), ['customer.create:c', 'debt.create:d', 'payment.create:p']);
    });

    test('une modification d\'une entité jamais envoyée est fusionnée dans sa création', () {
      enqueue(OutboxEntity.customer, 'c', OutboxOp.create, payload: {'name': 'A', 'phone': '1'});
      enqueue(OutboxEntity.customer, 'c', OutboxOp.update, payload: {'name': 'B'});
      enqueue(OutboxEntity.customer, 'c', OutboxOp.update, payload: {'creditLimitCents': 500});

      expect(summary(), ['customer.create:c']);
      expect(outbox.all().single.payload, {'name': 'B', 'phone': '1', 'creditLimitCents': 500});
    });

    test('des modifications successives d\'une entité déjà envoyée sont fusionnées (la dernière gagne)', () {
      enqueue(OutboxEntity.debt, 'd', OutboxOp.update, payload: {'reason': 'a', 'category': 'X'});
      enqueue(OutboxEntity.debt, 'd', OutboxOp.update, payload: {'reason': null});

      expect(summary(), ['debt.update:d']);
      expect(outbox.all().single.payload, {'reason': null, 'category': 'X'});
    });

    test('supprimer une entité jamais envoyée annule tout, descendants compris : rien à envoyer', () {
      enqueue(OutboxEntity.customer, 'c', OutboxOp.create);
      enqueue(OutboxEntity.debt, 'd', OutboxOp.create, payload: {'customerId': 'c'});
      enqueue(OutboxEntity.payment, 'p', OutboxOp.create, payload: {'debtId': 'd'});
      enqueue(OutboxEntity.customer, 'autre', OutboxOp.create);

      enqueue(OutboxEntity.customer, 'c', OutboxOp.delete, descendants: {'d', 'p'});

      expect(summary(), ['customer.create:autre']);
    });

    test('supprimer une entité déjà envoyée : une suppression, sans ses modifications ni ses descendants en attente', () {
      enqueue(OutboxEntity.customer, 'c', OutboxOp.update, payload: {'name': 'X'});
      enqueue(OutboxEntity.debt, 'd', OutboxOp.create, payload: {'customerId': 'c'});
      enqueue(OutboxEntity.payment, 'p', OutboxOp.create, payload: {'debtId': 'd'});

      enqueue(OutboxEntity.customer, 'c', OutboxOp.delete, descendants: {'d', 'p'});

      expect(summary(), ['customer.delete:c']);
    });

    test('supprimer un paiement jamais envoyé ne laisse aucune trace ; un paiement déjà envoyé produit une suppression', () {
      enqueue(OutboxEntity.payment, 'neuf', OutboxOp.create, payload: {'debtId': 'd'});
      enqueue(OutboxEntity.payment, 'neuf', OutboxOp.delete);
      enqueue(OutboxEntity.payment, 'ancien', OutboxOp.delete);
      expect(summary(), ['payment.delete:ancien']);
    });

    test('une opération EN COURS d\'envoi n\'est jamais modifiée ni annulée (le serveur l\'a peut-être reçue)', () {
      enqueue(OutboxEntity.customer, 'c', OutboxOp.create, payload: {'name': 'A'});
      outbox.markInFlight(outbox.all().single.seq);

      enqueue(OutboxEntity.customer, 'c', OutboxOp.update, payload: {'name': 'B'});
      expect(summary(), ['customer.create:c', 'customer.update:c']);
      expect(outbox.all().first.payload, {'name': 'A'});

      enqueue(OutboxEntity.customer, 'c', OutboxOp.delete);
      // La création a peut-être abouti : la suppression doit partir derrière elle.
      expect(summary(), ['customer.create:c', 'customer.delete:c']);
    });
  });

  group('cycle de vie d\'une opération', () {
    test('due() ne renvoie que les opérations prêtes, dans l\'ordre ; elles sont retirées une fois envoyées', () {
      enqueue(OutboxEntity.customer, 'a', OutboxOp.create);
      enqueue(OutboxEntity.customer, 'b', OutboxOp.create);
      expect(outbox.due(now).map((e) => e.entityId), ['a', 'b']);

      outbox.complete(outbox.all().first.seq);
      expect(outbox.due(now).map((e) => e.entityId), ['b']);
      expect(outbox.count(), 1);
    });

    test('un échec temporaire reporte la reprise et compte les tentatives', () {
      enqueue(OutboxEntity.customer, 'a', OutboxOp.create);
      final seq = outbox.all().single.seq;
      outbox.markInFlight(seq);

      final retryAt = now.add(const Duration(seconds: 30));
      outbox.recordFailure(seq, error: 'timeout', nextAttemptAt: retryAt);

      final entry = outbox.all().single;
      expect(entry.status, OutboxStatus.pending);
      expect(entry.attempts, 1);
      expect(entry.lastError, 'timeout');
      expect(outbox.due(now), isEmpty);
      expect(outbox.due(retryAt).single.seq, seq);
      expect(outbox.nextRetryAt(), retryAt);
    });

    test('resetInFlight reprend les envois interrompus par un arrêt de l\'app', () {
      enqueue(OutboxEntity.customer, 'a', OutboxOp.create);
      outbox.markInFlight(outbox.all().single.seq);
      expect(outbox.due(now), isEmpty);

      outbox.resetInFlight();
      expect(outbox.due(now), hasLength(1));
    });

    test('entityIds liste les entités à ne pas écraser avec les données du serveur', () {
      enqueue(OutboxEntity.customer, 'a', OutboxOp.create);
      enqueue(OutboxEntity.debt, 'd', OutboxOp.update);
      expect(outbox.entityIds(), {'a', 'd'});
    });
  });

  group('refus définitif du serveur', () {
    late OutboxEntry customerCreate;

    setUp(() {
      enqueue(OutboxEntity.customer, 'c', OutboxOp.create, payload: {'name': 'A'});
      enqueue(OutboxEntity.debt, 'd', OutboxOp.create, payload: {'customerId': 'c'});
      enqueue(OutboxEntity.payment, 'p', OutboxOp.create, payload: {'debtId': 'd'});
      enqueue(OutboxEntity.customer, 'autre', OutboxOp.create, payload: {'name': 'B'});
      customerCreate = outbox.all().first;
    });

    test('bloque l\'opération et toutes celles qui en dépendent, mais pas les autres', () {
      outbox.block(customerCreate, 'Plan gratuit limité à 15 clients');

      final statuses = {for (final e in outbox.all()) e.entityId: e.status};
      expect(statuses, {
        'c': OutboxStatus.blocked,
        'd': OutboxStatus.blocked,
        'p': OutboxStatus.blocked,
        'autre': OutboxStatus.pending,
      });
      expect(outbox.all().first.lastError, 'Plan gratuit limité à 15 clients');
      expect(outbox.due(now).map((e) => e.entityId), ['autre']);
      expect(outbox.blocked(), hasLength(3));
    });

    test('réessayer relance l\'opération et ses dépendantes', () {
      outbox.block(customerCreate, 'refus');
      outbox.retry(customerCreate);

      expect(outbox.blocked(), isEmpty);
      expect(outbox.due(now), hasLength(4));
      expect(outbox.all().first.lastError, isNull);
    });

    test('abandonner supprime l\'opération et ses dépendantes, et renvoie ce qui a été retiré', () {
      outbox.block(customerCreate, 'refus');
      final removed = outbox.discard(customerCreate);

      expect(removed.map((e) => e.entityId), ['c', 'd', 'p']);
      expect(summary(), ['customer.create:autre']);
    });

    test('un blocage au milieu de la chaîne ne touche ni l\'amont ni les autres chaînes', () {
      final debtCreate = outbox.all()[1];
      outbox.block(debtCreate, 'refus');

      final statuses = {for (final e in outbox.all()) e.entityId: e.status};
      expect(statuses['c'], OutboxStatus.pending);
      expect(statuses['d'], OutboxStatus.blocked);
      expect(statuses['p'], OutboxStatus.blocked);
      expect(statuses['autre'], OutboxStatus.pending);
    });
  });

  test('la file survit à la fermeture de l\'application (persistance)', () {
    final dir = DatabaseDirectory.create();
    final path = '${dir.path}/o.db';
    final first = AppDatabase.open(path: path, hexKey: key);
    OutboxStore(first).enqueue(
      entity: OutboxEntity.debt,
      entityId: 'd',
      op: OutboxOp.create,
      now: now,
      payload: {'amountCents': 100},
    );
    first.close();

    final second = AppDatabase.open(path: path, hexKey: key);
    expect(OutboxStore(second).all().single.payload, {'amountCents': 100});
    second.close();
    dir.dispose();
  });
}
