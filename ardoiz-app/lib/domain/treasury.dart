import 'package:flutter/foundation.dart';

import '../core/money.dart';
import 'models.dart';

@immutable
class ExpenseCategoryTotal {
  const ExpenseCategoryTotal({required this.category, required this.total});

  final String category;
  final Money total;
}

/// Argent réellement entré et sorti sur une période (calculé sur l'appareil, hors
/// ligne). Mêmes règles que `GET /cash/summary` du serveur :
/// - entrées = ventes au comptant + remboursements reçus de clients ;
/// - sorties = dépenses + paiements faits aux fournisseurs.
/// Une dette accordée à un client ou un achat à crédit ne bouge pas la caisse
/// tant qu'il n'est pas payé : ils sont indiqués à part.
@immutable
class TreasurySummary {
  const TreasurySummary({
    required this.sales,
    required this.collected,
    required this.expenses,
    required this.paidToSuppliers,
    required this.creditGranted,
    required this.creditReceived,
    required this.expensesByCategory,
  });

  final Money sales;
  final Money collected;
  final Money expenses;
  final Money paidToSuppliers;

  /// Crédit accordé aux clients sur la période (n'a pas touché la caisse).
  final Money creditGranted;

  /// Achats à crédit chez des fournisseurs sur la période (n'ont pas touché la caisse).
  final Money creditReceived;
  final List<ExpenseCategoryTotal> expensesByCategory;

  Money get cashIn => sales + collected;
  Money get cashOut => expenses + paidToSuppliers;
  Money get net => cashIn - cashOut;
  bool get isEmpty =>
      cashIn.isZero && cashOut.isZero && creditGranted.isZero && creditReceived.isZero;
}

class TreasuryCalculator {
  const TreasuryCalculator._();

  /// Période [from, to) (bornes en temps absolu).
  static TreasurySummary compute({
    required List<CustomerView> customers,
    required List<CashEntry> cashEntries,
    required DateTime from,
    required DateTime to,
  }) {
    bool inRange(DateTime d) => !d.isBefore(from) && d.isBefore(to);

    var sales = Money.zero;
    var expenses = Money.zero;
    final byCategory = <String, Money>{};
    for (final e in cashEntries) {
      if (!inRange(e.occurredAt)) continue;
      if (e.type == CashType.sale) {
        sales += e.amount;
      } else {
        expenses += e.amount;
        byCategory[e.category] = (byCategory[e.category] ?? Money.zero) + e.amount;
      }
    }

    var collected = Money.zero;
    var paidToSuppliers = Money.zero;
    var creditGranted = Money.zero;
    var creditReceived = Money.zero;
    for (final customer in customers) {
      for (final view in customer.debts) {
        if (inRange(view.debt.createdAt)) {
          if (customer.customer.isSupplier) {
            creditReceived += view.debt.amount;
          } else {
            creditGranted += view.debt.amount;
          }
        }
        for (final payment in view.payments) {
          if (!inRange(payment.paidAt)) continue;
          if (customer.customer.isSupplier) {
            paidToSuppliers += payment.amount;
          } else {
            collected += payment.amount;
          }
        }
      }
    }

    final categories = byCategory.entries
        .map((e) => ExpenseCategoryTotal(category: e.key, total: e.value))
        .toList()
      ..sort((a, b) {
        final byTotal = b.total.compareTo(a.total);
        return byTotal != 0 ? byTotal : a.category.compareTo(b.category);
      });

    return TreasurySummary(
      sales: sales,
      collected: collected,
      expenses: expenses,
      paidToSuppliers: paidToSuppliers,
      creditGranted: creditGranted,
      creditReceived: creditReceived,
      expensesByCategory: categories,
    );
  }

  /// Mois civil local : [1er du mois, 1er du mois suivant).
  static (DateTime, DateTime) monthRange(DateTime anyDayInMonth) {
    final local = anyDayInMonth.toLocal();
    return (DateTime(local.year, local.month), DateTime(local.year, local.month + 1));
  }
}
