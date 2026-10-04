import '../../core/money.dart';
import '../../domain/models.dart';
import '../local/outbox_store.dart';
import '../remote/api_client.dart';
import '../remote/api_exceptions.dart';

/// État complet du commerçant côté serveur.
class RemoteSnapshot {
  const RemoteSnapshot({
    required this.serverTime,
    required this.customers,
    required this.debts,
    required this.payments,
  });

  final DateTime serverTime;
  final List<Customer> customers;
  final List<Debt> debts;
  final List<Payment> payments;
}

/// Contrat entre le moteur de synchronisation et le serveur. Implémenté par
/// [HttpLedgerTransport] (réseau réel) et par un faux serveur dans les tests ;
/// les deux sont vérifiés par la même suite de tests de contrat.
abstract interface class LedgerTransport {
  /// Rejoue une opération locale. Les créations sont idempotentes (id client) :
  /// un renvoi après un échec ambigu ne crée jamais de doublon.
  Future<void> send(OutboxEntry entry);

  Future<RemoteSnapshot> snapshot();
}

class HttpLedgerTransport implements LedgerTransport {
  const HttpLedgerTransport(this._api);

  final ApiClient _api;

  @override
  Future<void> send(OutboxEntry entry) async {
    final id = entry.entityId;
    final p = entry.payload;
    switch ((entry.entity, entry.op)) {
      case (OutboxEntity.customer, OutboxOp.create):
        await _api.send('POST', '/customers', body: <String, Object?>{
          'id': id,
          'name': p['name'],
          'phone': p['phone'],
          if (p['creditLimitCents'] != null) 'creditLimit': _money(p['creditLimitCents']),
        });
      case (OutboxEntity.customer, OutboxOp.update):
        await _api.send('PATCH', '/customers/$id', body: <String, Object?>{
          if (p.containsKey('name')) 'name': p['name'],
          if (p.containsKey('phone')) 'phone': p['phone'],
          if (p.containsKey('creditLimitCents')) 'creditLimit': _money(p['creditLimitCents']),
        });
      case (OutboxEntity.customer, OutboxOp.delete):
        await _api.send('DELETE', '/customers/$id');
      case (OutboxEntity.debt, OutboxOp.create):
        await _api.send('POST', '/debts', body: <String, Object?>{
          'id': id,
          'customerId': p['customerId'],
          'amount': _money(p['amountCents']),
          if (p['reason'] != null) 'reason': p['reason'],
          'category': p['category'],
          if (p['dueDate'] != null) 'dueDate': p['dueDate'],
          'createdAt': p['createdAt'],
        });
      case (OutboxEntity.debt, OutboxOp.update):
        await _api.send('PATCH', '/debts/$id', body: <String, Object?>{
          if (p.containsKey('amountCents')) 'amount': _money(p['amountCents']),
          if (p.containsKey('reason')) 'reason': p['reason'],
          if (p.containsKey('category')) 'category': p['category'],
          if (p.containsKey('dueDate')) 'dueDate': p['dueDate'],
        });
      case (OutboxEntity.debt, OutboxOp.delete):
        await _api.send('DELETE', '/debts/$id');
      case (OutboxEntity.payment, OutboxOp.create):
        await _api.send('POST', '/payments', body: <String, Object?>{
          'id': id,
          'debtId': p['debtId'],
          'amount': _money(p['amountCents']),
          'method': p['method'],
          'paidAt': p['paidAt'],
        });
      case (OutboxEntity.payment, OutboxOp.update):
        throw StateError('Les paiements ne se modifient pas : supprimer puis recréer.');
      case (OutboxEntity.payment, OutboxOp.delete):
        await _api.send('DELETE', '/payments/$id');
    }
  }

  @override
  Future<RemoteSnapshot> snapshot() async {
    final body = await _api.send('GET', '/sync/snapshot');
    try {
      final json = body! as Map<String, Object?>;
      return RemoteSnapshot(
        serverTime: DateTime.parse(json['serverTime']! as String),
        customers: (json['customers']! as List<Object?>).map((c) => _customer(c! as Map<String, Object?>)).toList(),
        debts: (json['debts']! as List<Object?>).map((d) => _debt(d! as Map<String, Object?>)).toList(),
        payments: (json['payments']! as List<Object?>).map((p) => _payment(p! as Map<String, Object?>)).toList(),
      );
    } on Object catch (error) {
      if (error is ApiException) rethrow;
      throw const ServerException(200, 'Réponse de synchronisation invalide.');
    }
  }

  static num? _money(Object? cents) => cents == null ? null : Money.fromCents(cents as int).toJson();

  static Customer _customer(Map<String, Object?> j) => Customer(
        id: j['id']! as String,
        name: j['name']! as String,
        phone: j['phone']! as String,
        creditLimit: j['creditLimit'] == null ? null : Money.fromJson(j['creditLimit']! as num),
        createdAt: DateTime.parse(j['createdAt']! as String),
      );

  static Debt _debt(Map<String, Object?> j) => Debt(
        id: j['id']! as String,
        customerId: j['customerId']! as String,
        amount: Money.fromJson(j['amount']! as num),
        reason: j['reason'] as String?,
        category: j['category']! as String,
        dueDate: j['dueDate'] == null ? null : DateTime.parse(j['dueDate']! as String),
        createdAt: DateTime.parse(j['createdAt']! as String),
      );

  static Payment _payment(Map<String, Object?> j) => Payment(
        id: j['id']! as String,
        debtId: j['debtId']! as String,
        amount: Money.fromJson(j['amount']! as num),
        method: PaymentMethod.fromWire(j['method']! as String),
        paidAt: DateTime.parse(j['paidAt']! as String),
      );
}
