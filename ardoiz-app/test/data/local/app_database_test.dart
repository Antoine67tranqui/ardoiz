import 'dart:io';

import 'package:ardoiz/data/local/app_database.dart';
import 'package:ardoiz/data/local/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const String keyA = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const String keyB = '0000000000000000000000000000000000000000000000000000000000000001';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('carne_db_test');
    path = '${dir.path}/carne.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('chiffrement (SQLCipher)', () {
    test('les données ne sont jamais écrites en clair sur le disque', () {
      final db = AppDatabase.open(path: path, hexKey: keyA);
      db.write((d) {
        d.execute("INSERT INTO customers (id, name, phone, created_at) VALUES ('c1', 'MARCHAND_SECRET_XYZ', '+229 01 67 07 70 27', '2026-01-01')");
        d.execute("INSERT INTO meta (key, value) VALUES ('k', 'VALEUR_CONFIDENTIELLE_123')");
      });
      db.close();

      for (final suffix in const ['', '-wal']) {
        final file = File('$path$suffix');
        if (!file.existsSync()) continue;
        final content = String.fromCharCodes(file.readAsBytesSync());
        expect(content.contains('MARCHAND_SECRET_XYZ'), isFalse, reason: 'fichier $suffix');
        expect(content.contains('VALEUR_CONFIDENTIELLE_123'), isFalse, reason: 'fichier $suffix');
        expect(content.contains('SQLite format 3'), isFalse, reason: 'en-tête SQLite en clair dans $suffix');
      }
    });

    test('la base ne s\'ouvre pas avec une mauvaise clé, ni sans clé', () {
      AppDatabase.open(path: path, hexKey: keyA).close();

      expect(() => AppDatabase.open(path: path, hexKey: keyB), throwsA(isA<DatabaseKeyMismatchException>()));

      final raw = sqlite3.open(path);
      expect(() => raw.select('SELECT * FROM customers'), throwsA(isA<SqliteException>()));
      raw.close();
    });

    test('se rouvre avec la bonne clé et retrouve les données', () {
      final first = AppDatabase.open(path: path, hexKey: keyA);
      first.write((d) => d.execute("INSERT INTO meta (key, value) VALUES ('user', 'abc')"));
      first.close();

      final second = AppDatabase.open(path: path, hexKey: keyA);
      expect(second.read((d) => d.select("SELECT value FROM meta WHERE key = 'user'").first['value']), 'abc');
      second.close();
    });

    test('refuse une clé mal formée (trop courte, non hexadécimale)', () {
      for (final bad in ['', 'abc', 'g' * 64, 'A' * 64, keyA.substring(1)]) {
        expect(() => AppDatabase.open(path: path, hexKey: bad), throwsA(isA<DatabaseException>()), reason: bad);
      }
      expect(File(path).existsSync() ? File(path).lengthSync() : 0, 0);
    });

    test('closeAndDelete supprime tous les fichiers de la base', () {
      final db = AppDatabase.open(path: path, hexKey: keyA);
      db.write((d) => d.execute("INSERT INTO meta (key, value) VALUES ('a', 'b')"));
      db.closeAndDelete();

      expect(dir.listSync(), isEmpty);
    });
  });

  final latest = appMigrations.last.version;

  group('schéma et migrations', () {
    test('une base de la version 1 (avant fournisseurs et caisse) migre sans perdre un client ni une dette', () {
      AppDatabase.open(path: path, hexKey: keyA, migrations: <Migration>[appMigrations.first])
        ..write((d) {
          d.execute("INSERT INTO customers (id, name, phone, credit_limit_cents, created_at) VALUES ('c', 'Aïcha', '+229 01 67 07 70 27', 5000, '2026-01-01')");
          d.execute("INSERT INTO debts VALUES ('d', 'c', 1000, 'Riz', 'Autre', NULL, '2026-01-01')");
        })
        ..close();

      final db = AppDatabase.open(path: path, hexKey: keyA);
      expect(db.schemaVersion, latest);
      final customer = db.read((d) => d.select('SELECT name, kind, reminder_opt_out FROM customers').first);
      expect(customer['name'], 'Aïcha');
      expect(customer['kind'], 'CLIENT', reason: 'les anciens clients restent des clients');
      expect(customer['reminder_opt_out'], 0);
      expect(db.read((d) => d.select('SELECT count(*) c FROM debts').first['c']), 1);
      expect(db.read((d) => d.select('SELECT count(*) c FROM cash_entries').first['c']), 0);
      db.close();
    });

    test('crée le schéma complet à la dernière version avec clés étrangères actives', () {
      final db = AppDatabase.openInMemory(hexKey: keyA);
      expect(db.schemaVersion, latest);
      final tables = db.read((d) => d.select("SELECT name FROM sqlite_master WHERE type='table'").map((r) => r['name']).toSet());
      expect(tables, containsAll(<String>['meta', 'customers', 'debts', 'payments', 'outbox', 'cash_entries']));
      expect(db.read((d) => d.select('PRAGMA foreign_keys').first.values.first), 1);
      db.close();
    });

    test('la suppression d\'un client supprime en cascade ses dettes et paiements', () {
      final db = AppDatabase.openInMemory(hexKey: keyA);
      db.write((d) {
        d.execute("INSERT INTO customers (id, name, phone, credit_limit_cents, created_at) VALUES ('c', 'A', '+229 01 67 07 70 27', NULL, '2026-01-01')");
        d.execute("INSERT INTO debts VALUES ('d', 'c', 1000, NULL, 'Autre', NULL, '2026-01-01')");
        d.execute("INSERT INTO payments VALUES ('p', 'd', 500, 'CASH', '2026-01-02')");
        d.execute("DELETE FROM customers WHERE id = 'c'");
      });
      expect(db.read((d) => d.select('SELECT count(*) c FROM debts').first['c']), 0);
      expect(db.read((d) => d.select('SELECT count(*) c FROM payments').first['c']), 0);
      db.close();
    });

    test('refuse une dette orpheline et un montant nul (contraintes)', () {
      final db = AppDatabase.openInMemory(hexKey: keyA);
      expect(
        () => db.write((d) => d.execute("INSERT INTO debts VALUES ('d', 'inconnu', 1000, NULL, 'Autre', NULL, '2026-01-01')")),
        throwsA(isA<SqliteException>()),
      );
      db.write((d) => d.execute("INSERT INTO customers (id, name, phone, credit_limit_cents, created_at) VALUES ('c', 'A', 'x', NULL, '2026-01-01')"));
      expect(
        () => db.write((d) => d.execute("INSERT INTO debts VALUES ('d', 'c', 0, NULL, 'Autre', NULL, '2026-01-01')")),
        throwsA(isA<SqliteException>()),
      );
      db.close();
    });

    test('monte de version en conservant les données, et ne rejoue pas les anciennes migrations', () {
      AppDatabase.open(path: path, hexKey: keyA)
        ..write((d) => d.execute("INSERT INTO meta VALUES ('keep', 'me')"))
        ..close();

      final migrations = <Migration>[
        ...appMigrations,
        Migration(latest + 1, const <String>['ALTER TABLE customers ADD COLUMN note TEXT']),
      ];
      final upgraded = AppDatabase.open(path: path, hexKey: keyA, migrations: migrations);
      expect(upgraded.schemaVersion, latest + 1);
      expect(upgraded.read((d) => d.select("SELECT value FROM meta WHERE key = 'keep'").first['value']), 'me');
      upgraded.write((d) => d.execute("INSERT INTO customers (id, name, phone, created_at, note) VALUES ('c', 'A', 'x', '2026-01-01', 'n')"));
      upgraded.close();

      // Réouverture : aucune migration à rejouer (sinon ALTER TABLE échouerait).
      AppDatabase.open(path: path, hexKey: keyA, migrations: migrations).close();
    });

    test('une migration qui échoue est annulée entièrement', () {
      AppDatabase.open(path: path, hexKey: keyA).close();
      final broken = <Migration>[
        ...appMigrations,
        Migration(latest + 1, const <String>['ALTER TABLE customers ADD COLUMN ok TEXT', 'CREATE TABLE ??? invalide']),
      ];

      expect(() => AppDatabase.open(path: path, hexKey: keyA, migrations: broken), throwsA(isA<SqliteException>()));

      final db = AppDatabase.open(path: path, hexKey: keyA);
      expect(db.schemaVersion, latest);
      final columns = db.read((d) => d.select('PRAGMA table_info(customers)').map((r) => r['name']).toList());
      expect(columns, isNot(contains('ok')));
      db.close();
    });

    test('refuse une base plus récente que l\'application (pas de rétrogradation)', () {
      AppDatabase.open(path: path, hexKey: keyA, migrations: [
        ...appMigrations,
        Migration(latest + 1, const <String>['ALTER TABLE customers ADD COLUMN note TEXT']),
      ]).close();

      expect(() => AppDatabase.open(path: path, hexKey: keyA), throwsA(isA<DatabaseException>()));
    });
  });

  group('effacement des données', () {
    test('clearAllData vide toutes les tables, conserve le schéma et la clé, et efface les traces du disque', () {
      final db = AppDatabase.open(path: path, hexKey: keyA);
      db.write((d) {
        d.execute("INSERT INTO cash_entries VALUES ('e', 'SALE', 500, 'VENTE_A_EFFACER_TUV', 'Autre', '2026-01-01')");
        d.execute("INSERT INTO customers (id, name, phone, credit_limit_cents, created_at) VALUES ('c', 'CLIENT_A_EFFACER_QRS', 'x', NULL, '2026-01-01')");
        d.execute("INSERT INTO debts VALUES ('d', 'c', 1000, NULL, 'Autre', NULL, '2026-01-01')");
        d.execute("INSERT INTO meta VALUES ('user_id', 'u1')");
        d.execute("INSERT INTO outbox (entity, entity_id, op, payload, created_at) VALUES ('debt', 'd', 'create', '{}', '2026-01-01')");
      });

      db.clearAllData();

      for (final table in ['customers', 'debts', 'payments', 'cash_entries', 'meta', 'outbox']) {
        expect(db.read((d) => d.select('SELECT count(*) c FROM $table').first['c']), 0, reason: table);
      }
      expect(db.schemaVersion, latest);
      db.write((d) => d.execute("INSERT INTO meta VALUES ('apres', 'ok')")); // reste utilisable
      db.close();
      AppDatabase.open(path: path, hexKey: keyA).close(); // même clé
    });
  });

  group('transactions et notifications', () {
    test('write annule tout en cas d\'erreur et n\'émet aucune notification', () {
      final db = AppDatabase.openInMemory(hexKey: keyA);
      var notifications = 0;
      final subscription = db.changes.listen((_) => notifications++);

      expect(
        () => db.write((d) {
          d.execute("INSERT INTO meta VALUES ('a', '1')");
          throw StateError('échec au milieu');
        }),
        throwsStateError,
      );

      expect(db.read((d) => d.select('SELECT count(*) c FROM meta').first['c']), 0);
      expect(notifications, 0);
      subscription.cancel();
      db.close();
    });

    test('émet une seule notification par transaction, même imbriquée', () {
      final db = AppDatabase.openInMemory(hexKey: keyA);
      var notifications = 0;
      final subscription = db.changes.listen((_) => notifications++);

      db.write((d) {
        d.execute("INSERT INTO meta VALUES ('a', '1')");
        db.write((inner) => inner.execute("INSERT INTO meta VALUES ('b', '2')"));
      });

      expect(notifications, 1);
      expect(db.read((d) => d.select('SELECT count(*) c FROM meta').first['c']), 2);
      subscription.cancel();
      db.close();
    });

    test('une erreur dans une transaction imbriquée annule la transaction externe', () {
      final db = AppDatabase.openInMemory(hexKey: keyA);
      expect(
        () => db.write((d) {
          d.execute("INSERT INTO meta VALUES ('a', '1')");
          db.write((_) => throw StateError('interne'));
        }),
        throwsStateError,
      );
      expect(db.read((d) => d.select('SELECT count(*) c FROM meta').first['c']), 0);
      db.close();
    });

    test('refuse tout accès après fermeture', () {
      final db = AppDatabase.openInMemory(hexKey: keyA)..close();
      expect(() => db.read((d) => d.select('SELECT 1')), throwsA(isA<DatabaseException>()));
      expect(() => db.write((d) => d.execute('SELECT 1')), throwsA(isA<DatabaseException>()));
    });
  });
}
