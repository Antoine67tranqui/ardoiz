import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/customer_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../domain/models/customer.dart';
import '../../auth/providers/auth_provider.dart';

final customerRepositoryProvider = Provider((ref) => CustomerRepository());
final syncServiceProvider = Provider((ref) => SyncService());

final customersProvider =
    FutureProvider.autoDispose<List<Customer>>((ref) async {
  final userId = await ref.watch(currentUserIdProvider.future);
  if (userId == null) return [];

  final repo = ref.watch(customerRepositoryProvider);
  final syncService = ref.watch(syncServiceProvider);

  // Synchronise en arriere-plan sans bloquer l'affichage du cache local.
  unawaited(syncService.syncIfOnline().then((_) => repo.refreshFromRemote(userId)));

  return repo.getAll(userId);
});
