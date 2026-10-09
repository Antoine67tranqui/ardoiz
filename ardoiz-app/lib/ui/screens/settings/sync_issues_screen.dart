import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../widgets/common.dart';

/// Modifications que le serveur a refusées : le commerçant décide de les
/// réessayer ou de les abandonner (jamais de perte silencieuse).
class SyncIssuesScreen extends ConsumerWidget {
  const SyncIssuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(syncIssuesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Modifications à vérifier')),
      body: issues.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(icon: Icons.error_outline, title: 'Lecture impossible', message: describeError(error)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Tout est en ordre',
                message: 'Aucune modification n\'a été refusée par le serveur.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                    child: Text(
                      'Ces modifications ont été enregistrées sur votre téléphone mais le serveur les a refusées. '
                      'Réessayez, ou abandonnez-les pour revenir à la version du serveur.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  for (final issue in list) _IssueCard(issue),
                ],
              ),
      ),
    );
  }
}

class _IssueCard extends ConsumerWidget {
  const _IssueCard(this.issue);

  final SyncIssue issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(issue.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.error_outline, size: 18, color: context.statusColors.overdue),
                const SizedBox(width: 6),
                Expanded(child: Text(issue.reason, style: TextStyle(color: context.statusColors.overdue, fontWeight: FontWeight.w600))),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: () {
                    ref.read(repositoryProvider).retryIssue(issue.entry);
                    ref.read(syncControlProvider).syncNow();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: 'Abandonner cette modification ?',
                      message: 'Elle sera supprimée de ce téléphone. Les modifications qui en dépendent seront aussi abandonnées.',
                      confirmLabel: 'Abandonner',
                      destructive: true,
                    );
                    if (ok) ref.read(repositoryProvider).discardIssue(issue.entry);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Abandonner'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
