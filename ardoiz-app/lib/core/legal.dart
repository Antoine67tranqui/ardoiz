import 'config.dart';

/// Textes juridiques : version acceptée à l'inscription (doit être celle du
/// serveur, vérifié par un test) et adresses des documents publics.
class Legal {
  const Legal._();

  /// Version des conditions d'utilisation et de la politique de confidentialité.
  static const String termsVersion = '2026-10-06';

  static Uri? privacyUri([String base = ApiConfig.websiteUrl]) => base.isEmpty ? null : Uri.parse(base).resolve('confidentialite.html');
  static Uri? termsUri([String base = ApiConfig.websiteUrl]) => base.isEmpty ? null : Uri.parse(base).resolve('conditions.html');
  static Uri? mentionsUri([String base = ApiConfig.websiteUrl]) => base.isEmpty ? null : Uri.parse(base).resolve('mentions-legales.html');
}
