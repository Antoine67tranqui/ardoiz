import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/dates.dart';
import '../../../core/formatters.dart';
import '../../../core/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models.dart';
import '../../../domain/treasury.dart';
import '../../widgets/common.dart';
import 'cash_entry_sheet.dart';

const List<String> _monthNames = <String>[
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// Caisse : ventes au comptant et dépenses, avec le bilan de l'argent entré et sorti du mois
/// (y compris les remboursements reçus de clients et les paiements faits aux fournisseurs).
class CashScreen extends ConsumerStatefulWidget {
  const CashScreen({super.key});

  @override
  ConsumerState<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends ConsumerState<CashScreen> {
  DateTime? _month;

  DateTime get _currentMonth => _month ?? TreasuryCalculator.monthRange(ref.read(clockProvider)()).$1;

  bool get _isCurrentMonth => _currentMonth == TreasuryCalculator.monthRange(ref.read(clockProvider)()).$1;

  void _shift(int delta) => setState(() => _month = DateTime(_currentMonth.year, _currentMonth.month + delta));

  Future<void> _add() async {
    final type = await showModalBottomSheet<CashType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Une vente au comptant'),
              subtitle: const Text('Un client a payé tout de suite'),
              onTap: () => Navigator.of(context).pop(CashType.sale),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Une dépense'),
              subtitle: const Text('Transport, loyer, marchandises payées comptant...'),
              onTap: () => Navigator.of(context).pop(CashType.expense),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    await showCashEntrySheet(context, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final month = _currentMonth;
    final summary = ref.watch(treasuryProvider(month));
    final entries = ref.watch(cashEntriesProvider).value;
    final (from, to) = TreasuryCalculator.monthRange(month);
    final monthEntries = (entries ?? const <CashEntry>[]).where((e) => !e.occurredAt.isBefore(from) && e.occurredAt.isBefore(to)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Caisse')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Ajouter')),
      body: summary == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: <Widget>[
                _MonthBar(
                  label: '${_monthNames[month.month - 1]} ${month.year}',
                  onPrevious: () => _shift(-1),
                  onNext: _isCurrentMonth ? null : () => _shift(1),
                ),
                const SizedBox(height: 8),
                _SummaryCard(summary),
                if (monthEntries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.point_of_sale_outlined,
                      title: 'Aucune vente ni dépense ce mois-ci',
                      message: 'Notez ici vos ventes payées comptant et vos dépenses. '
                          'Les remboursements de vos clients sont comptés automatiquement.',
                    ),
                  )
                else
                  ..._groupByDay(monthEntries).map((group) => _DayGroup(day: group.$1, entries: group.$2)),
              ],
            ),
    );
  }

  static List<(DateTime, List<CashEntry>)> _groupByDay(List<CashEntry> entries) {
    final byDay = <DateTime, List<CashEntry>>{};
    for (final e in entries) {
      byDay.putIfAbsent(localDateOnly(e.occurredAt), () => <CashEntry>[]).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return <(DateTime, List<CashEntry>)>[for (final d in days) (d, byDay[d]!)];
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.label, required this.onPrevious, required this.onNext});

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          IconButton(tooltip: 'Mois précédent', icon: const Icon(Icons.chevron_left), onPressed: onPrevious),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          IconButton(tooltip: 'Mois suivant', icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.summary);

  final TreasurySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.statusColors;
    final net = summary.net;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Argent gagné ce mois', style: theme.textTheme.labelLarge),
            Semantics(
              label: 'Solde du mois : ${formatMoney(net)}',
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(
                    net,
                    color: net.cents < 0 ? colors.overdue : colors.paid,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
            const Divider(height: 24),
            _Line('Ventes au comptant', summary.sales, plus: true),
            _Line('Remboursements reçus de clients', summary.collected, plus: true),
            _Line('Dépenses', summary.expenses, plus: false),
            _Line('Paiements à des fournisseurs', summary.paidToSuppliers, plus: false),
            if (summary.creditGranted.isPositive || summary.creditReceived.isPositive) ...<Widget>[
              const Divider(height: 24),
              if (summary.creditGranted.isPositive)
                Text('Crédit accordé à des clients ce mois (pas encore encaissé) : ${formatMoney(summary.creditGranted)}', style: theme.textTheme.bodySmall),
              if (summary.creditReceived.isPositive)
                Text('Achats à crédit chez des fournisseurs ce mois (pas encore payés) : ${formatMoney(summary.creditReceived)}', style: theme.textTheme.bodySmall),
            ],
            if (summary.expensesByCategory.isNotEmpty) ...<Widget>[
              const Divider(height: 24),
              Text('Dépenses par catégorie', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final c in summary.expensesByCategory) _Line(c.category, c.total, plus: null),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount, {required this.plus});

  final String label;
  final Money amount;

  /// Vrai : entrée (+) ; faux : sortie (-) ; null : neutre.
  final bool? plus;

  @override
  Widget build(BuildContext context) {
    final sign = plus == null ? '' : (plus! ? '+ ' : '- ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          AmountBox(amount, maxFraction: 0.5, style: const TextStyle(fontWeight: FontWeight.w700), color: null, prefix: sign),
        ],
      ),
    );
  }
}

class _DayGroup extends ConsumerWidget {
  const _DayGroup({required this.day, required this.entries});

  final DateTime day;
  final List<CashEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.statusColors;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionTitle('${_capitalized(formatRelativeDays(day, ref.read(clockProvider)()))} · ${formatDate(day)}'),
        for (final entry in entries)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => showCashEntrySheet(context, type: entry.type, existing: entry),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(entry.type == CashType.sale ? Icons.add_circle_outline : Icons.remove_circle_outline,
                        color: entry.type == CashType.sale ? colors.paid : colors.overdue, semanticLabel: entry.type.label),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text((entry.label ?? '').isEmpty ? entry.category : entry.label!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                          Text('${entry.type.label} · ${entry.category}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AmountBox(
                      entry.amount,
                      prefix: entry.type == CashType.sale ? '+ ' : '- ',
                      color: entry.type == CashType.sale ? colors.paid : colors.overdue,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _capitalized(String text) => text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
