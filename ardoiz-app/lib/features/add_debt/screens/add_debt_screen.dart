import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../customer_detail/providers/debts_provider.dart';

class AddDebtScreen extends ConsumerStatefulWidget {
  final String customerId;
  const AddDebtScreen({super.key, required this.customerId});

  @override
  ConsumerState<AddDebtScreen> createState() => _AddDebtScreenState();
}

class _AddDebtScreenState extends ConsumerState<AddDebtScreen> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  DateTime? _dueDate;
  bool _loading = false;

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;

    setState(() => _loading = true);
    try {
      final repo = ref.read(debtRepositoryProvider);
      await repo.create(
        customerId: widget.customerId,
        amount: amount,
        reason: _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
        dueDate: _dueDate,
      );
      ref.invalidate(debtsForCustomerProvider(widget.customerId));
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle ardoise')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Montant (FCFA)'),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(hintText: '2500'),
            ),
            const SizedBox(height: 20),
            const Text('Motif (optionnel)'),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(hintText: 'Ex: Riz + huile'),
            ),
            const SizedBox(height: 20),
            const Text("Date d'echeance (optionnelle)"),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                _dueDate == null
                    ? 'Choisir une date'
                    : '${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
              ),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
