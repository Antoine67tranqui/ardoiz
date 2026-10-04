import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatters.dart';
import '../../../core/money.dart';
import '../../../core/validators.dart';
import '../../../domain/models.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

/// Saisie d'un remboursement en espèces ; renvoie vrai si un paiement a été enregistré.
Future<bool> showPaymentSheet(BuildContext context, DebtView debt) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => PaymentSheet(debt: debt),
  );
  return saved ?? false;
}

class PaymentSheet extends ConsumerStatefulWidget {
  const PaymentSheet({super.key, required this.debt});

  final DebtView debt;

  @override
  ConsumerState<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<PaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  String? _error;

  Money get _remaining => widget.debt.remaining;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      ref.read(repositoryProvider).addPayment(debtId: widget.debt.debt.id, amount: Money.tryParse(_amount.text)!);
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Enregistrer un paiement', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Paiement reçu en espèces. Reste à payer : ${formatMoney(_remaining)}.', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                decoration: const InputDecoration(labelText: 'Montant reçu', suffixText: 'FCFA'),
                validator: (value) => Validators.amount(value, max: _remaining),
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  label: Text('Solde total (${formatMoney(_remaining)})'),
                  onPressed: () => _amount.text = formatMoneyInput(_remaining),
                ),
              ),
              if (_error != null) ...<Widget>[const SizedBox(height: 12), FormErrorBanner(_error!)],
              const SizedBox(height: 16),
              BusyButton(label: 'Enregistrer le paiement', icon: Icons.check, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
