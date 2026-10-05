import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/formatters.dart';
import '../../../core/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/dashboard.dart';
import '../../widgets/common.dart';

/// Tableau de bord Premium, calculé sur l'appareil (disponible hors connexion).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    final summary = ref.watch(dashboardProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tableau de bord')),
      body: !isPremium
          ? const _PremiumUpsell()
          : summary == null
              ? const Center(child: CircularProgressIndicator())
              : _Content(summary),
    );
  }
}

class _PremiumUpsell extends StatelessWidget {
  const _PremiumUpsell();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const SizedBox(height: 16),
          Icon(Icons.insights, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Gardez le contrôle de votre crédit',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Avec Premium, repérez en un coup d\'œil qui vous doit le plus, qui est en retard et comment évolue votre crédit.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const _Benefit(Icons.warning_amber_rounded, 'Les dettes en retard et les clients à risque'),
          const _Benefit(Icons.pie_chart_outline, 'La répartition de l\'argent dû par catégorie'),
          const _Benefit(Icons.trending_up, 'L\'évolution du crédit accordé et récupéré sur 6 mois'),
          const _Benefit(Icons.verified_outlined, 'Votre taux de recouvrement'),
          const _Benefit(Icons.groups_outlined, 'Plus de 15 clients et relances automatiques'),
          const SizedBox(height: 24),
          BusyButton(
            label: 'Découvrir Premium',
            icon: Icons.workspace_premium_outlined,
            onPressed: () => context.push(Routes.subscription),
          ),
        ],
      );
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      );
}

