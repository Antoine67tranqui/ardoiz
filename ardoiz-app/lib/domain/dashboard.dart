import 'package:flutter/foundation.dart';

import '../core/money.dart';
import 'ledger.dart';
import 'models.dart';

const String _uncategorized = 'Autre';

@immutable
class CategoryBreakdown {
  const CategoryBreakdown({required this.category, required this.outstanding, required this.count});

  final String category;
  final Money outstanding;

  /// Dettes encore dues dans cette catégorie.
  final int count;
}

@immutable
class OverdueItem {
  const OverdueItem({
    required this.debtId,
    required this.customerId,
    required this.customerName,
    required this.outstanding,
    required this.daysOverdue,
    required this.category,
  });

  final String debtId;
  final String customerId;
  final String customerName;
  final Money outstanding;

  /// Jours entiers écoulés depuis l'échéance (0 : échue depuis moins de 24 h).
  final int daysOverdue;
  final String category;
}

@immutable
class AtRiskCustomer {
  const AtRiskCustomer({
    required this.customerId,
    required this.customerName,
    required this.overdueCount,
    required this.overdueAmount,
    required this.maxDaysOverdue,
  });

  final String customerId;
  final String customerName;
  final int overdueCount;
  final Money overdueAmount;
  final int maxDaysOverdue;
}

@immutable
class TrendPoint {
  const TrendPoint({required this.month, required this.granted, required this.recovered});

  /// « 2026-10 ».
  final String month;
  final Money granted;
  final Money recovered;
}

@immutable
class DashboardSummary {
  const DashboardSummary({
    required this.totalOutstanding,
    required this.totalCustomers,
    required this.customersWithDebt,
    required this.byCategory,
    required this.overdue,
    required this.atRisk,
    required this.trend,
    this.recoveryRate,
    this.totalPayable = Money.zero,
    this.payableOverdue = Money.zero,
    this.suppliersWithDebt = 0,
  });

  final Money totalOutstanding;
  final int totalCustomers;
  final int customersWithDebt;
  final List<CategoryBreakdown> byCategory;
  final List<OverdueItem> overdue;
  final List<AtRiskCustomer> atRisk;
  final List<TrendPoint> trend;

  /// Part des dettes soldées payées à temps (0 à 1), null si aucune dette soldée.
  final double? recoveryRate;

  /// Ce que je dois aux fournisseurs (reste à payer), dont la part déjà échue.
  final Money totalPayable;
  final Money payableOverdue;
  final int suppliersWithDebt;
}

/// Tableau de bord calculé sur l'appareil à partir du carnet local : disponible
/// hors connexion. Mêmes règles que `GET /dashboard/summary` du serveur (vérifié
/// par le test d'intégration contre le vrai backend).
class DashboardCalculator {
  const DashboardCalculator._();

  static const int trendMonths = 6;

