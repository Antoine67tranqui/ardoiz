import 'package:flutter/foundation.dart';

/// Montant en FCFA, stocké en centièmes (entier) : jamais de flottant pour de
/// l'argent (0,1 + 0,7 != 0,8 en virgule flottante). Le backend utilise des
/// colonnes Decimal(12, 2), soit au plus 2 décimales.
@immutable
class Money implements Comparable<Money> {
  const Money.fromCents(this.cents);

  /// Montant maximal accepté par le backend (Decimal(12, 2)).
  static const Money max = Money.fromCents(9999999999 * 100);
  static const Money zero = Money.fromCents(0);

  final int cents;

  /// Depuis un nombre JSON renvoyé par l'API (au plus 2 décimales).
  factory Money.fromJson(num value) => Money.fromCents((value * 100).round());

  /// Saisie utilisateur : « 1 250,50 », « 1250.5 », « 2500 ». Retourne null si
  /// la saisie n'est pas un montant positif valide (au plus 2 décimales).
  static Money? tryParse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\s  ]'), '');
    if (cleaned.isEmpty) return null;
    final match = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final whole = BigInt.tryParse(match.group(1)!);
    if (whole == null || whole > BigInt.from(9999999999)) return null;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    final value = Money.fromCents(whole.toInt() * 100 + int.parse(fraction.isEmpty ? '0' : fraction));
    return value.cents > max.cents ? null : value;
  }

  /// Valeur à envoyer à l'API : entier si possible, sinon 2 décimales exactes.
  num toJson() => cents % 100 == 0 ? cents ~/ 100 : cents / 100;

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;

  Money operator +(Money other) => Money.fromCents(cents + other.cents);
  Money operator -(Money other) => Money.fromCents(cents - other.cents);
  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  /// Jamais négatif (un trop-perçu ne crée pas de solde « inverse »).
  Money get clampedAtZero => cents < 0 ? zero : this;

  static Money sum(Iterable<Money> amounts) =>
      amounts.fold(zero, (total, amount) => total + amount);

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'Money($cents centimes)';
}
