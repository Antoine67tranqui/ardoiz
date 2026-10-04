import 'dart:math';

import 'package:ardoiz/core/brand.dart';
import 'package:ardoiz/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rapport de contraste WCAG 2.x entre deux couleurs opaques.
double contrast(Color a, Color b) {
  double channel(double c) => c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) => 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final l1 = luminance(a);
  final l2 = luminance(b);
  return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05);
}

void main() {
  group('accessibilité des couleurs (WCAG AA : 4,5 pour le texte)', () {
    test('thème clair : texte principal, boutons, états de dette', () {
      final scheme = AppTheme.light().colorScheme;
      expect(contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(7), reason: 'texte sur fond');
      expect(contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5), reason: 'texte des boutons');
      expect(contrast(scheme.onSecondary, scheme.secondary), greaterThanOrEqualTo(4.5), reason: 'texte sur ocre');
      const status = StatusColors.light;
      for (final entry in {'payé': status.paid, 'partiel': status.partial, 'retard': status.overdue, 'en attente': status.pending}.entries) {
        expect(contrast(entry.value, Colors.white), greaterThanOrEqualTo(4.5), reason: '${entry.key} sur carte blanche');
        expect(contrast(entry.value, Brand.paper), greaterThanOrEqualTo(4.5), reason: '${entry.key} sur fond papier');
      }
    });

    test('thème sombre : mêmes exigences', () {
      final scheme = AppTheme.dark().colorScheme;
      expect(contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(7));
      expect(contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5));
      const status = StatusColors.dark;
      for (final entry in {'payé': status.paid, 'partiel': status.partial, 'retard': status.overdue, 'en attente': status.pending}.entries) {
        expect(contrast(entry.value, scheme.surface), greaterThanOrEqualTo(4.5), reason: entry.key);
        expect(contrast(entry.value, scheme.surfaceContainerHigh), greaterThanOrEqualTo(4.5), reason: '${entry.key} sur carte');
      }
    });

    test('le vert de marque ressort sur le fond papier (lien, icône active)', () {
      expect(contrast(Brand.forest, Brand.paper), greaterThanOrEqualTo(4.5));
      expect(contrast(Brand.ochre, Brand.paper), greaterThanOrEqualTo(4.5), reason: 'ocre utilisé aussi pour du texte');
    });
  });

  test('les thèmes exposent les couleurs d\'état et se construisent sans erreur', () {
    expect(AppTheme.light().extension<StatusColors>(), isNotNull);
    expect(AppTheme.dark().extension<StatusColors>()!.paid, Brand.paidOnDark);
    expect(AppTheme.light().useMaterial3, isTrue);
  });
}
