import 'package:flutter/material.dart';

import '../brand.dart';

/// Couleurs sémantiques des états de dette, adaptées au thème clair/sombre.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.paid, required this.partial, required this.overdue, required this.pending});

  final Color paid;
  final Color partial;
  final Color overdue;
  final Color pending;

  static const StatusColors light = StatusColors(
    paid: Brand.paid,
    partial: Brand.partial,
    overdue: Brand.overdue,
    pending: Brand.pending,
  );

  static const StatusColors dark = StatusColors(
    paid: Brand.paidOnDark,
    partial: Brand.partialOnDark,
    overdue: Brand.overdueOnDark,
    pending: Brand.pendingOnDark,
  );

  @override
  StatusColors copyWith({Color? paid, Color? partial, Color? overdue, Color? pending}) => StatusColors(
        paid: paid ?? this.paid,
        partial: partial ?? this.partial,
        overdue: overdue ?? this.overdue,
        pending: pending ?? this.pending,
      );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      paid: Color.lerp(paid, other.paid, t)!,
      partial: Color.lerp(partial, other.partial, t)!,
      overdue: Color.lerp(overdue, other.overdue, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
    );
  }
}

class AppTheme {
  const AppTheme._();

  /// Chiffres de largeur fixe : les montants s'alignent en colonne.
  static const List<FontFeature> tabularFigures = <FontFeature>[FontFeature.tabularFigures()];

  static ThemeData light() => _build(
        ColorScheme.fromSeed(
          seedColor: Brand.forest,
          brightness: Brightness.light,
        ).copyWith(
          primary: Brand.forest,
          onPrimary: Colors.white,
          secondary: Brand.ochre,
          onSecondary: Colors.white,
          surface: Brand.paper,
          onSurface: Brand.ink,
          error: Brand.overdue,
        ),
        StatusColors.light,
      );

  static ThemeData dark() => _build(
        ColorScheme.fromSeed(
          seedColor: Brand.forest,
          brightness: Brightness.dark,
        ).copyWith(
          primary: Brand.forestOnDark,
          onPrimary: Brand.inkDark,
          surface: Brand.inkDark,
          onSurface: const Color(0xFFE6EFEC),
          error: Brand.overdueOnDark,
        ),
        StatusColors.dark,
      );

  static ThemeData _build(ColorScheme scheme, StatusColors status) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: scheme.surface);
    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[status],
      // Texte un peu plus grand que la norme : écrans parfois lus en plein soleil.
      textTheme: base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface).copyWith(
            bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 17),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 15),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.brightness == Brightness.light ? Colors.white : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.brightness == Brightness.light ? Colors.white : scheme.surfaceContainerHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

extension ThemeStatusColors on BuildContext {
  StatusColors get statusColors => Theme.of(this).extension<StatusColors>() ?? StatusColors.light;
}
