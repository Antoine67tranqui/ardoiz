import 'debt_status.dart';

class Debt {
  final String id;
  final String customerId;
  final double amount;
  final String? reason;
  final DebtStatus status;
  final DateTime? dueDate;
  final DateTime createdAt;
  final bool pendingSync;

  const Debt({
    required this.id,
    required this.customerId,
    required this.amount,
    this.reason,
    this.status = DebtStatus.pending,
    this.dueDate,
    required this.createdAt,
    this.pendingSync = false,
  });

  factory Debt.fromJson(Map<String, dynamic> json) => Debt(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        amount: (json['amount'] as num).toDouble(),
        reason: json['reason'] as String?,
        status: debtStatusFromString(json['status'] as String),
        dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate'] as String) : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  factory Debt.fromLocalMap(Map<String, dynamic> map) => Debt(
        id: map['id'] as String,
        customerId: map['customer_id'] as String,
        amount: (map['amount'] as num).toDouble(),
        reason: map['reason'] as String?,
        status: debtStatusFromString(map['status'] as String),
        dueDate: map['due_date'] != null ? DateTime.parse(map['due_date'] as String) : null,
        createdAt: DateTime.parse(map['created_at'] as String),
        pendingSync: (map['pending_sync'] as int? ?? 0) == 1,
      );

  Map<String, dynamic> toLocalMap() => {
        'id': id,
        'customer_id': customerId,
        'amount': amount,
        'reason': reason,
        'status': debtStatusToString(status),
        'due_date': dueDate?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'pending_sync': pendingSync ? 1 : 0,
      };
}
