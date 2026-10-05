import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/session_service.dart';
import '../../../app/sync_coordinator.dart';
import '../../../core/brand.dart';
import '../../../core/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy_widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;
  bool _exportingData = false;
  bool _loggingOut = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session is! SignedIn) return const Scaffold();
    final profile = session.profile;
    final isPremium = ref.watch(isPremiumProvider);
    final sync = ref.watch(syncStateProvider).value ?? const SyncState();
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  AppAvatar(profile.businessName, radius: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(profile.businessName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text(formatPhone(profile.phone), style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 6),
                        _PlanChip(isPremium: isPremium, expiresAt: profile.planExpiresAt, now: now),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Ma boutique'),
          _Tile(
            icon: Icons.storefront_outlined,
            title: 'Nom de la boutique',
            subtitle: profile.businessName,
            onTap: () => context.push(Routes.businessName),
          ),
          _Tile(
            icon: Icons.workspace_premium_outlined,
            title: 'Abonnement',
            subtitle: isPremium ? 'Premium' : 'Plan gratuit · $freePlanCustomerLimit clients',
            onTap: () => context.push(Routes.subscription),
          ),
          _Tile(
            icon: Icons.notifications_active_outlined,
            title: 'Relances automatiques',
            subtitle: isPremium ? 'Choisir quand relancer vos clients' : 'Réservé à Premium',
            onTap: () => context.push(Routes.reminderRules),
          ),
          const SectionTitle('Sécurité'),
          _Tile(
            icon: Icons.lock_outline,
            title: 'Changer mon code PIN',
            subtitle: 'Les autres appareils seront déconnectés',
            onTap: () => context.push(Routes.changePin),
          ),
          const SectionTitle('Vie privée et données'),
          _Tile(
            icon: Icons.privacy_tip_outlined,
            title: 'Ce que Carné fait de vos données',
            subtitle: 'Conditions d\'utilisation et confidentialité',
            onTap: () => showPrivacySummary(context),
          ),
          _Tile(
            icon: Icons.download_for_offline_outlined,
            title: 'Exporter toutes mes données',
            subtitle: 'Copie complète au format JSON (nécessite une connexion)',
            trailing: _exportingData ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : null,
            onTap: _exportingData ? null : _exportMyData,
          ),
          _Tile(
            icon: Icons.history,
            title: 'Activité du compte',
            subtitle: 'Connexions et changements récents',
            onTap: () => context.push(Routes.activity),
          ),
          _Tile(
            icon: Icons.delete_forever_outlined,
            iconColor: theme.colorScheme.error,
            title: 'Supprimer mon compte',
            subtitle: 'Efface définitivement vos données',
            onTap: () => context.push(Routes.deleteAccount),
          ),
          const SectionTitle('Données'),
          _Tile(
            icon: sync.online ? Icons.sync : Icons.cloud_off_outlined,
            title: 'Synchronisation',
            subtitle: _syncText(sync),
            action: TextButton(
              onPressed: sync.syncing ? null : () => ref.read(syncControlProvider).syncNow(),
              child: Text(sync.syncing ? 'En cours…' : 'Synchroniser'),
            ),
          ),
          if (sync.blocked > 0)
            _Tile(
              icon: Icons.error_outline,
              iconColor: context.statusColors.overdue,
              title: 'Modifications à vérifier',
              subtitle: '${sync.blocked} refusée${sync.blocked > 1 ? 's' : ''} par le serveur',
              onTap: () => context.push(Routes.syncIssues),
            ),
          _Tile(
            icon: Icons.ios_share,
            title: 'Exporter l\'historique',
            subtitle: 'Fichier CSV (nécessite une connexion)',
            trailing: _exporting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : null,
            onTap: _exporting ? null : _export,
          ),
          const SectionTitle('À propos'),
          const _Tile(
            icon: Icons.menu_book_outlined,
            title: '${Brand.name} ${Brand.version}',
            subtitle: 'Vos données sont chiffrées sur ce téléphone et fonctionnent sans connexion.',
          ),
          const _Tile(
            icon: Icons.handshake_outlined,
            title: 'Conçu et développé par',
            subtitle: Brand.publisher,
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: PublisherLogo(width: 112))),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error, side: BorderSide(color: theme.colorScheme.error)),
            onPressed: _loggingOut ? null : _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }

  String _syncText(SyncState sync) {
    if (!sync.online) {
      return sync.pending > 0 ? 'Hors ligne · ${sync.pending} modification${sync.pending > 1 ? 's' : ''} en attente' : 'Hors ligne';
    }
    final parts = <String>[
      if (sync.pending > 0) '${sync.pending} en attente d\'envoi',
      if (sync.lastSyncAt != null) 'Dernière synchronisation : ${formatDate(sync.lastSyncAt!)} à ${formatTime(sync.lastSyncAt!)}' else 'Pas encore synchronisé',
    ];
    return parts.join(' · ');
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await ref.read(backendApiProvider).exportHistory();
      await ref.read(fileSharerProvider).share(fileName: file.fileName, bytes: file.bytes, mimeType: 'text/csv');
    } on Object catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportMyData() async {
    setState(() => _exportingData = true);
    try {
      final file = await ref.read(backendApiProvider).exportMyData();
      await ref.read(fileSharerProvider).share(fileName: file.fileName, bytes: file.bytes, mimeType: 'application/json');
    } on Object catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _exportingData = false);
    }
  }

  Future<void> _logout() async {
    final ok = await confirm(
      context,
      title: 'Se déconnecter ?',
      message: 'Vos données restent sauvegardées sur nos serveurs et reviendront à votre prochaine connexion. '
          'Elles seront effacées de ce téléphone.',
      confirmLabel: 'Se déconnecter',
    );
    if (!ok || !mounted) return;
    setState(() => _loggingOut = true);
    try {
      // Envoyer d'abord ce qui peut l'être : rien n'est perdu si le réseau est là.
      await ref.read(syncControlProvider).syncNow();
      final notifier = ref.read(sessionProvider.notifier);
      final result = await notifier.logout();
      if (result is LogoutBlocked) {
        if (!mounted) return;
        final force = await confirm(
          context,
          title: 'Données non envoyées',
          message: '${result.unsyncedCount} modification${result.unsyncedCount > 1 ? 's' : ''} n\'${result.unsyncedCount > 1 ? 'ont' : 'a'} '
              'pas encore été envoyée${result.unsyncedCount > 1 ? 's' : ''} au serveur. Connectez-vous à internet pour les envoyer, '
              'ou déconnectez-vous maintenant et ${result.unsyncedCount > 1 ? 'les' : 'la'} perdre.',
          confirmLabel: 'Déconnecter et perdre',
          destructive: true,
        );
        if (!force || !mounted) return;
        await notifier.logout(force: true);
      }
    } on Object catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip({required this.isPremium, required this.expiresAt, required this.now});

  final bool isPremium;
  final DateTime? expiresAt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final color = isPremium ? Brand.ochre : Theme.of(context).colorScheme.primary;
    final label = isPremium
        ? (expiresAt == null ? 'Premium' : 'Premium jusqu\'au ${formatDate(expiresAt!)}')
        : 'Plan gratuit';
    return Semantics(
      label: 'Abonnement : $label',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(isPremium ? Icons.workspace_premium : Icons.person_outline, size: 16, color: color),
              const SizedBox(width: 4),
              Flexible(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, this.subtitle, this.onTap, this.action, this.trailing, this.iconColor});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Bouton placé sous le texte (reste lisible quand le texte est agrandi).
  final Widget? action;
  final Widget? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: iconColor)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodyMedium),
                    if (action != null) Align(alignment: Alignment.centerLeft, child: action),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.chevron_right)),
            ],
          ),
        ),
      ),
    );
  }
}
