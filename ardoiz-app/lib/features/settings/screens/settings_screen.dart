import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessNameAsync = ref.watch(currentBusinessNameProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Parametres')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.store_outlined),
            title: const Text('Boutique'),
            subtitle: Text(businessNameAsync.value ?? '-'),
          ),
          SwitchListTile(
            value: true,
            onChanged: (_) {},
            title: const Text('Relances automatiques'),
            subtitle: const Text(
              "Envoyer un SMS automatique aux clients en retard de paiement",
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Deconnexion', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await ref.read(authRepositoryProvider).logout();
              if (context.mounted) context.go('/phone');
            },
          ),
        ],
      ),
    );
  }
}
