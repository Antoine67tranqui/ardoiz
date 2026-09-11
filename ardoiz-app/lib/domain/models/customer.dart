class Customer {
  final String id;
  final String userId;
  final String name;
  final String? phone;
  final double outstandingBalance;
  final bool pendingSync;

  const Customer({
    required this.id,
    required this.userId,
    required this.name,
    this.phone,
    this.outstandingBalance = 0,
    this.pendingSync = false,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        userId: json['userId'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        outstandingBalance: (json['outstandingBalance'] as num?)?.toDouble() ?? 0,
      );

  factory Customer.fromLocalMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        phone: map['phone'] as String?,
        outstandingBalance: (map['outstanding_balance'] as num?)?.toDouble() ?? 0,
        pendingSync: (map['pending_sync'] as int? ?? 0) == 1,
      );

  Map<String, dynamic> toLocalMap() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'phone': phone,
        'outstanding_balance': outstandingBalance,
        'pending_sync': pendingSync ? 1 : 0,
      };
}
