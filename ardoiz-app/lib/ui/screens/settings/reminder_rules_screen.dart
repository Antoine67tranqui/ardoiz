import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../data/remote/backend_api.dart';
import '../../widgets/common.dart';

/// Relances automatiques (Premium) : quand et sur quel ton relancer les clients.
class ReminderRulesScreen extends ConsumerWidget {
  const ReminderRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Relances automatiques')),
      body: !isPremium
          ? EmptyState(
              icon: Icons.workspace_premium_outlined,
              title: 'Réservé à Premium',
              message: 'Avec Premium, Carné envoie un SMS à vos clients avant et après l\'échéance, sans que vous ayez à y penser.',
              action: BusyButton(label: 'Découvrir Premium', onPressed: () => context.push(Routes.subscription)),
            )
          : const _Rules(),
    );
  }
}

String describeOffset(int offsetDays) {
  if (offsetDays == 0) return 'Le jour de l\'échéance';
  final days = offsetDays.abs();
  final unit = days > 1 ? 'jours' : 'jour';
  return offsetDays < 0 ? '$days $unit avant l\'échéance' : '$days $unit après l\'échéance';
}

class _Rules extends ConsumerStatefulWidget {
  const _Rules();

  @override
  ConsumerState<_Rules> createState() => _RulesState();
}

class _RulesState extends ConsumerState<_Rules> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(reminderRulesProvider);
    } on Object catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({required int offsetDays, required ReminderTone tone, required bool enabled}) => _run(
        () => ref.read(backendApiProvider).saveReminderRule(
              offsetDays: offsetDays,
              channel: ReminderChannel.sms,
              tone: tone,
              enabled: enabled,
            ),
      );

  Future<void> _add() async {
    final rule = await showModalBottomSheet<({int offsetDays, ReminderTone tone})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _AddRuleSheet(),
    );
    if (rule != null) await _save(offsetDays: rule.offsetDays, tone: rule.tone, enabled: true);
  }

  Future<void> _delete(ReminderRule rule) async {
    final ok = await confirm(
      context,
      title: 'Supprimer cette relance ?',
      message: '« ${describeOffset(rule.offsetDays)} » ne sera plus envoyée.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (ok && mounted) await _run(() => ref.read(backendApiProvider).deleteReminderRule(rule.id));
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(reminderRulesProvider);
    return rules.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Relances indisponibles',
        message: describeError(error),
        action: BusyButton(label: 'Réessayer', onPressed: () => ref.invalidate(reminderRulesProvider)),
      ),
      data: (list) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'Chaque jour, Carné envoie un SMS pour les dettes non soldées dont l\'échéance correspond. '
              'Une même relance n\'est jamais envoyée deux fois pour la même dette.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (list.isEmpty)
            const EmptyState(icon: Icons.notifications_off_outlined, title: 'Aucune relance', message: 'Ajoutez une première relance.'),
          for (final rule in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(describeOffset(rule.offsetDays), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text('SMS · ton ${rule.tone.label.toLowerCase()}', style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    Switch(
                      value: rule.enabled,
                      onChanged: _busy ? null : (value) => _save(offsetDays: rule.offsetDays, tone: rule.tone, enabled: value),
                    ),
                    IconButton(
                      tooltip: 'Supprimer cette relance',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy ? null : () => _delete(rule),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _busy ? null : _add, icon: const Icon(Icons.add), label: const Text('Ajouter une relance')),
        ],
      ),
    );
  }
}

class _AddRuleSheet extends StatefulWidget {
  const _AddRuleSheet();

  @override
  State<_AddRuleSheet> createState() => _AddRuleSheetState();
}

enum _When { before, onDay, after }

class _AddRuleSheetState extends State<_AddRuleSheet> {
  _When _when = _When.after;
  int _days = 3;
  ReminderTone _tone = ReminderTone.neutral;

  int get _offset => switch (_when) {
        _When.before => -_days,
        _When.onDay => 0,
        _When.after => _days,
      };

  int get _maxDays => _when == _When.before ? 30 : 60;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Ajouter une relance', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            SegmentedButton<_When>(
              segments: const <ButtonSegment<_When>>[
                ButtonSegment<_When>(value: _When.before, label: Text('Avant')),
                ButtonSegment<_When>(value: _When.onDay, label: Text('Le jour J')),
                ButtonSegment<_When>(value: _When.after, label: Text('Après')),
              ],
              selected: <_When>{_when},
              onSelectionChanged: (value) => setState(() {
                _when = value.first;
                if (_days > _maxDays) _days = _maxDays;
              }),
            ),
            if (_when != _When.onDay) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton.filledTonal(tooltip: 'Un jour de moins', icon: const Icon(Icons.remove), onPressed: _days > 1 ? () => setState(() => _days--) : null),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('$_days jour${_days > 1 ? 's' : ''}', style: theme.textTheme.titleLarge),
                  ),
                  IconButton.filledTonal(tooltip: 'Un jour de plus', icon: const Icon(Icons.add), onPressed: _days < _maxDays ? () => setState(() => _days++) : null),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('Ton du message', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final tone in ReminderTone.values)
                  ChoiceChip(label: Text(tone.label), selected: tone == _tone, onSelected: (_) => setState(() => _tone = tone)),
              ],
            ),
            const SizedBox(height: 16),
            Text(describeOffset(_offset), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            BusyButton(label: 'Ajouter', onPressed: () => Navigator.of(context).pop((offsetDays: _offset, tone: _tone))),
          ],
        ),
      ),
    );
  }
}
