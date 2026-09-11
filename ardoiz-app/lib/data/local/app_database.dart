import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Base de donnees locale offline-first. Toute ecriture (client, dette,
/// paiement) est d'abord persistee ici avec `pending_sync = 1`, puis
/// synchronisee vers le backend des que la connexion est disponible.
class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ardoiz.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            name TEXT NOT NULL,
            phone TEXT,
            outstanding_balance REAL NOT NULL DEFAULT 0,
            pending_sync INTEGER NOT NULL DEFAULT 0,
            deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE debts (
            id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            amount REAL NOT NULL,
            reason TEXT,
            status TEXT NOT NULL DEFAULT 'PENDING',
            due_date TEXT,
            created_at TEXT NOT NULL,
            pending_sync INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE payments (
            id TEXT PRIMARY KEY,
            debt_id TEXT NOT NULL,
            amount REAL NOT NULL,
            method TEXT NOT NULL,
            paid_at TEXT NOT NULL,
            pending_sync INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (debt_id) REFERENCES debts (id) ON DELETE CASCADE
          )
        ''');

        // File d'attente de synchronisation generique : chaque ligne
        // represente une operation locale a rejouer contre l'API.
        await db.execute('''
          CREATE TABLE sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }
}
