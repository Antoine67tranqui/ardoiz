import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/sync_coordinator.dart';
import '../../core/theme/app_theme.dart';

/// Bandeau discret sur l'état de la synchronisation : rassure (« tout est
/// enregistré sur ce téléphone ») plutôt que d'inquiéter, et signale seulement
/// ce qui demande une décision (modifications refusées par le serveur).
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncStateProvider).value ?? const SyncState();
    final colors = context.statusColors;
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, String text, Color color, VoidCallback? onTap)? content = switch (state) {
      _ when state.blocked > 0 => (
          Icons.error_outline,
          '${state.blocked} modification${state.blocked > 1 ? 's' : ''} à vérifier',
          colors.overdue,
          () => context.push(Routes.syncIssues),
        ),
      _ when state.syncing => (Icons.sync, 'Synchronisation…', scheme.primary, null),
      _ when !state.online => (
          Icons.cloud_off_outlined,
          state.pending > 0
              ? 'Hors ligne · ${state.pending} modification${state.pending > 1 ? 's' : ''} enregistrée${state.pending > 1 ? 's' : ''} sur ce téléphone'
              : 'Hors ligne · vos données restent disponibles',
          colors.pending,
          null,
        ),
      _ when state.pending > 0 => (
          Icons.cloud_upload_outlined,
          '${state.pending} modification${state.pending > 1 ? 's' : ''} en attente d\'envoi',
          colors.pending,
          null,
        ),
      _ => null,
    };
    if (content == null) return const SizedBox.shrink();
    final (icon, text, color, onTap) = content;

    return Semantics(
      liveRegion: true,
      button: onTap != null,
      label: text,
      child: Material(
        color: color.withValues(alpha: 0.10),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                ExcludeSemantics(child: Icon(icon, size: 18, color: color)),
                const SizedBox(width: 10),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13.5)),
                  ),
                ),
                if (onTap != null) ExcludeSemantics(child: Icon(Icons.chevron_right, size: 18, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
