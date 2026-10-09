import 'package:ardoiz/core/money.dart';
import 'package:ardoiz/domain/customer_filter.dart';
import 'package:ardoiz/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

CustomerView view(String name, {String phone = '+22901000000', int owed = 0, int overdue = 0, int day = 1}) => CustomerView(
      customer: Customer(id: name, name: name, phone: phone, createdAt: DateTime.utc(2026, 1, day)),
      debts: const <DebtView>[],
      outstanding: Money.fromCents(owed * 100),
      maxOverdueDays: overdue,
      creditLimitExceeded: false,
      pendingSync: false,
    );

List<String> names(List<CustomerView> l) => l.map((v) => v.customer.name).toList();

void main() {
  final all = <CustomerView>[
    view('Zoé', phone: '+229 05 55 12 34', owed: 100, day: 3),
    view('Aïcha', phone: '+229 01 67 00 11', owed: 900, overdue: 5, day: 1),
    view('bako', phone: '+229 07 00 00 99', owed: 900, day: 2),
  ];

  test('tri par nom sans tenir compte de la casse ni des accents', () {
    expect(names(filterCustomers(all)), <String>['Aïcha', 'bako', 'Zoé']);
  });

  test('tri par solde décroissant, puis par nom à égalité', () {
    expect(names(filterCustomers(all, sort: CustomerSort.balance)), <String>['Aïcha', 'bako', 'Zoé']);
  });

  test('tri par ancienneté de création, du plus récent au plus ancien', () {
    expect(names(filterCustomers(all, sort: CustomerSort.recent)), <String>['Zoé', 'bako', 'Aïcha']);
  });

  test('recherche par nom approximatif', () {
    expect(names(filterCustomers(all, query: ' AICHA ')), <String>['Aïcha']);
    expect(names(filterCustomers(all, query: 'zo')), <String>['Zoé']);
  });

  test('recherche par chiffres du numéro, à partir de 3 chiffres', () {
    expect(names(filterCustomers(all, query: '55 12')), <String>['Zoé']);
    expect(names(filterCustomers(all, query: '0 0')), isEmpty, reason: 'moins de 3 chiffres : ne cherche pas dans les numéros');
  });

  test('filtre « en retard » seul et combiné avec la recherche', () {
    expect(names(filterCustomers(all, overdueOnly: true)), <String>['Aïcha']);
    expect(names(filterCustomers(all, overdueOnly: true, query: 'bako')), isEmpty);
  });

  test('ne modifie pas la liste d\'origine', () {
    final copy = List<CustomerView>.of(all);
    filterCustomers(all, sort: CustomerSort.recent);
    expect(all, copy);
  });
}
