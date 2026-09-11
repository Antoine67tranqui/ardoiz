import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/customer.dart';

class CustomerCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;

  const CustomerCard({super.key, required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.decimalPattern('fr');
    final hasDebt = customer.outstandingBalance > 0;
    final statusColor = hasDebt ? AppColors.statusPartial : AppColors.statusPaid;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name, style: Theme.of(context).textTheme.titleLarge),
                    if (customer.phone != null)
                      Text(customer.phone!, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Text(
                hasDebt ? '${formatter.format(customer.outstandingBalance)} FCFA' : 'A jour',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