class _Content extends StatelessWidget {
  const _Content(this.summary);

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.totalCustomers == 0 && summary.suppliersWithDebt == 0) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: 'Rien à analyser pour le moment',
        message: 'Ajoutez des clients et des dettes : vos statistiques apparaîtront ici.',
      );
    }
    final categories = summary.byCategory.where((c) => c.outstanding.isPositive).toList();
    final overdue = summary.overdue;
    final overdueTotal = Money.sum(overdue.map((o) => o.outstanding));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _Kpi(label: 'À encaisser', value: formatMoney(summary.totalOutstanding), icon: Icons.account_balance_wallet_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: _Kpi(
                label: 'Clients qui doivent',
                value: '${summary.customersWithDebt} / ${summary.totalCustomers}',
                icon: Icons.people_outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _Kpi(
                label: 'En retard',
                value: overdue.isEmpty ? 'Aucun' : formatMoney(overdueTotal),
                icon: Icons.warning_amber_rounded,
                alert: overdue.isNotEmpty,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Kpi(
                label: 'Payé à temps',
                value: summary.recoveryRate == null ? 'Pas encore' : '${(summary.recoveryRate! * 100).round()} %',
                icon: Icons.verified_outlined,
                hint: summary.recoveryRate == null ? 'Aucune dette soldée' : 'des dettes soldées',
              ),
            ),
          ],
        ),
        if (summary.suppliersWithDebt > 0) ...<Widget>[
          const SizedBox(height: 12),
          _Kpi(
            label: 'À payer aux fournisseurs',
            value: formatMoney(summary.totalPayable),
            icon: Icons.local_shipping_outlined,
            alert: summary.payableOverdue.isPositive,
            hint: summary.payableOverdue.isPositive
                ? 'dont ${formatMoney(summary.payableOverdue)} déjà échu'
                : '${summary.suppliersWithDebt} fournisseur${summary.suppliersWithDebt > 1 ? 's' : ''}',
          ),
        ],
        if (summary.atRisk.isNotEmpty) ...<Widget>[
          const SectionTitle('Clients à surveiller'),
          for (final risk in summary.atRisk.take(5)) _AtRiskTile(risk),
        ],
        if (overdue.isNotEmpty) ...<Widget>[
          SectionTitle('Dettes en retard (${overdue.length})'),
          for (final item in overdue.take(10)) _OverdueTile(item),
          if (overdue.length > 10)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('… et ${overdue.length - 10} autres', style: Theme.of(context).textTheme.bodyMedium),
            ),
        ],
        if (categories.isNotEmpty) ...<Widget>[
          const SectionTitle('Argent dû par catégorie'),
          _CategoryBars(categories),
        ],
        const SectionTitle('Évolution sur 6 mois'),
        _TrendRows(summary.trend),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.icon, this.alert = false, this.hint});

  final String label;
  final String value;
  final IconData icon;
  final bool alert;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = alert ? context.statusColors.overdue : theme.colorScheme.primary;
    return Semantics(
      container: true,
      label: '$label : $value${hint == null ? '' : ', $hint'}',
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
                ]),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: alert ? color : null,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ),
                if (hint != null) Text(hint!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AtRiskTile extends StatelessWidget {
  const _AtRiskTile(this.risk);

  final AtRiskCustomer risk;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(Routes.customer(risk.customerId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              AppAvatar(risk.customerName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(risk.customerName, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '${risk.overdueCount} dette${risk.overdueCount > 1 ? 's' : ''} en retard · jusqu\'à ${_days(risk.maxDaysOverdue)}',
                      style: TextStyle(color: colors.overdue, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AmountBox(risk.overdueAmount, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverdueTile extends StatelessWidget {
  const _OverdueTile(this.item);

  final OverdueItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(Routes.debt(item.debtId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(item.customerName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Row(children: <Widget>[
                      Icon(Icons.warning_amber_rounded, size: 16, color: colors.overdue),
                      const SizedBox(width: 4),
                      Flexible(child: Text('${_days(item.daysOverdue)} de retard · ${item.category}', style: TextStyle(color: colors.overdue))),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AmountBox(item.outstanding, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

String _days(int days) => days < 1 ? 'moins d\'un jour' : '$days jour${days > 1 ? 's' : ''}';

/// Barres horizontales : lisibles à toute taille de texte, valeurs toujours écrites.
class _CategoryBars extends StatelessWidget {
  const _CategoryBars(this.categories);

  final List<CategoryBreakdown> categories;

  @override
  Widget build(BuildContext context) {
    final max = categories.first.outstanding.cents;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            for (final c in categories)
              _BarRow(
                label: '${c.category} (${c.count})',
                amount: c.outstanding,
                fraction: max == 0 ? 0 : c.outstanding.cents / max,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _TrendRows extends StatelessWidget {
  const _TrendRows(this.trend);

  final List<TrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.statusColors;
    var max = 0;
    for (final t in trend) {
      if (t.granted.cents > max) max = t.granted.cents;
      if (t.recovered.cents > max) max = t.recovered.cents;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(spacing: 16, children: <Widget>[
              _Legend(theme.colorScheme.primary, 'Crédit accordé'),
              _Legend(colors.paid, 'Récupéré'),
            ]),
            const SizedBox(height: 12),
            for (final t in trend) ...<Widget>[
              Text(_monthLabel(t.month), style: theme.textTheme.labelLarge),
              _BarRow(label: 'Accordé', amount: t.granted, fraction: max == 0 ? 0 : t.granted.cents / max, color: theme.colorScheme.primary, compact: true),
              _BarRow(label: 'Récupéré', amount: t.recovered, fraction: max == 0 ? 0 : t.recovered.cents / max, color: colors.paid, compact: true),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  static const List<String> _names = <String>[
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  static String _monthLabel(String month) {
    final parts = month.split('-');
    return '${_names[int.parse(parts[1]) - 1]} ${parts[0]}';
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.label, required this.amount, required this.fraction, required this.color, this.compact = false});

  final String label;
  final Money amount;
  final double fraction;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label : ${formatMoney(amount)}',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 2 : 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text(label, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  AmountBox(amount, maxFraction: 0.5, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  minHeight: compact ? 8 : 10,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
