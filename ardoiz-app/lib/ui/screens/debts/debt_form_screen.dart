import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/dates.dart';
import '../../../core/formatters.dart';
import '../../../core/money.dart';
import '../../../core/validators.dart';
import '../../../domain/models.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

/// Création d'une dette pour [customerId], ou modification de [debtId].
class DebtFormScreen extends ConsumerStatefulWidget {
  const DebtFormScreen({super.key, this.customerId, this.debtId}) : assert((customerId == null) != (debtId == null));

  final String? customerId;
  final String? debtId;

  @override
  ConsumerState<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends ConsumerState<DebtFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _category = fallbackDebtCategory;
  DateTime? _dueDate;
  bool _loaded = false;
  String? _error;

  bool get _editing => widget.debtId != null;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _load(DebtView view) {
    if (_loaded) return;
    _loaded = true;
    _amount.text = formatMoneyInput(view.debt.amount);
    _reason.text = view.debt.reason ?? '';
    _category = view.debt.category;
    _dueDate = view.debt.dueDate == null ? null : localDateOnly(view.debt.dueDate!);
  }

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider)();
    final today = localDateOnly(now);
    final initial = _dueDate ?? today.add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // Une dette déjà en retard peut être corrigée : on autorise un an en arrière.
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365 * 3)),
      helpText: 'Date d\'échéance',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _setInDays(int days) {
    final today = localDateOnly(ref.read(clockProvider)());
    setState(() => _dueDate = today.add(Duration(days: days)));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = Money.tryParse(_amount.text)!;
    final repo = ref.read(repositoryProvider);
    final due = _dueDate == null ? null : endOfLocalDay(_dueDate!);
    final reason = _reason.text.trim();

    try {
      if (_editing) {
        repo.updateDebt(
          widget.debtId!,
          amount: amount,
          reason: reason,
          clearReason: reason.isEmpty,
          category: _category,
          dueDate: due,
          clearDueDate: due == null,
        );
        context.pop();
        return;
      }

      final customer = ref.read(customerByIdProvider(widget.customerId!));
      final limit = customer?.customer.creditLimit;
      if (customer != null && limit != null && customer.outstanding + amount > limit) {
        final proceed = await confirm(
          context,
          title: 'Plafond de crédit dépassé',
          message: 'Avec cette dette, ${customer.customer.name} devra ${formatMoney(customer.outstanding + amount)} '
              'pour un plafond de ${formatMoney(limit)}. Voulez-vous quand même l\'enregistrer ?',
          confirmLabel: 'Enregistrer quand même',
        );
        if (!proceed || !mounted) return;
      }
      final debt = repo.addDebt(
        customerId: widget.customerId!,
        amount: amount,
        reason: reason,
        category: _category,
        dueDate: due,
      );
      if (!mounted) return;
      context.pushReplacement(Routes.debt(debt.id));
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      final loaded = ref.watch(customersProvider).hasValue;
      final view = ref.watch(debtByIdProvider(widget.debtId!));
      if (view == null) {
        return Scaffold(
          appBar: AppBar(),
          body: loaded
              ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Dette introuvable', message: 'Cette dette a été supprimée.')
              : const Center(child: CircularProgressIndicator()),
        );
      }
      _load(view);
    } else {
      final loaded = ref.watch(customersProvider).hasValue;
      if (loaded && ref.watch(customerByIdProvider(widget.customerId!)) == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const EmptyState(icon: Icons.person_off_outlined, title: 'Client introuvable', message: 'Ce client a été supprimé.'),
        );
      }
    }

    final partyId = _editing ? ref.watch(debtByIdProvider(widget.debtId!))?.debt.customerId : widget.customerId;
    final supplier = partyId != null && (ref.watch(customerByIdProvider(partyId))?.customer.isSupplier ?? false);
    final categories = <String>{...defaultDebtCategories, _category}.toList();
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? (supplier ? 'Modifier l\'achat' : 'Modifier la dette') : (supplier ? 'Nouvel achat à crédit' : 'Nouvelle dette'))),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              TextFormField(
                controller: _amount,
                autofocus: !_editing,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                decoration: InputDecoration(labelText: supplier ? 'Montant à payer' : 'Montant', suffixText: 'FCFA'),
                validator: Validators.amount,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                maxLines: 2,
                inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(500)],
                decoration: InputDecoration(labelText: 'Motif (facultatif)', hintText: supplier ? 'Ex. : 10 cartons de savon' : 'Ex. : 2 sacs de riz'),
                validator: Validators.reason,
              ),
              const SectionTitle('Catégorie'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final category in categories)
                    ChoiceChip(
                      label: Text(category),
                      selected: category == _category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                ],
              ),
              SectionTitle(supplier ? 'À payer avant le (facultatif)' : 'Échéance (facultatif)'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  ActionChip(label: const Text('7 jours'), onPressed: () => _setInDays(7)),
                  ActionChip(label: const Text('15 jours'), onPressed: () => _setInDays(15)),
                  ActionChip(label: const Text('30 jours'), onPressed: () => _setInDays(30)),
                  ActionChip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text(_dueDate == null ? 'Choisir une date' : formatDate(_dueDate!)),
                    onPressed: _pickDate,
                  ),
                  if (_dueDate != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _dueDate = null),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Sans échéance'),
                    ),
                ],
              ),
              if (_error != null) ...<Widget>[const SizedBox(height: 16), FormErrorBanner(_error!)],
              const SizedBox(height: 24),
              BusyButton(label: _editing ? 'Enregistrer' : (supplier ? 'Enregistrer l\'achat' : 'Enregistrer la dette'), icon: Icons.check, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
