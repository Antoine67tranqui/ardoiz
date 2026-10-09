import 'package:sqlite3/sqlite3.dart';

import '../../core/money.dart';
import '../../domain/models.dart';
import 'app_database.dart';

/// Accès aux clients, dettes et paiements de la base locale. Les méthodes
/// d'écriture sont à appeler dans `AppDatabase.write` pour être atomiques.
class LedgerStore {
  const LedgerStore(this._db);

  final AppDatabase _db;

  // ---- Clients ----

  List<Customer> customers() => _db.read(
        (db) => db.select('SELECT * FROM customers ORDER BY name COLLATE NOCASE').map(_customer).toList(),
      );

  Customer? customer(String id) => _db.read((db) {
        final rows = db.select('SELECT * FROM customers WHERE id = ?', [id]);
        return rows.isEmpty ? null : _customer(rows.first);
      });

  /// Insère ou met à jour sans supprimer la ligne (un REPLACE déclencherait la
  /// suppression en cascade des dettes du client).
  void upsertCustomer(Customer customer) => _db.write((db) {
        db.execute(
          '''
          INSERT INTO customers (id, name, phone, credit_limit_cents, created_at, kind, reminder_opt_out)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            phone = excluded.phone,
            credit_limit_cents = excluded.credit_limit_cents,
            created_at = excluded.created_at,
            kind = excluded.kind,
            reminder_opt_out = excluded.reminder_opt_out
          ''',
          [
            customer.id,
            customer.name,
            customer.phone,
            customer.creditLimit?.cents,
            _iso(customer.createdAt),
            customer.kind.wire,
            customer.reminderOptOut ? 1 : 0,
          ],
        );
      });

  void deleteCustomer(String id) => _db.write((db) => db.execute('DELETE FROM customers WHERE id = ?', [id]));

  // ---- Dettes ----

  List<Debt> debts() => _db.read((db) => db.select('SELECT * FROM debts ORDER BY created_at DESC').map(_debt).toList());

  Debt? debt(String id) => _db.read((db) {
        final rows = db.select('SELECT * FROM debts WHERE id = ?', [id]);
        return rows.isEmpty ? null : _debt(rows.first);
      });

  void upsertDebt(Debt debt) => _db.write((db) {
        db.execute(
          '''
          INSERT INTO debts (id, customer_id, amount_cents, reason, category, due_date, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            customer_id = excluded.customer_id,
            amount_cents = excluded.amount_cents,
            reason = excluded.reason,
            category = excluded.category,
            due_date = excluded.due_date,
            created_at = excluded.created_at
          ''',
          [
            debt.id,
            debt.customerId,
            debt.amount.cents,
            debt.reason,
            debt.category,
            debt.dueDate == null ? null : _iso(debt.dueDate!),
            _iso(debt.createdAt),
          ],
        );
      });

  void deleteDebt(String id) => _db.write((db) => db.execute('DELETE FROM debts WHERE id = ?', [id]));

  // ---- Paiements ----

  List<Payment> payments() => _db.read((db) => db.select('SELECT * FROM payments ORDER BY paid_at DESC').map(_payment).toList());

  Payment? payment(String id) => _db.read((db) {
        final rows = db.select('SELECT * FROM payments WHERE id = ?', [id]);
        return rows.isEmpty ? null : _payment(rows.first);
      });

  void upsertPayment(Payment payment) => _db.write((db) {
        db.execute(
          '''
          INSERT INTO payments (id, debt_id, amount_cents, method, paid_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            debt_id = excluded.debt_id,
            amount_cents = excluded.amount_cents,
            method = excluded.method,
            paid_at = excluded.paid_at
          ''',
          [payment.id, payment.debtId, payment.amount.cents, payment.method.wire, _iso(payment.paidAt)],
        );
      });

  void deletePayment(String id) => _db.write((db) => db.execute('DELETE FROM payments WHERE id = ?', [id]));

  // ---- Journal de caisse ----

