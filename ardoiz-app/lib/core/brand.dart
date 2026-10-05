import 'package:flutter/material.dart';

/// Identité de marque (nom, accroche, palette). Un seul endroit à modifier.
class Brand {
  const Brand._();

  static const String name = 'Carné';
  static const String tagline = 'Le carnet de crédit de votre commerce';

  /// Structure qui a conçu et développé Carné (nom tel qu'il figure dans ses documents).
  static const String publisher = 'CIVORA Conseil et Solutions';

  /// Doit correspondre à `version:` de pubspec.yaml (vérifié par un test).
  static const String version = '0.2.0';

  // Vert profond (confiance, argent) et ocre (chaleur, terre d'Afrique de
  // l'Ouest), sur un fond « papier de carnet » : les couleurs dominantes du
  // marché régional (orange, jaune, bleu des opérateurs Mobile Money) sont ainsi évitées.
  static const Color forest = Color(0xFF0B5D4B);
  static const Color forestDark = Color(0xFF063D31);
  static const Color ochre = Color(0xFFA85F0A);
  static const Color paper = Color(0xFFFBF8F1);
  static const Color ink = Color(0xFF1C2B27);

  /// Or du logo (reliure du carnet) : décoratif, jamais utilisé pour du texte.
  static const Color gold = Color(0xFFE3A53A);
  static const Color logoLine = Color(0xFFC9DDD6);

  // États d'une dette : jamais la couleur seule (toujours un texte ou une icône).
  static const Color paid = Color(0xFF1E7B4F);
  static const Color partial = Color(0xFF8F5A00);
  static const Color overdue = Color(0xFFB3261E);
  static const Color pending = Color(0xFF4A5A57);

  // Variantes sombres.
  static const Color forestOnDark = Color(0xFF7FD6BC);
  static const Color inkDark = Color(0xFF0F1A17);
  static const Color paidOnDark = Color(0xFF6FD6A3);
  static const Color partialOnDark = Color(0xFFF0B455);
  static const Color overdueOnDark = Color(0xFFFF8A80);
  static const Color pendingOnDark = Color(0xFFB4C2BE);
}
