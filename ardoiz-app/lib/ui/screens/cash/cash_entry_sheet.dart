import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/dates.dart';
import '../../../core/formatters.dart';
import '../../../core/money.dart';
import '../../../core/validators.dart';
import '../../../domain/models.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

/// Saisie d'une vente ou d'une dépense ([existing] : modification). Renvoie vrai si enregistré ou supprimé.
Future<bool> showCashEntrySheet(BuildContext context, {required CashType type, CashEntry? existing}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => CashEntrySheet(type: type, existing: existing),
  );
  return done ?? false;
}

class CashEntrySheet extends ConsumerStatefulWidget {
  const CashEntrySheet({super.key, required this.type, this.existing});

  final CashType type;
  final CashEntry? existing;

  @override
  ConsumerState<CashEntrySheet> createState() => _CashEntrySheetState();
}

class _CashEntrySheetState extends ConsumerState<CashEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _label = TextEditingController();
  late String _category;
  late DateTime _date;
  String? _error;

  bool get _editing => widget.existing != null;
  bool get _expense => widget.type == CashType.expense;

  List<String> get _categories {
    final base = _expense ? defaultExpenseCategories : defaultDebtCategories;
    return <String>{...base, _category}.toList();
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final now = ref.read(clockProvider)();
    _category = existing?.category ?? (_expense ? defaultExpenseCategories.first : fallbackDebtCategory);
    _date = localDateOnly(existing?.occurredAt ?? now);
    if (existing != null) {
      _amount.text = formatMoneyInput(existing.amount);
      _label.text = existing.label ?? '';
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _label.dispose();
    super.dispose();
  }

  DateTime get _today => localDateOnly(ref.read(clockProvider)());

  Future<void> _pickDate() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
      helpText: 'Date de l\'opération',
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// Une opération du jour garde l'heure réelle ; une autre date est placée à midi.
  DateTime _occurredAt() {
    final now = ref.read(clockProvider)();
    if (_date == localDateOnly(now)) return now;
    return DateTime(_date.year, _date.month, _date.day, 12);
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(repositoryProvider);
    final amount = Money.tryParse(_amount.text)!;
    try {
      final existing = widget.existing;
      if (existing == null) {
        repo.addCashEntry(type: widget.type, amount: amount, label: _label.text, category: _category, occurredAt: _occurredAt());
      } else {
        final dateChanged = _date != localDateOnly(existing.occurredAt);
        repo.updateCashEntry(
          existing.id,
          amount: amount,
          label: _label.text,
          clearLabel: _label.text.trim().isEmpty,
          category: _category,
          occurredAt: dateChanged ? _occurredAt() : null,
        );
      }
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      setState(() => _error = describeError(e));
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Supprimer cette écriture ?',
      message: 'Elle sera retirée de votre caisse. Cette action est définitive.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok || !mounted) return;
    ref.read(repositoryProvider).deleteCashEntry(widget.existing!.id);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _today;
    final title = '${_editing ? 'Modifier' : 'Nouvelle'} ${_expense ? 'dépense' : 'vente'}';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                decoration: const InputDecoration(labelText: 'Montant', suffixText: 'FCFA'),
                validator: Validators.amount,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _label,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: 'Libellé (facultatif)', hintText: _expense ? 'Ex. : Taxi pour le marché' : 'Ex. : 3 sacs de riz'),
                validator: Validators.cashLabel,
              ),
              const SectionTitle('Catégorie'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final category in _categories)
                    ChoiceChip(label: Text(category), selected: category == _category, onSelected: (_) => setState(() => _category = category)),
                ],
              ),
              const SectionTitle('Date'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  ChoiceChip(label: const Text('Aujourd\'hui'), selected: _date == today, onSelected: (_) => setState(() => _date = today)),
                  ChoiceChip(
                    label: const Text('Hier'),
                    selected: _date == today.subtract(const Duration(days: 1)),
                    onSelected: (_) => setState(() => _date = today.subtract(const Duration(days: 1))),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text(_date == today || _date == today.subtract(const Duration(days: 1)) ? 'Autre date' : formatDate(_date)),
                    onPressed: _pickDate,
                  ),
                ],
              ),
              if (_error != null) ...<Widget>[const SizedBox(height: 12), FormErrorBanner(_error!)],
              const SizedBox(height: 16),
              BusyButton(label: 'Enregistrer', icon: Icons.check, onPressed: _save),
              if (_editing) ...<Widget>[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer cette écriture'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