  static DashboardSummary compute(List<CustomerView> allParties, DateTime now) {
    // Les indicateurs portent sur les CLIENTS (ce qu'on me doit) ; ce que je
    // dois aux fournisseurs est totalisé à part.
    final customers = allParties.where((c) => !c.customer.isSupplier).toList();
    var payable = Money.zero;
    var payableOverdue = Money.zero;
    final suppliersWithDebt = <String>{};
    for (final supplier in allParties.where((c) => c.customer.isSupplier)) {
      for (final view in supplier.debts) {
        if (!view.remaining.isPositive) continue;
        payable += view.remaining;
        suppliersWithDebt.add(supplier.customer.id);
        final due = view.debt.dueDate;
        if (due != null && due.isBefore(now)) payableOverdue += view.remaining;
      }
    }

    var total = Money.zero;
    final withDebt = <String>{};
    final categories = <String, ({Money outstanding, int count})>{};
    final overdue = <OverdueItem>[];
    var paidDebts = 0;
    var paidOnTime = 0;

    for (final customer in customers) {
      for (final view in customer.debts) {
        final debt = view.debt;
        total += view.remaining;
        if (view.remaining.isPositive) withDebt.add(customer.customer.id);

        final category = debt.category.isEmpty ? _uncategorized : debt.category;
        final entry = categories[category] ?? (outstanding: Money.zero, count: 0);
        categories[category] = (
          outstanding: entry.outstanding + view.remaining,
          count: entry.count + (view.remaining.isPositive ? 1 : 0),
        );

        final due = debt.dueDate;
        if (view.remaining.isPositive && due != null && due.isBefore(now)) {
          overdue.add(OverdueItem(
            debtId: debt.id,
            customerId: customer.customer.id,
            customerName: customer.customer.name,
            outstanding: view.remaining,
            daysOverdue: Ledger.overdueDays(due, now),
            category: category,
          ));
        }

        if (view.status == DebtStatus.paid) {
          paidDebts++;
          DateTime? last;
          for (final payment in view.payments) {
            if (last == null || payment.paidAt.isAfter(last)) last = payment.paidAt;
          }
          if (due == null || last == null || !last.isAfter(due)) paidOnTime++;
        }
      }
    }

    // Ordre total (jours, puis nom, puis identifiant) : même affichage à chaque calcul.
    overdue.sort((a, b) {
      final byDays = b.daysOverdue.compareTo(a.daysOverdue);
      if (byDays != 0) return byDays;
      final byName = a.customerName.compareTo(b.customerName);
      return byName != 0 ? byName : a.debtId.compareTo(b.debtId);
    });
    final atRisk = _atRisk(overdue);

    final byCategory = categories.entries
        .map((e) => CategoryBreakdown(category: e.key, outstanding: e.value.outstanding, count: e.value.count))
        .toList()
      ..sort((a, b) {
        final byAmount = b.outstanding.compareTo(a.outstanding);
        return byAmount != 0 ? byAmount : a.category.compareTo(b.category);
      });

    return DashboardSummary(
      totalOutstanding: total,
      totalCustomers: customers.length,
      customersWithDebt: withDebt.length,
      byCategory: byCategory,
      overdue: overdue,
      atRisk: atRisk,
      trend: _trend(customers, now),
      recoveryRate: paidDebts == 0 ? null : paidOnTime / paidDebts,
      totalPayable: payable,
      payableOverdue: payableOverdue,
      suppliersWithDebt: suppliersWithDebt.length,
    );
  }

  static List<AtRiskCustomer> _atRisk(List<OverdueItem> overdue) {
    final byCustomer = <String, List<OverdueItem>>{};
    for (final item in overdue) {
      byCustomer.putIfAbsent(item.customerId, () => <OverdueItem>[]).add(item);
    }
    final result = byCustomer.entries.map((e) {
      final items = e.value;
      return AtRiskCustomer(
        customerId: e.key,
        customerName: items.first.customerName,
        overdueCount: items.length,
        overdueAmount: Money.sum(items.map((i) => i.outstanding)),
        maxDaysOverdue: items.fold<int>(0, (m, i) => i.daysOverdue > m ? i.daysOverdue : m),
      );
    }).toList()
      ..sort((a, b) {
        final byCount = b.overdueCount.compareTo(a.overdueCount);
        if (byCount != 0) return byCount;
        final byDays = b.maxDaysOverdue.compareTo(a.maxDaysOverdue);
        return byDays != 0 ? byDays : a.customerName.compareTo(b.customerName);
      });
    return result;
  }

  /// Crédit accordé et remboursements reçus, mois civils locaux, du plus ancien au courant.
  static List<TrendPoint> _trend(List<CustomerView> customers, DateTime now) {
    final local = now.toLocal();
    final points = <TrendPoint>[];
    for (var i = trendMonths - 1; i >= 0; i--) {
      final start = DateTime(local.year, local.month - i);
      final end = DateTime(local.year, local.month - i + 1);
      var granted = Money.zero;
      var recovered = Money.zero;
      for (final customer in customers) {
        for (final view in customer.debts) {
          final created = view.debt.createdAt.toLocal();
          if (!created.isBefore(start) && created.isBefore(end)) granted += view.debt.amount;
          for (final payment in view.payments) {
            final paid = payment.paidAt.toLocal();
            if (!paid.isBefore(start) && paid.isBefore(end)) recovered += payment.amount;
          }
        }
      }
      points.add(TrendPoint(
        month: '${start.year}-${start.month.toString().padLeft(2, '0')}',
        granted: granted,
        recovered: recovered,
      ));
    }
    return points;
  }
}
