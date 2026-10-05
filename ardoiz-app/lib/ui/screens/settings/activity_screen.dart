import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatters.dart';
import '../../widgets/common.dart';

/// Journal d'activité du compte : ce qui s'est passé et quand (jamais d'adresse IP
/// ni de donnée du carnet). Permet de repérer une connexion que l'on ne reconnaît pas.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(activityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activité du compte')),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Activité indisponible',
          message: describeError(error),
          action: BusyButton(label: 'Réessayer', onPressed: () => ref.invalidate(activityProvider)),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(activityProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Text(
                  'Les 100 derniers événements, conservés 12 mois. Si une connexion vous semble inconnue, changez votre code PIN : toutes les autres sessions seront fermées.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (list.isEmpty) const EmptyState(icon: Icons.history, title: 'Rien à afficher', message: 'Aucune activité enregistrée.'),
              for (final event in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(event.label),
                    subtitle: Text('${formatDate(event.at)} à ${formatTime(event.at)}'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
