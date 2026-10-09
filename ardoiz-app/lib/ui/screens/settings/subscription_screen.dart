import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatters.dart';
import '../../../data/remote/backend_api.dart';
import '../../widgets/common.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _busy = false;

  Future<void> _upgrade(SubscriptionStatus status) async {
    final ok = await confirm(
      context,
      title: 'Passer à Premium ?',
      message: 'Vous allez payer ${formatMoney(status.monthlyPrice)} par Mobile Money sur votre numéro. '
          'Premium dure 30 jours.',
      confirmLabel: 'Payer ${formatMoney(status.monthlyPrice)}',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(backendApiProvider).upgrade();
      if (result.activated) await ref.read(sessionProvider.notifier).refreshProfile();
      ref.invalidate(subscriptionStatusProvider);
      if (mounted) showSnack(context, result.message);
    } on Object catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    await ref.read(sessionProvider.notifier).refreshProfile();
    ref.invalidate(subscriptionStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(subscriptionStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Abonnement')),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Abonnement indisponible',
          message: describeError(error),
          action: BusyButton(label: 'Réessayer', onPressed: () => ref.invalidate(subscriptionStatusProvider)),
        ),
        data: (status) => RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              _CurrentPlan(status),
              const SectionTitle('Ce que vous obtenez'),
              const _Comparison(),
              const SizedBox(height: 24),
              BusyButton(
                label: status.plan == Plan.premium
                    ? 'Prolonger de 30 jours (${formatMoney(status.monthlyPrice)})'
                    : 'Passer à Premium (${formatMoney(status.monthlyPrice)} / mois)',
                icon: Icons.workspace_premium_outlined,
                busy: _busy,
                onPressed: status.paymentsAvailable ? () => _upgrade(status) : null,
              ),
              const SizedBox(height: 8),
              Text(
                status.paymentsAvailable
                    ? 'Paiement par Mobile Money. Pas de renouvellement automatique : vous décidez à chaque fois.'
                    : 'Le paiement de l\'abonnement n\'est pas encore ouvert. Revenez bientôt : vos données et le plan gratuit ne changent pas.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentPlan extends StatelessWidget {
  const _CurrentPlan(this.status);

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final premium = status.plan == Plan.premium;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Votre abonnement', style: theme.textTheme.labelLarge),
            Text(premium ? 'Premium' : 'Gratuit', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            if (premium && status.planExpiresAt != null) Text('Actif jusqu\'au ${formatDate(status.planExpiresAt!)}'),
            if (!premium)
              Text('${status.customerCount} client${status.customerCount > 1 ? 's' : ''} sur ${status.customerLimit ?? '∞'} autorisés'),
          ],
        ),
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison();

  static const List<(String, String, String)> _rows = <(String, String, String)>[
    ('Clients', '15 maximum', 'Illimités'),
    ('Dettes, paiements, relances manuelles', 'Inclus', 'Inclus'),
    ('Fonctionne sans internet', 'Inclus', 'Inclus'),
    ('Tableau de bord et clients à risque', 'Non', 'Inclus'),
    ('Relances automatiques par SMS', 'Non', 'Inclus'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Row(children: <Widget>[
              const Expanded(flex: 5, child: SizedBox()),
              Expanded(flex: 3, child: Text('Gratuit', style: theme.textTheme.labelLarge, textAlign: TextAlign.center)),
              Expanded(flex: 3, child: Text('Premium', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center)),
            ]),
            const Divider(),
            for (final row in _rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 5, child: Text(row.$1)),
                    Expanded(flex: 3, child: Text(row.$2, textAlign: TextAlign.center)),
                    Expanded(flex: 3, child: Text(row.$3, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
