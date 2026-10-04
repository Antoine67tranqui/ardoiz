import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'app_database.dart';

enum OutboxEntity { customer, debt, payment }

enum OutboxOp { create, update, delete }

/// pending : à envoyer · inFlight : envoi en cours · blocked : refusé par le
/// serveur de façon définitive, en attente d'une décision du commerçant.
enum OutboxStatus { pending, inFlight, blocked }

class OutboxEntry {
  const OutboxEntry({
    required this.seq,
    required this.entity,
    required this.entityId,
    required this.op,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    required this.status,
    this.nextAttemptAt,
    this.lastError,
  });

  final int seq;
  final OutboxEntity entity;
  final String entityId;
  final OutboxOp op;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final OutboxStatus status;

  /// Identifiants d'entités dont cette opération dépend (client d'une dette,
  /// dette d'un paiement).
  Set<String> get references => <String>{
        if (payload['customerId'] is String) payload['customerId']! as String,
        if (payload['debtId'] is String) payload['debtId']! as String,
      };
}

/// File d'envoi persistante des modifications locales. Elle garantit qu'aucune
/// saisie n'est perdue hors ligne : chaque écriture locale ajoute ici, dans la
/// MÊME transaction, l'opération à rejouer vers le serveur.
class OutboxStore {
  const OutboxStore(this._db);

  final AppDatabase _db;

  /// Ajoute une opération en la compactant avec celles déjà en attente :
  ///  - modification d'une entité jamais envoyée : fusionnée dans sa création ;
  ///  - suppression d'une entité jamais envoyée : plus rien à envoyer ;
  ///  - modifications successives : fusionnées (la dernière valeur gagne).
  /// Une opération déjà EN COURS d'envoi n'est jamais modifiée ni supprimée
  /// (le serveur l'a peut-être déjà reçue).
  /// [descendantIds] : dettes/paiements supprimés en cascade avec l'entité.
  void enqueue({
    required OutboxEntity entity,
    required String entityId,
    required OutboxOp op,
    required DateTime now,
    Map<String, Object?> payload = const <String, Object?>{},
    Set<String> descendantIds = const <String>{},
  }) {
    _db.write((db) {
      final existing = _forEntity(db, entityId);

      switch (op) {
        case OutboxOp.create:
          _insert(db, entity, entityId, op, payload, now);
        case OutboxOp.update:
          final target = existing.reversed.where((e) => e.status != OutboxStatus.inFlight && e.op != OutboxOp.delete).firstOrNull;
          if (target != null && target == existing.last) {
            _setPayload(db, target.seq, <String, Object?>{...target.payload, ...payload});
          } else {
            _insert(db, entity, entityId, op, payload, now);
          }
        case OutboxOp.delete:
          final neverSent = existing.any((e) => e.op == OutboxOp.create && e.status != OutboxStatus.inFlight);
          _deleteWhere(db, <String>{entityId, ...descendantIds}, onlyNotInFlight: true);
          if (!neverSent) {
            _insert(db, entity, entityId, op, const <String, Object?>{}, now);
          }
      }
    });
  }

  List<OutboxEntry> all() => _db.read((db) => _select(db, 'SELECT * FROM outbox ORDER BY seq'));

  List<OutboxEntry> blocked() =>
      _db.read((db) => _select(db, "SELECT * FROM outbox WHERE status = 'blocked' ORDER BY seq"));

  /// Opérations à envoyer maintenant (en attente, délai de reprise écoulé), dans l'ordre.
  List<OutboxEntry> due(DateTime now) => _db.read(
        (db) => _select(
          db,
          "SELECT * FROM outbox WHERE status = 'pending' AND (next_attempt_at IS NULL OR next_attempt_at <= ?) ORDER BY seq",
          [now.toUtc().toIso8601String()],
        ),
      );

  /// Date de la prochaine reprise programmée, s'il y en a une.
  DateTime? nextRetryAt() => _db.read((db) {
        final rows = db.select("SELECT MIN(next_attempt_at) AS t FROM outbox WHERE status = 'pending' AND next_attempt_at IS NOT NULL");
        final value = rows.first['t'] as String?;
        return value == null ? null : DateTime.parse(value);
      });

  int count({OutboxStatus? status}) => _db.read((db) {
        final rows = status == null
            ? db.select('SELECT count(*) AS c FROM outbox')
            : db.select('SELECT count(*) AS c FROM outbox WHERE status = ?', [_statusName(status)]);
        return rows.first['c']! as int;
      });

  /// Entités ayant au moins une opération non terminée : le serveur ne doit
  /// pas écraser leur version locale.
  Set<String> entityIds() =>
      _db.read((db) => db.select('SELECT DISTINCT entity_id FROM outbox').map((r) => r['entity_id']! as String).toSet());

  /// Au démarrage : un envoi interrompu est repris (sans risque grâce aux ids idempotents).
  void resetInFlight() => _db.write((db) => db.execute("UPDATE outbox SET status = 'pending' WHERE status = 'in_flight'"));

  /// Remet en attente une opération dont l'envoi n'a pas pu avoir lieu (ex. session expirée).
  void markPending(int seq) => _db.write((db) => db.execute("UPDATE outbox SET status = 'pending' WHERE seq = ?", [seq]));

  void markInFlight(int seq) => _db.write((db) => db.execute("UPDATE outbox SET status = 'in_flight' WHERE seq = ?", [seq]));

