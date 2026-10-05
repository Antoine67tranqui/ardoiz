import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

class DatabaseException implements Exception {
  const DatabaseException(this.message);
  final String message;
  @override
  String toString() => 'DatabaseException: $message';
}

/// SQLCipher n'est pas disponible : la base serait en clair. L'app refuse de
/// démarrer plutôt que de stocker des données financières sans chiffrement.
class EncryptionUnavailableException extends DatabaseException {
  const EncryptionUnavailableException()
      : super('SQLCipher indisponible : la base locale ne serait pas chiffrée.');
}

/// La clé ne déchiffre pas la base existante (clé perdue ou fichier corrompu).
class DatabaseKeyMismatchException extends DatabaseException {
  const DatabaseKeyMismatchException()
      : super('La clé de chiffrement ne permet pas d\'ouvrir la base locale.');
}

/// Base locale offline-first, chiffrée (SQLCipher, AES-256). L'API de sqlite3
/// est synchrone : les volumes d'un commerçant (centaines de lignes) restent
/// très inférieurs à une image de l'interface.
class AppDatabase {
  AppDatabase._(this._db, this.path);

  final Database _db;

  /// Chemin du fichier, ou null pour une base en mémoire.
  final String? path;

  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);
  int _writeDepth = 0;
  bool _closed = false;

  static final RegExp _hexKey = RegExp(r'^[0-9a-f]{64}$');

  /// Ouvre (ou crée) la base chiffrée à [path] avec la clé hexadécimale [hexKey].
  static AppDatabase open({
    required String path,
    required String hexKey,
    List<Migration> migrations = appMigrations,
  }) =>
      _open(sqlite3.open(path), path, hexKey, migrations);

  /// Base en mémoire (tests) : chiffrée elle aussi, pour exercer le même chemin.
  static AppDatabase openInMemory({
    required String hexKey,
    List<Migration> migrations = appMigrations,
  }) =>
      _open(sqlite3.openInMemory(), null, hexKey, migrations);

  static AppDatabase _open(Database db, String? path, String hexKey, List<Migration> migrations) {
    try {
      if (!_hexKey.hasMatch(hexKey)) {
        throw const DatabaseException('Clé de chiffrement invalide (64 caractères hexadécimaux attendus).');
      }
      // Fail closed : sans SQLCipher, PRAGMA key est ignoré en silence.
      if (db.select('PRAGMA cipher_version').isEmpty) {
        throw const EncryptionUnavailableException();
      }
      // Clé brute (pas de dérivation PBKDF2 : la clé est déjà aléatoire).
      db.execute('''PRAGMA key = "x'$hexKey'"''');
      try {
        db.select('SELECT count(*) FROM sqlite_master');
      } on SqliteException {
        throw const DatabaseKeyMismatchException();
      }
      db.execute('PRAGMA foreign_keys = ON');
      // Les lignes supprimées sont écrasées (pas de reste de données financières).
      db.execute('PRAGMA secure_delete = ON');
      db.select('PRAGMA journal_mode = WAL');
      _migrate(db, migrations);
      return AppDatabase._(db, path);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static void _migrate(Database db, List<Migration> migrations) {
    final current = db.select('PRAGMA user_version').first.values.first! as int;
    final latest = migrations.isEmpty ? 0 : migrations.last.version;
    if (current > latest) {
      throw DatabaseException(
        'La base locale (v$current) est plus récente que l\'application (v$latest).',
      );
    }
    for (final migration in migrations.where((m) => m.version > current)) {
      db.execute('BEGIN IMMEDIATE');
      try {
        migration.statements.forEach(db.execute);
        db.execute('PRAGMA user_version = ${migration.version}');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  int get schemaVersion => _db.select('PRAGMA user_version').first.values.first! as int;

  /// Émet après chaque écriture validée : les écrans se rafraîchissent.
  Stream<void> get changes => _changes.stream;

  T read<T>(T Function(Database db) action) {
    _ensureOpen();
    return action(_db);
  }

  /// Exécute [action] dans une transaction (tout ou rien). Les appels imbriqués
  /// rejoignent la transaction en cours.
  T write<T>(T Function(Database db) action) {
    _ensureOpen();
    if (_writeDepth > 0) {
      _writeDepth++;
      try {
        return action(_db);
      } finally {
        _writeDepth--;
      }
    }
    _db.execute('BEGIN IMMEDIATE');
    _writeDepth = 1;
    try {
      final result = action(_db);
      _db.execute('COMMIT');
      _writeDepth = 0;
      _changes.add(null);
      return result;
    } catch (_) {
      _writeDepth = 0;
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _db.close();
    unawaited(_changes.close());
  }

  /// Efface toutes les données (déconnexion, changement de compte) en conservant
  /// la base et sa clé. `secure_delete` écrase les lignes supprimées, puis VACUUM
  /// réécrit le fichier : plus aucune trace des données du commerçant précédent.
  void clearAllData() {
    _ensureOpen();
    write((db) {
      for (final table in const ['outbox', 'payments', 'debts', 'customers', 'cash_entries', 'meta']) {
        db.execute('DELETE FROM $table');
      }
    });
    _db.execute('VACUUM');
  }

  /// Ferme la base et supprime ses fichiers (déconnexion : aucune donnée
  /// financière ne doit rester sur l'appareil).
  void closeAndDelete() {
    final file = path;
    close();
    if (file == null) return;
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final f = File('$file$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }

  void _ensureOpen() {
    if (_closed) throw const DatabaseException('La base locale est fermée.');
  }
}
