import 'package:connectivity_plus/connectivity_plus.dart';
import '../local/sync_queue.dart';
import '../remote/api_client.dart';

/// Rejoue la file d'attente locale des qu'une connexion est detectee.
/// Strategie de resolution de conflit : "derniere ecriture gagne" cote
/// serveur, avec horodatage serveur faisant autorite (le backend ignore
/// silencieusement les doublons via ID idempotent quand applicable, ex.
/// transactionRef unique pour les paiements Mobile Money).
class SyncService {
  final _queue = SyncQueue();
  final _dio = ApiClient.instance.dio;

  Future<void> syncIfOnline() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;
    await syncNow();
  }

  Future<void> syncNow() async {
    final pending = await _queue.pending();
    for (final entry in pending) {
      try {
        await _replay(entry);
        await _queue.remove(entry.id);
      } catch (_) {
        // Echec reseau ou serveur : on conserve l'entree et on
        // incremente le compteur pour eviter une boucle infinie agressive.
        await _queue.incrementRetry(entry.id);
      }
    }
  }

  Future<void> _replay(SyncQueueEntry entry) async {
    switch (entry.entityType) {
      case SyncEntity.customer:
        if (entry.operation == SyncOperation.create) {
          await _dio.post('/customers', data: {
            'name': entry.payload['name'],
            'phone': entry.payload['phone'],
          });
        }
        break;
      case SyncEntity.debt:
        if (entry.operation == SyncOperation.create) {
          await _dio.post('/debts', data: {
            'customerId': entry.payload['customerId'],
            'amount': entry.payload['amount'],
            'reason': entry.payload['reason'],
            'dueDate': entry.payload['dueDate'],
          });
        }
        break;
      case SyncEntity.payment:
        if (entry.operation == SyncOperation.create) {
          await _dio.post('/payments', data: {
            'debtId': entry.payload['debtId'],
            'amount': entry.payload['amount'],
            'method': entry.payload['method'],
          });
        }
        break;
    }
  }
}
