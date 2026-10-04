import 'package:flutter/foundation.dart';

import '../core/money.dart';

/// Moyen de remboursement (valeurs identiques à l'API : CASH / MOMO).
enum PaymentMethod {
  cash('CASH', 'Espèces'),
  momo('MOMO', 'Mobile Money');

  const PaymentMethod(this.wire, this.label);
  final String wire;
  final String label;

  static PaymentMethod fromWire(String value) =>
      PaymentMethod.values.firstWhere((m) => m.wire == value, orElse: () => PaymentMethod.cash);
}

/// Statut d'une dette, toujours déduit des paiements (jamais stocké).
enum DebtStatus { pending, partial, paid }

/// Catégories proposées à la saisie (le backend accepte tout texte ≤ 50 car.).
const List<String> defaultDebtCategories = <String>[
  'Alimentation',
  'Boissons',
  'Hygiène',
  'Ménage',
  'Autre',
];
const String fallbackDebtCategory = 'Autre';

@immutable
class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.createdAt,
    this.creditLimit,
  });

  final String id;
  final String name;
  final String phone;
  final Money? creditLimit;
  final DateTime createdAt;

  Customer copyWith({String? name, String? phone, Money? creditLimit, bool clearCreditLimit = false}) => Customer(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        creditLimit: clearCreditLimit ? null : (creditLimit ?? this.creditLimit),
        createdAt: createdAt,
      );
}

@immutable
class Debt {
  const Debt({
    required this.id,
    required this.customerId,
    required this.amount,
    required this.category,
    required this.createdAt,
    this.reason,
    this.dueDate,
  });

  final String id;
  final String customerId;
  final Money amount;
  final String? reason;
  final String category;
  final DateTime? dueDate;
  final DateTime createdAt;
}

@immutable
class Payment {
  const Payment({
    required this.id,
    required this.debtId,
    required this.amount,
    required this.method,
    required this.paidAt,
  });

  final String id;
  final String debtId;
  final Money amount;
  final PaymentMethod method;
  final DateTime paidAt;
}

/// Dette avec ses paiements et les valeurs calculées pour l'affichage.
@immutable
class DebtView {
  const DebtView({
    required this.debt,
    required this.payments,
    required this.paid,
    required this.remaining,
    required this.status,
    required this.overdueDays,
    required this.pendingSync,
  });

  final Debt debt;
  final List<Payment> payments;
  final Money paid;
  final Money remaining;
  final DebtStatus status;

  /// Jours de retard (0 si non échue, soldée ou sans échéance).
  final int overdueDays;

  /// Des modifications de cette dette (ou de ses paiements) n'ont pas encore
  /// été envoyées au serveur.
  final bool pendingSync;

  bool get isOverdue => overdueDays > 0;
}

/// Client avec ses dettes et les valeurs calculées pour l'affichage.
@immutable
class CustomerView {
  const CustomerView({
    required this.customer,
    required this.debts,
    required this.outstanding,
    required this.maxOverdueDays,
    required this.creditLimitExceeded,
    required this.pendingSync,
  });

  final Customer customer;
  final List<DebtView> debts;

  /// Solde dû : somme du restant à payer des dettes non soldées.
  final Money outstanding;
  final int maxOverdueDays;
  final bool creditLimitExceeded;
  final bool pendingSync;

  bool get hasOverdue => maxOverdueDays > 0;
  bool get isUpToDate => outstanding.isZero;
}
