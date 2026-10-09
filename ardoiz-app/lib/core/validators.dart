import 'money.dart';

/// Règles de saisie, alignées sur la validation du backend. Chaque fonction
/// renvoie un message d'erreur en français, ou null si la valeur est valide.
class Validators {
  const Validators._();

  static final RegExp _looseCustomerPhone = RegExp(r'^[0-9+()\-.\s]{8,20}$');
  static final RegExp _pin = RegExp(r'^\d{4}$');
  static final RegExp _otp = RegExp(r'^\d{6}$');

  static String? customerName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Saisissez le nom du client.';
    if (v.length < 2) return 'Le nom doit comporter au moins 2 caractères.';
    if (v.length > 100) return 'Le nom est trop long (100 caractères maximum).';
    return null;
  }

  /// Téléphone d'un client : large (numéros locaux de tous formats).
  static String? customerPhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Le téléphone est nécessaire pour les relances et Mobile Money.';
    if (!_looseCustomerPhone.hasMatch(v)) return 'Numéro invalide (8 à 20 chiffres, espaces et + acceptés).';
    return null;
  }

  /// Téléphone du commerçant (connexion) : format international obligatoire.
  static String? accountPhone(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'[\s().-]'), '');
    if (v.isEmpty) return 'Saisissez votre numéro de téléphone.';
    if (!RegExp(r'^\+\d{8,15}$').hasMatch(v)) {
      return 'Saisissez le numéro avec l\'indicatif du pays, par ex. +229 01 67 07 70 27.';
    }
    return null;
  }

  /// Forme canonique envoyée au serveur : « +22901670770 27 » -> « +2290167077027 ».
  static String normalizeAccountPhone(String value) => value.replaceAll(RegExp(r'[\s().-]'), '');

  static String? pin(String? value) => _pin.hasMatch(value ?? '') ? null : 'Le code PIN comporte exactement 4 chiffres.';

  static String? otp(String? value) => _otp.hasMatch(value ?? '') ? null : 'Le code reçu par SMS comporte 6 chiffres.';

  static String? businessName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Saisissez le nom de votre boutique.';
    if (v.length > 100) return 'Le nom est trop long (100 caractères maximum).';
    return null;
  }

  /// Montant strictement positif, au plus [max] (par défaut le maximum du serveur).
  static String? amount(String? value, {Money? max}) {
    final money = Money.tryParse(value ?? '');
    if (money == null) return 'Saisissez un montant valide (ex. 2 500).';
    if (!money.isPositive) return 'Le montant doit être supérieur à zéro.';
    final limit = max ?? Money.max;
    if (money > limit) {
      return max == null ? 'Montant trop élevé.' : 'Le montant dépasse le solde restant.';
    }
    return null;
  }

  /// Plafond de crédit : vide (aucun plafond) ou montant positif.
  static String? creditLimit(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    return amount(value);
  }

  static String? reason(String? value) =>
      (value ?? '').trim().length > 500 ? 'Le motif est trop long (500 caractères maximum).' : null;

  static String? cashLabel(String? value) =>
      (value ?? '').trim().length > 200 ? 'Le libellé est trop long (200 caractères maximum).' : null;

  static String? category(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Choisissez une catégorie.';
    if (v.length > 50) return 'La catégorie est trop longue (50 caractères maximum).';
    return null;
  }
}
