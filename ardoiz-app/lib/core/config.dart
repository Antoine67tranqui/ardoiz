/// Configuration injectée à la compilation :
/// `flutter run --dart-define=CARNE_API_BASE_URL=https://api.exemple.com/api/v1`
class ApiConfig {
  const ApiConfig._();

  /// 10.0.2.2 = machine hôte vue depuis l'émulateur Android.
  static const String baseUrl = String.fromEnvironment(
    'CARNE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );

  /// Message d'erreur si [url] ne convient pas, sinon null. En production
  /// (build release), l'API doit être en HTTPS : les jetons et les données
  /// financières ne circulent jamais en clair.
  static String? validate(String url, {required bool release}) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'L\'adresse du serveur est invalide : "$url".';
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return 'L\'adresse du serveur doit commencer par https://.';
    }
    if (release && uri.scheme != 'https') {
      return 'Cette version de l\'application exige un serveur en HTTPS (adresse reçue : $url).';
    }
    return null;
  }
}
