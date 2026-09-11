import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/customers_provider.dart';
import '../widgets/customer_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersProvider);
    final businessNameAsync = ref.watch(currentBusinessNameProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(businessNameAsync.value ?? 'Ardoiz'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(customersProvider.future),
        child: customersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => const Center(child: Text("Erreur de chargement")),
          data: (customers) {
            if (customers.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Aucun client pour le moment.')),
                  Center(child: Text("Appuyez sur + pour ajouter votre premier client.")),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: customers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final customer = customers[index];
                return CustomerCard(
                  customer: customer,
                  onTap: () => context.push('/customers/${customer.id}'),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCustomerDialog(context, ref),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Client'),
      ),
    );
  }

  void _showAddCustomerDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: 'Nom du client'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Telephone (optionnel)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              final userId = await ref.read(currentUserIdProvider.future);
              if (userId == null || nameController.text.trim().isEmpty) return;
              await ref.read(customerRepositoryProvider).create(
                    userId: userId,
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim().isEmpty
                        ? null
                        : phoneController.text.trim(),
                  );
              ref.invalidate(customersProvider);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }
}
