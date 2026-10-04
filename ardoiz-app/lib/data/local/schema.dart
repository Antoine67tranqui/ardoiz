/// Une étape de migration de la base locale.
class Migration {
  const Migration(this.version, this.statements);

  final int version;
  final List<String> statements;
}

/// Migrations dans l'ordre. Ne JAMAIS modifier une migration déjà publiée :
/// en ajouter une nouvelle (le test de migration vérifie la montée de version).
const List<Migration> appMigrations = <Migration>[
  Migration(1, <String>[
    '''
    CREATE TABLE meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )''',
    '''
    CREATE TABLE customers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT NOT NULL,
      credit_limit_cents INTEGER,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE debts (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL REFERENCES customers (id) ON DELETE CASCADE,
      amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
      reason TEXT,
      category TEXT NOT NULL,
      due_date TEXT,
      created_at TEXT NOT NULL
    )''',
    'CREATE INDEX idx_debts_customer ON debts (customer_id)',
    '''
    CREATE TABLE payments (
      id TEXT PRIMARY KEY,
      debt_id TEXT NOT NULL REFERENCES debts (id) ON DELETE CASCADE,
      amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
      method TEXT NOT NULL,
      paid_at TEXT NOT NULL
    )''',
    'CREATE INDEX idx_payments_debt ON payments (debt_id)',
    // File d'envoi persistante : chaque ligne est une opération locale à
    // rejouer vers l'API, dans l'ordre (seq).
    '''
    CREATE TABLE outbox (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      entity TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      op TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT,
      last_error TEXT,
      status TEXT NOT NULL DEFAULT 'pending'
    )''',
    'CREATE INDEX idx_outbox_entity ON outbox (entity_id)',
  ]),
];