  void complete(int seq) => _db.write((db) => db.execute('DELETE FROM outbox WHERE seq = ?', [seq]));

  /// Échec temporaire : l'opération reste en tête de file, reprise à [nextAttemptAt].
  void recordFailure(int seq, {required String error, required DateTime nextAttemptAt}) => _db.write(
        (db) => db.execute(
          "UPDATE outbox SET status = 'pending', attempts = attempts + 1, last_error = ?, next_attempt_at = ? WHERE seq = ?",
          [error, nextAttemptAt.toUtc().toIso8601String(), seq],
        ),
      );

  /// Refus définitif du serveur : l'opération et celles qui en dépendent sont
  /// bloquées (elles échoueraient toutes) jusqu'à une décision du commerçant.
  void block(OutboxEntry entry, String reason) => _db.write((db) {
        db.execute("UPDATE outbox SET status = 'blocked', last_error = ? WHERE seq = ?", [reason, entry.seq]);
        for (final dependent in _dependents(db, entry)) {
          db.execute(
            "UPDATE outbox SET status = 'blocked', last_error = ? WHERE seq = ?",
            ['Dépend d\'une opération refusée par le serveur.', dependent.seq],
          );
        }
      });

  /// Le commerçant relance une opération bloquée (et celles qui en dépendent).
  void retry(OutboxEntry entry) => _db.write((db) {
        for (final target in <OutboxEntry>[entry, ..._dependents(db, entry)]) {
          db.execute(
            "UPDATE outbox SET status = 'pending', attempts = 0, last_error = NULL, next_attempt_at = NULL WHERE seq = ?",
            [target.seq],
          );
        }
      });

  /// Supprime l'opération et celles qui en dépendent. Renvoie les entités
  /// concernées (le dépôt annule alors leurs effets locaux).
  List<OutboxEntry> discard(OutboxEntry entry) => _db.write((db) {
        final removed = <OutboxEntry>[entry, ..._dependents(db, entry)];
        for (final item in removed) {
          db.execute('DELETE FROM outbox WHERE seq = ?', [item.seq]);
        }
        return removed;
      });

  void clear() => _db.write((db) => db.execute('DELETE FROM outbox'));

  // ---- Interne ----

  /// Opérations postérieures qui référencent l'entité de [entry] (chaîne
  /// client → dette → paiement) et ne sont pas en cours d'envoi.
  List<OutboxEntry> _dependents(Database db, OutboxEntry entry) {
    final chain = <String>{entry.entityId};
    final result = <OutboxEntry>[];
    for (final candidate in _select(db, 'SELECT * FROM outbox WHERE seq > ? ORDER BY seq', [entry.seq])) {
      if (candidate.status == OutboxStatus.inFlight) continue;
      if (chain.contains(candidate.entityId) || candidate.references.any(chain.contains)) {
        chain.add(candidate.entityId);
        result.add(candidate);
      }
    }
    return result;
  }

  List<OutboxEntry> _forEntity(Database db, String entityId) =>
      _select(db, 'SELECT * FROM outbox WHERE entity_id = ? ORDER BY seq', [entityId]);

  void _insert(Database db, OutboxEntity entity, String entityId, OutboxOp op, Map<String, Object?> payload, DateTime now) {
    db.execute(
      'INSERT INTO outbox (entity, entity_id, op, payload, created_at) VALUES (?, ?, ?, ?, ?)',
      [entity.name, entityId, op.name, jsonEncode(payload), now.toUtc().toIso8601String()],
    );
  }

  void _setPayload(Database db, int seq, Map<String, Object?> payload) =>
      db.execute('UPDATE outbox SET payload = ? WHERE seq = ?', [jsonEncode(payload), seq]);

  void _deleteWhere(Database db, Set<String> entityIds, {required bool onlyNotInFlight}) {
    if (entityIds.isEmpty) return;
    final marks = List.filled(entityIds.length, '?').join(',');
    db.execute(
      "DELETE FROM outbox WHERE entity_id IN ($marks)${onlyNotInFlight ? " AND status != 'in_flight'" : ''}",
      entityIds.toList(),
    );
  }

  List<OutboxEntry> _select(Database db, String sql, [List<Object?> args = const <Object?>[]]) =>
      db.select(sql, args).map(_entry).toList();

  static OutboxEntry _entry(Row r) => OutboxEntry(
        seq: r['seq']! as int,
        entity: OutboxEntity.values.byName(r['entity']! as String),
        entityId: r['entity_id']! as String,
        op: OutboxOp.values.byName(r['op']! as String),
        payload: (jsonDecode(r['payload']! as String) as Map<String, dynamic>).cast<String, Object?>(),
        createdAt: DateTime.parse(r['created_at']! as String),
        attempts: r['attempts']! as int,
        nextAttemptAt: r['next_attempt_at'] == null ? null : DateTime.parse(r['next_attempt_at']! as String),
        lastError: r['last_error'] as String?,
        status: _parseStatus(r['status']! as String),
      );

  static OutboxStatus _parseStatus(String value) => switch (value) {
        'in_flight' => OutboxStatus.inFlight,
        'blocked' => OutboxStatus.blocked,
        _ => OutboxStatus.pending,
      };

  static String _statusName(OutboxStatus status) => switch (status) {
        OutboxStatus.inFlight => 'in_flight',
        OutboxStatus.blocked => 'blocked',
        OutboxStatus.pending => 'pending',
      };
}
