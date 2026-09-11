import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/debt.dart';
import '../../domain/models/debt_status.dart';
import '../local/app_database.dart';
import '../local/sync_queue.dart';
import '../remote/api_client.dart';

class DebtRepository {
  final _dio = ApiClient.instance.dio;
  final _syncQueue = SyncQueue();
  final _uuid = const Uuid();

  Future<List<Debt>> getForCustomer(String customerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'debts',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Debt.fromLocalMap).toList();
  }

  Future<Debt> create({
    required String customerId,
    required double amount,
    String? reason,
    DateTime? dueDate,
  }) async {
    final debt = Debt(
      id: _uuid.v4(),
      customerId: customerId,
      amount: amount,
      reason: reason,
      status: DebtStatus.pending,
      dueDate: dueDate,
      createdAt: DateTime.now(),
      pendingSync: true,
    );

    final db = await AppDatabase.instance.database;
    await db.insert('debts', debt.toLocalMap());
    await _recalculateCustomerBalance(customerId);

    await _syncQueue.enqueue(
      entityType: SyncEntity.debt,
      entityId: debt.id,
      operation: SyncOperation.create,
      payload: {
        'customerId': customerId,
        'amount': amount,
        'reason': reason,
        'dueDate': dueDate?.toIso8601String(),
      },
    );

    return debt;
  }

  Future<void> recordCashPayment({
    required String debtId,
    required String customerId,
    required double amount,
  }) async {
    final db = await AppDatabase.instance.database;
    final paymentId = _uuid.v4();

    await db.insert('payments', {
      'id': paymentId,
      'debt_id': debtId,
      'amount': amount,
      'method': 'CASH',
      'paid_at': DateTime.now().toIso8601String(),
      'pending_sync': 1,
    });

    await _applyPaymentToLocalDebt(debtId, amount);
    await _recalculateCustomerBalance(customerId);

    await _syncQueue.enqueue(
      entityType: SyncEntity.payment,
      entityId: paymentId,
      operation: SyncOperation.create,
      payload: {'debtId': debtId, 'amount': amount, 'method': 'CASH'},
    );
  }

  Future<void> _applyPaymentToLocalDebt(String debtId, double amount) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('debts', where: 'id = ?', whereArgs: [debtId]);
    if (rows.isEmpty) return;

    final debt = Debt.fromLocalMap(rows.first);
    final totalPaid = await _totalPaidForDebt(debtId);
    final newStatus = totalPaid >= debt.amount
        ? DebtStatus.paid
        : (totalPaid > 0 ? DebtStatus.partial : DebtStatus.pending);

    await db.update(
      'debts',
      {'status': debtStatusToString(newStatus)},
      where: 'id = ?',
      whereArgs: [debtId],
    );
  }

  Future<double> _totalPaidForDebt(String debtId) async {
    final db = await AppDatabase.instance.database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM payments WHERE debt_id = ?',
      [debtId],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<void> _recalculateCustomerBalance(String customerId) async {
    final db = await AppDatabase.instance.database;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as total FROM debts WHERE customer_id = ? AND status != 'PAID'",
      [customerId],
    );
    final balance = (result.first['total'] as num).toDouble();
    await db.update(
      'customers',
      {'outstanding_balance': balance},
      where: 'id = ?',
      whereArgs: [customerId],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Rafraichit le cache local des dettes d'un client depuis l'API.
  Future<void> refreshFromRemote(String customerId) async {
    final response = await _dio.get('/customers/$customerId');
    final debts = (response.data['debts'] as List)
        .map((json) => Debt.fromJson(json as Map<String, dynamic>))
        .toList();

    final db = await AppDatabase.instance.database;
    final batch = db.batch();
    for (final debt in debts) {
      batch.insert('debts', debt.toLocalMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
