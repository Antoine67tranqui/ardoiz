import 'dart:math';

import 'package:ardoiz/data/local/app_database.dart';
import 'package:ardoiz/data/local/ledger_store.dart';
import 'package:ardoiz/data/local/outbox_store.dart';
import 'package:ardoiz/data/repositories/ledger_repository.dart';
import 'package:ardoiz/data/sync/sync_engine.dart';
import 'package:ardoiz/core/money.dart';
import 'package:ardoiz/domain/models.dart';
import 'package:uuid/uuid.dart';

import 'fake_backend.dart';

const String testKey = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

Money fcfa(int amount) => Money.fromCents(amount * 100);

/// Un « appareil » : base chiffrée, dépôt, moteur, horloge contrôlable.
class Device {
  Device(this.backend, {DateTime? start, Uuid? uuid})
      : db = AppDatabase.openInMemory(hexKey: testKey),
        time = start ?? DateTime.utc(2026, 10, 4, 12) {
    repo = LedgerRepository(db: db, clock: () => time, uuid: uuid ?? const Uuid());
    ledger = LedgerStore(db);
    outbox = OutboxStore(db);
    engine = SyncEngine(
      db: db,
      transport: backend,
      clock: () => time,
      random: _FixedRandom(),
    );
    backend.now = () => time;
  }

  final FakeBackend backend;
  final AppDatabase db;
  DateTime time;
  late final LedgerRepository repo;
  late final LedgerStore ledger;
  late final OutboxStore outbox;
  late final SyncEngine engine;

  void advance(Duration d) => time = time.add(d);

  Future<SyncReport> sync() => engine.run();

  void dispose() => db.close();
}

/// Aléa fixe (milieu de la plage de ±20 %) : délais de reprise déterministes.
class _FixedRandom implements Random {
  @override
  bool nextBool() => true;
  @override
  double nextDouble() => 0.5;
  @override
  int nextInt(int max) => max ~/ 2;
}

/// Client déjà présent sur le serveur (créé « depuis un autre appareil »).
Customer remoteCustomer(String id) => Customer(
      id: id,
      name: 'Client $id',
      phone: '+229 01 11 11 11 11',
      createdAt: DateTime.utc(2026, 9, 1),
    );
