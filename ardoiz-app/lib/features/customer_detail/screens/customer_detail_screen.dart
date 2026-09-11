import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/debts_provider.dart';
import '../widgets/debt_tile.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtsAsync = ref.watch(debtsForCustomerProvider(customerId));

    return Scaffold(
      appBar: AppBar(title: const Text('Historique du client')),
      body: debtsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => const Center(child: Text('Erreur de chargement')),
        data: (debts) {
          if (debts.isEmpty) {
            return const Center(child: Text('Aucune dette enregistree pour ce client.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: debts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final debt = debts[index];
              return DebtTile(
                debt: debt,
                onPay: () => context.push(
                  '/debts/${debt.id}/pay?customerId=$customerId&amount=${debt.amount}',
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/customers/$customerId/add-debt'),
        icon: const Icon(Icons.add),
        label: const Text('Ardoise'),
      ),
    );
  }
}
