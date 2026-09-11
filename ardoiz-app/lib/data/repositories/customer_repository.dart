import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/customer.dart';
import '../local/app_database.dart';
import '../local/sync_queue.dart';
import '../remote/api_client.dart';

/// Repository offline-first : toute ecriture va d'abord en local (l'UI
/// n'attend jamais le reseau), puis est mise en file pour synchronisation.
class CustomerRepository {
  final _dio = ApiClient.instance.dio;
  final _syncQueue = SyncQueue();
  final _uuid = const Uuid();

  Future<List<Customer>> getAll(String userId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'customers',
      where: 'user_id = ? AND deleted = 0',
      whereArgs: [userId],
      orderBy: 'name ASC',
    );
    return rows.map(Customer.fromLocalMap).toList();
  }

  Future<Customer> create({
    required String userId,
    required String name,
    String? phone,
  }) async {
    final customer = Customer(
      id: _uuid.v4(),
      userId: userId,
      name: name,
      phone: phone,
      pendingSync: true,
    );

    final db = await AppDatabase.instance.database;
    await db.insert('customers', customer.toLocalMap());

    await _syncQueue.enqueue(
      entityType: SyncEntity.customer,
      entityId: customer.id,
      operation: SyncOperation.create,
      payload: {'localId': customer.id, 'name': name, 'phone': phone},
    );

    return customer;
  }

  /// Recupere la liste distante et rafraichit le cache local (appele
  /// quand la connectivite est disponible, ex. au pull-to-refresh).
  Future<void> refreshFromRemote(String userId) async {
    final response = await _dio.get('/customers');
    final remoteCustomers = (response.data as List)
        .map((json) => Customer.fromJson(json as Map<String, dynamic>))
        .toList();

    final db = await AppDatabase.instance.database;
    final batch = db.batch();
    for (final customer in remoteCustomers) {
      batch.insert(
        'customers',
        customer.toLocalMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
