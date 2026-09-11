import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../customer_detail/providers/debts_provider.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final String debtId;
  final String customerId;
  final double amount;

  const PaymentScreen({
    super.key,
    required this.debtId,
    required this.customerId,
    required this.amount,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _amountController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.amount.toStringAsFixed(0);
  }

  Future<void> _recordCashPayment() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;

    setState(() => _loading = true);
    try {
      final repo = ref.read(debtRepositoryProvider);
      await repo.recordCashPayment(
        debtId: widget.debtId,
        customerId: widget.customerId,
        amount: amount,
      );
      ref.invalidate(debtsForCustomerProvider(widget.customerId));
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.decimalPattern('fr');

    return Scaffold(
      appBar: AppBar(title: const Text('Encaisser le remboursement')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Solde du : ${formatter.format(widget.amount)} FCFA',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            const Text('Montant recu'),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.payments_outlined),
              onPressed: _loading ? null : _recordCashPayment,
              label: const Text('Encaisser en especes'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.phone_android),
              onPressed: () => _showMobileMoneyInfo(context),
              label: const Text('Demander via Mobile Money'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMobileMoneyInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paiement Mobile Money'),
        content: const Text(
          'Le client recevra une demande de paiement Orange Money / MTN MoMo / '
          'Moov Money / Wave. La dette sera automatiquement mise a jour des '
          'confirmation du paiement.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Compris')),
        ],
      ),
    );
  }
}