  List<CashEntry> cashEntries() => _db.read(
        (db) => db.select('SELECT * FROM cash_entries ORDER BY occurred_at DESC, id').map(_cash).toList(),
      );

  CashEntry? cashEntry(String id) => _db.read((db) {
        final rows = db.select('SELECT * FROM cash_entries WHERE id = ?', [id]);
        return rows.isEmpty ? null : _cash(rows.first);
      });

  void upsertCashEntry(CashEntry entry) => _db.write((db) {
        db.execute(
          '''
          INSERT INTO cash_entries (id, type, amount_cents, label, category, occurred_at)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            type = excluded.type,
            amount_cents = excluded.amount_cents,
            label = excluded.label,
            category = excluded.category,
            occurred_at = excluded.occurred_at
          ''',
          [entry.id, entry.type.wire, entry.amount.cents, entry.label, entry.category, _iso(entry.occurredAt)],
        );
      });

  void deleteCashEntry(String id) => _db.write((db) => db.execute('DELETE FROM cash_entries WHERE id = ?', [id]));

  // ---- Descendants (pour annuler les envois d'une suppression en cascade) ----

  Set<String> debtIdsOfCustomer(String customerId) => _db.read(
        (db) => db.select('SELECT id FROM debts WHERE customer_id = ?', [customerId]).map((r) => r['id']! as String).toSet(),
      );

  Set<String> paymentIdsOfCustomer(String customerId) => _db.read(
        (db) => db
            .select(
              'SELECT p.id FROM payments p JOIN debts d ON d.id = p.debt_id WHERE d.customer_id = ?',
              [customerId],
            )
            .map((r) => r['id']! as String)
            .toSet(),
      );

  Set<String> paymentIdsOfDebt(String debtId) => _db.read(
        (db) => db.select('SELECT id FROM payments WHERE debt_id = ?', [debtId]).map((r) => r['id']! as String).toSet(),
      );

  // ---- Métadonnées (clé/valeur) ----

  String? meta(String key) => _db.read((db) {
        final rows = db.select('SELECT value FROM meta WHERE key = ?', [key]);
        return rows.isEmpty ? null : rows.first['value']! as String;
      });

  void setMeta(String key, String value) => _db.write(
        (db) => db.execute(
          'INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [key, value],
        ),
      );

  void deleteMeta(String key) => _db.write((db) => db.execute('DELETE FROM meta WHERE key = ?', [key]));

  // ---- Conversions ----

  static String _iso(DateTime date) => date.toUtc().toIso8601String();

  static Customer _customer(Row r) => Customer(
        id: r['id']! as String,
        name: r['name']! as String,
        phone: r['phone']! as String,
        creditLimit: r['credit_limit_cents'] == null ? null : Money.fromCents(r['credit_limit_cents']! as int),
        createdAt: DateTime.parse(r['created_at']! as String),
        kind: PartyKind.fromWire(r['kind'] as String?),
        reminderOptOut: (r['reminder_opt_out'] as int? ?? 0) != 0,
      );

  static Debt _debt(Row r) => Debt(
        id: r['id']! as String,
        customerId: r['customer_id']! as String,
        amount: Money.fromCents(r['amount_cents']! as int),
        reason: r['reason'] as String?,
        category: r['category']! as String,
        dueDate: r['due_date'] == null ? null : DateTime.parse(r['due_date']! as String),
        createdAt: DateTime.parse(r['created_at']! as String),
      );

  static CashEntry _cash(Row r) => CashEntry(
        id: r['id']! as String,
        type: CashType.fromWire(r['type']! as String),
        amount: Money.fromCents(r['amount_cents']! as int),
        label: r['label'] as String?,
        category: r['category']! as String,
        occurredAt: DateTime.parse(r['occurred_at']! as String),
      );

  static Payment _payment(Row r) => Payment(
        id: r['id']! as String,
        debtId: r['debt_id']! as String,
        amount: Money.fromCents(r['amount_cents']! as int),
        method: PaymentMethod.fromWire(r['method']! as String),
        paidAt: DateTime.parse(r['paid_at']! as String),
      );
}
