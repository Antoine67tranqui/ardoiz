import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/debt.dart';
import '../../../domain/models/debt_status.dart';

class DebtTile extends StatelessWidget {
  final Debt debt;
  final VoidCallback onPay;

  const DebtTile({super.key, required this.debt, required this.onPay});

  Color _statusColor() {
    switch (debt.status) {
      case DebtStatus.paid:
        return AppColors.statusPaid;
      case DebtStatus.partial:
        return AppColors.statusPartial;
      case DebtStatus.pending:
        final isOverdue = debt.dueDate != null && debt.dueDate!.isBefore(DateTime.now());
        return isOverdue ? AppColors.statusOverdue : AppColors.textSecondary;
    }
  }

  String _statusLabel() {
    switch (debt.status) {
      case DebtStatus.paid:
        return 'Remboursee';
      case DebtStatus.partial:
        return 'Partiellement remboursee';
      case DebtStatus.pending:
        return 'En attente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.decimalPattern('fr');
    final dateFormatter = DateFormat('dd/MM/yyyy');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatter.format(debt.amount)} FCFA',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (debt.reason != null) Text(debt.reason!),
                  Text(
                    dateFormatter.format(debt.createdAt),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusLabel(),
                    style: TextStyle(color: _statusColor(), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (debt.status != DebtStatus.paid)
              OutlinedButton(onPressed: onPay, child: const Text('Encaisser')),
          ],
        ),
      ),
    );
  }
}
