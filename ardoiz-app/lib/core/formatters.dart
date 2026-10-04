import 'package:characters/characters.dart';

import 'money.dart';

const String _thinSpace = ' ';
const String _nbsp = ' ';

/// « 1 250 FCFA », ou « 1 250,50 FCFA » s'il y a des centimes. Espace fine
/// insécable comme séparateur de milliers (usage français).
String formatMoney(Money amount, {bool withCurrency = true}) {
  final negative = amount.cents < 0;
  final absolute = amount.cents.abs();
  final whole = absolute ~/ 100;
  final fraction = absolute % 100;
  final digits = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => _thinSpace);
  final number = fraction == 0 ? digits : '$digits,${fraction.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}$number${withCurrency ? '$_nbsp' 'FCFA' : ''}';
}

const List<String> _months = <String>[
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

/// « 4 oct. 2026 » (date locale de l'appareil).
String formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// « il y a 3 jours », « aujourd'hui », « dans 2 jours ».
String formatRelativeDays(DateTime date, DateTime now) {
  final a = DateTime(date.toLocal().year, date.toLocal().month, date.toLocal().day);
  final b = DateTime(now.toLocal().year, now.toLocal().month, now.toLocal().day);
  final days = a.difference(b).inDays;
  if (days == 0) return 'aujourd\'hui';
  if (days == 1) return 'demain';
  if (days == -1) return 'hier';
  return days > 0 ? 'dans $days jours' : 'il y a ${-days} jours';
}

/// « +229 01 67 07 70 27 » : conserve la saisie, normalise seulement les espaces.
String formatPhone(String phone) => phone.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Initiale(s) pour les avatars : « Aicha Traore » -> « AT ».
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}

/// Montant pour un champ de saisie : « 2500 » ou « 1250,50 » (sans séparateur de milliers).
String formatMoneyInput(Money amount) {
  final whole = amount.cents.abs() ~/ 100;
  final fraction = amount.cents.abs() % 100;
  final sign = amount.cents < 0 ? '-' : '';
  return fraction == 0 ? '$sign$whole' : '$sign$whole,${fraction.toString().padLeft(2, '0')}';
}
