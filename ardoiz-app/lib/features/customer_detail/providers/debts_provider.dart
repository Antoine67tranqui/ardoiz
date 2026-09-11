import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/debt_repository.dart';
import '../../../domain/models/debt.dart';

final debtRepositoryProvider = Provider((ref) => DebtRepository());

final debtsForCustomerProvider =
    FutureProvider.autoDispose.family<List<Debt>, String>((ref, customerId) async {
  final repo = ref.watch(debtRepositoryProvider);
  await repo.refreshFromRemote(customerId).catchError((_) {});
  return repo.getForCustomer(customerId);
});
