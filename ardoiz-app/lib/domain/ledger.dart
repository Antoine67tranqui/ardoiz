import 'models.dart';
import '../core/money.dart';

const int _dayMs = 24 * 60 * 60 * 1000;

/// Calculs métier purs (sans I/O), identiques côté serveur : le statut d'une
/// dette est déduit de ses paiements, le solde d'un client est la somme du
/// RESTANT à payer de ses dettes non soldées.
class Ledger {
  const Ledger._();

  static DebtStatus statusOf(Money amount, Money paid) {
    if (paid >= amount) return DebtStatus.paid;
    if (paid.isPositive) return DebtStatus.partial;
    return DebtStatus.pending;
  }

  /// Jours de retard : 0 tant que l'échéance n'est pas dépassée de 24 h
  /// (même règle que le tableau de bord du backend).
  static int overdueDays(DateTime? dueDate, DateTime now) {
    if (dueDate == null || !dueDate.isBefore(now)) return 0;
    return (now.millisecondsSinceEpoch - dueDate.millisecondsSinceEpoch) ~/ _dayMs;
  }

  static DebtView debtView(
    Debt debt,
    List<Payment> payments,
    DateTime now, {
    bool pendingSync = false,
  }) {
    final paid = Money.sum(payments.map((p) => p.amount));
    final remaining = (debt.amount - paid).clampedAtZero;
    final status = statusOf(debt.amount, paid);
    final overdue = status == DebtStatus.paid ? 0 : _overdue(debt.dueDate, now);
    return DebtView(
      debt: debt,
      payments: List.unmodifiable(payments),
      paid: paid,
      remaining: remaining,
      status: status,
      overdueDays: overdue,
      pendingSync: pendingSync,
    );
  }

  // Une dette échue depuis moins d'un jour est déjà "en retard" à l'affichage
  // (1 jour minimum) : contrairement au tableau de bord serveur qui compte des
  // jours entiers, le commerçant veut voir le badge dès l'échéance dépassée.
  static int _overdue(DateTime? dueDate, DateTime now) {
    if (dueDate == null || !dueDate.isBefore(now)) return 0;
    final days = overdueDays(dueDate, now);
    return days == 0 ? 1 : days;
  }

  /// [pendingIds] : identifiants d'entités ayant des envois en attente.
  static List<CustomerView> customerViews({
    required List<Customer> customers,
    required List<Debt> debts,
    required List<Payment> payments,
    required Set<String> pendingIds,
    required DateTime now,
  }) {
    final paymentsByDebt = <String, List<Payment>>{};
    for (final payment in payments) {
      paymentsByDebt.putIfAbsent(payment.debtId, () => <Payment>[]).add(payment);
    }
    final debtsByCustomer = <String, List<Debt>>{};
    for (final debt in debts) {
      debtsByCustomer.putIfAbsent(debt.customerId, () => <Debt>[]).add(debt);
    }

    return customers.map((customer) {
      final debtViews = (debtsByCustomer[customer.id] ?? const <Debt>[]).map((debt) {
        final debtPayments = paymentsByDebt[debt.id] ?? const <Payment>[];
        final pending = pendingIds.contains(debt.id) || debtPayments.any((p) => pendingIds.contains(p.id));
        return debtView(debt, debtPayments, now, pendingSync: pending);
      }).toList()
        ..sort((a, b) => b.debt.createdAt.compareTo(a.debt.createdAt));

      final outstanding = Money.sum(debtViews.map((d) => d.remaining));
      final limit = customer.creditLimit;
      return CustomerView(
        customer: customer,
        debts: List.unmodifiable(debtViews),
        outstanding: outstanding,
        maxOverdueDays: debtViews.fold<int>(0, (m, d) => d.overdueDays > m ? d.overdueDays : m),
        creditLimitExceeded: limit != null && outstanding > limit,
        pendingSync: pendingIds.contains(customer.id) || debtViews.any((d) => d.pendingSync),
      );
    }).toList();
  }
}
