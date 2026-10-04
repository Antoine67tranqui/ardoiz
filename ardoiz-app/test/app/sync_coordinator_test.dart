import 'dart:async';

import 'package:ardoiz/app/connectivity.dart';
import 'package:ardoiz/app/sync_coordinator.dart';
import 'package:ardoiz/data/local/app_database.dart';
import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/repositories/ledger_repository.dart';
import 'package:ardoiz/data/sync/sync_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/harness.dart';

class FakeConnectivity implements ConnectivityService {
  FakeConnectivity({this.online = true});

  bool online;
  final StreamController<bool> controller = StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => online;

  @override
  Stream<bool> get onChanged => controller.stream;

  void change(bool value) {
    online = value;
    controller.add(value);
  }
}

void main() {
  late FakeBackend backend;
  late AppDatabase db;
  late LedgerRepository repo;
  late FakeConnectivity connectivity;
  late int unauthorizedCount;
  late SyncCoordinator coordinator;
  late DateTime Function() now;

  /// Monte le coordinateur sur l'horloge simulée de [async].
  void build(FakeAsync async, {bool online = true}) {
    now = () => async.getClock(DateTime.utc(2026, 10, 4, 12)).now();
    backend = FakeBackend()..now = now;
    db = AppDatabase.openInMemory(hexKey: testKey);
    repo = LedgerRepository(db: db, clock: now);
    connectivity = FakeConnectivity(online: online);
    unauthorizedCount = 0;
    coordinator = SyncCoordinator(
      engine: SyncEngine(db: db, transport: backend, clock: now),
      db: db,
      connectivity: connectivity,
      onUnauthorized: () => unauthorizedCount++,
      clock: now,
    );
  }

  void tearDownAll_(FakeAsync async) {
    coordinator.dispose();
    db.close();
  }

  const phone = '+229 01 67 07 70 27';

  test('au démarrage en ligne : synchronise tout de suite et expose la date', () {
    fakeAsync((async) {
      build(async);
      repo.addCustomer(name: 'Aicha', phone: phone);

      unawaited(coordinator.start());
      async.flushMicrotasks();

      expect(backend.customers, hasLength(1));
      expect(coordinator.state.pending, 0);
      expect(coordinator.state.lastSyncAt, isNotNull);
      expect(coordinator.state.syncing, isFalse);
      tearDownAll_(async);
    });
  });

  test('démarrage hors ligne : rien n\'est tenté ; au retour du réseau la synchronisation part seule', () {
    fakeAsync((async) {
      build(async, online: false);
      repo.addCustomer(name: 'Aicha', phone: phone);

      unawaited(coordinator.start());
      async.flushMicrotasks();
      expect(backend.calls, 0);
      expect(coordinator.state.online, isFalse);
      expect(coordinator.state.pending, 1);

      connectivity.change(true);
      async.flushMicrotasks();

      expect(backend.customers, hasLength(1));
      expect(coordinator.state.online, isTrue);
      expect(coordinator.state.pending, 0);
      tearDownAll_(async);
    });
  });

  test('une saisie locale est envoyée après un court délai ; plusieurs saisies rapprochées = une seule passe', () {
    fakeAsync((async) {
      build(async);
      unawaited(coordinator.start());
      async.flushMicrotasks();
      final callsAfterStart = backend.calls;

      repo.addCustomer(name: 'Aicha', phone: phone);
      async.elapse(const Duration(milliseconds: 500));
      repo.addCustomer(name: 'Bako', phone: phone);
      expect(backend.customers, isEmpty); // pas encore : délai de regroupement

      async.elapse(const Duration(seconds: 3));

      expect(backend.customers, hasLength(2));
      // 2 créations + 1 lecture du serveur : une seule passe.
      expect(backend.calls - callsAfterStart, 3);
      tearDownAll_(async);
    });
  });

  test('la synchronisation ne se redéclenche pas elle-même : ses écritures (pull) ne relancent rien', () {
    fakeAsync((async) {
      build(async);
      unawaited(coordinator.start());
      async.flushMicrotasks();
      backend.seedCustomer(remoteCustomer('c-remote'));
      unawaited(coordinator.syncNow());
      async.flushMicrotasks();
      final calls = backend.calls;

      async.elapse(const Duration(seconds: 10)); // moins que la période de 60 s

      expect(backend.calls, calls); // aucune boucle
      expect(db.read((d) => d.select('SELECT count(*) c FROM customers').first['c']), 1);
      tearDownAll_(async);
    });
  });

  test('une saisie faite PENDANT une synchronisation part dans la foulée', () {
    fakeAsync((async) {
      build(async);
      unawaited(coordinator.start());
      async.flushMicrotasks();

      repo.addCustomer(name: 'Premier', phone: phone);
      unawaited(coordinator.syncNow());
      repo.addCustomer(name: 'Pendant la synchro', phone: phone); // la passe est en cours (non terminée)
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));

      expect(backend.customers, hasLength(2));
      expect(coordinator.state.pending, 0);
      tearDownAll_(async);
    });
  });

  test('échec réseau : passe en hors ligne, reprend à l\'échéance sans intervention, puis revient en ligne', () {
    fakeAsync((async) {
      build(async);
      backend.downWith = const NetworkException();
      repo.addCustomer(name: 'Aicha', phone: phone);

      unawaited(coordinator.start());
      async.flushMicrotasks();
      expect(coordinator.state.online, isFalse);
      expect(coordinator.state.lastStop, SyncStop.network);
      expect(coordinator.state.pending, 1);

      backend.downWith = null;
      async.elapse(const Duration(seconds: 6)); // 5 s de délai de reprise

      expect(backend.customers, hasLength(1));
      expect(coordinator.state.online, isTrue);
      expect(coordinator.state.pending, 0);
      tearDownAll_(async);
    });
  });

  test('session refusée : prévient l\'application et ne réessaie pas en boucle', () {
    fakeAsync((async) {
      build(async);
      backend.downWith = const UnauthorizedException();
      repo.addCustomer(name: 'Aicha', phone: phone);

      unawaited(coordinator.start());
      async.flushMicrotasks();
      final calls = backend.calls;
      async.elapse(const Duration(seconds: 30));

      expect(unauthorizedCount, 1);
      expect(backend.calls, calls);
      expect(coordinator.state.pending, 1); // la saisie est conservée
      tearDownAll_(async);
    });
  });

  test('périodique : récupère ce qui a changé ailleurs même sans saisie locale', () {
    fakeAsync((async) {
      build(async);
      unawaited(coordinator.start());
      async.flushMicrotasks();

      backend.seedCustomer(remoteCustomer('c-remote'));
      async.elapse(const Duration(seconds: 61));

      expect(db.read((d) => d.select('SELECT count(*) c FROM customers').first['c']), 1);
      tearDownAll_(async);
    });
  });

  test('un refus du serveur est signalé (compteur) sans bloquer le reste', () {
    fakeAsync((async) {
      build(async);
      backend.freePlanCustomerLimit = 0;
      repo.addCustomer(name: 'Trop', phone: phone);

      unawaited(coordinator.start());
      async.flushMicrotasks();

      expect(coordinator.state.blocked, 1);
      expect(coordinator.state.pending, 0);
      tearDownAll_(async);
    });
  });

  test('après dispose, plus aucun déclencheur ne s\'exécute', () {
    fakeAsync((async) {
      build(async);
      unawaited(coordinator.start());
      async.flushMicrotasks();
      final calls = backend.calls;

      coordinator.dispose();
      repo.addCustomer(name: 'Aicha', phone: phone);
      connectivity.change(true);
      async.elapse(const Duration(minutes: 5));

      expect(backend.calls, calls);
      expect(async.nonPeriodicTimerCount + async.periodicTimerCount, 0);
      db.close();
    });
  });
}
