import '../core/text.dart';
import 'models.dart';

enum CustomerSort {
  name('Nom'),
  balance('Solde le plus élevé'),
  recent('Plus récents');

  const CustomerSort(this.label);
  final String label;
}

/// Recherche (nom sans accents/casse, ou chiffres du téléphone), filtre « en
/// retard » et tri de la liste des clients.
List<CustomerView> filterCustomers(
  List<CustomerView> customers, {
  String query = '',
  bool overdueOnly = false,
  CustomerSort sort = CustomerSort.name,
}) {
  final needle = foldForSearch(query.trim());
  final needleDigits = digitsOnly(query);
  final result = customers.where((view) {
    if (overdueOnly && !view.hasOverdue) return false;
    if (needle.isEmpty) return true;
    if (foldForSearch(view.customer.name).contains(needle)) return true;
    return needleDigits.length >= 3 && digitsOnly(view.customer.phone).contains(needleDigits);
  }).toList();

  switch (sort) {
    case CustomerSort.name:
      result.sort((a, b) => foldForSearch(a.customer.name).compareTo(foldForSearch(b.customer.name)));
    case CustomerSort.balance:
      result.sort((a, b) {
        final byBalance = b.outstanding.compareTo(a.outstanding);
        return byBalance != 0 ? byBalance : foldForSearch(a.customer.name).compareTo(foldForSearch(b.customer.name));
      });
    case CustomerSort.recent:
      result.sort((a, b) => b.customer.createdAt.compareTo(a.customer.createdAt));
  }
  return result;
}
