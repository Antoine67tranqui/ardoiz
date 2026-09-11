import 'dart:convert';
import 'app_database.dart';

enum SyncOperation { create, update, delete }

enum SyncEntity { customer, debt, payment }

class SyncQueueEntry {
  final int id;
  final SyncEntity entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final int retryCount;

  SyncQueueEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.retryCount,
  });

  factory SyncQueueEntry.fromMap(Map<String, dynamic> map) => SyncQueueEntry(
        id: map['id'] as int,
        entityType: SyncEntity.values.firstWhere((e) => e.name == map['entity_type']),
        entityId: map['entity_id'] as String,
        operation: SyncOperation.values.firstWhere((e) => e.name == map['operation']),
        payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
        retryCount: map['retry_count'] as int,
      );
}

/// File d'attente persistante des operations locales en attente de
/// synchronisation avec le backend. Garantit qu'aucune action du
/// commercant n'est perdue en cas de coupure reseau.
class SyncQueue {
  Future<void> enqueue({
    required SyncEntity entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.insert('sync_queue', {
      'entity_type': entityType.name,
      'entity_id': entityId,
      'operation': operation.name,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
    });
  }

  Future<List<SyncQueueEntry>> pending() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('sync_queue', orderBy: 'created_at ASC');
    return rows.map(SyncQueueEntry.fromMap).toList();
  }

  Future<void> remove(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> incrementRetry(int id) async {
    final db = await AppDatabase.instance.database;
    await db.rawUpdate(
      'UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?',
      [id],
    );
  }
}
