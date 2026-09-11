enum DebtStatus { pending, partial, paid }

DebtStatus debtStatusFromString(String value) {
  switch (value.toUpperCase()) {
    case 'PAID':
      return DebtStatus.paid;
    case 'PARTIAL':
      return DebtStatus.partial;
    default:
      return DebtStatus.pending;
  }
}

String debtStatusToString(DebtStatus status) {
  switch (status) {
    case DebtStatus.paid:
      return 'PAID';
    case DebtStatus.partial:
      return 'PARTIAL';
    case DebtStatus.pending:
      return 'PENDING';
  }
}
