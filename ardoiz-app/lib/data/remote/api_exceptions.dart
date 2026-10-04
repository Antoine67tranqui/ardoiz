/// Erreurs réseau/API classées par la conduite à tenir (réessayer, bloquer,
/// reconnecter), et non par détail technique.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Pas de réseau, délai dépassé, serveur injoignable : réessayer plus tard.
final class NetworkException extends ApiException {
  const NetworkException([super.message = 'Pas de connexion au serveur.']);
}

/// Erreur serveur (5xx) ou surcharge (429, 408) : réessayer plus tard.
final class ServerException extends ApiException {
  const ServerException(this.statusCode, [super.message = 'Le serveur est momentanément indisponible.']);

  final int statusCode;
}

/// Session invalide ou révoquée (le rafraîchissement du jeton a échoué).
final class UnauthorizedException extends ApiException {
  const UnauthorizedException([super.message = 'Votre session a expiré. Reconnectez-vous.']);
}

/// Refus définitif du serveur (400, 403, 404, 409, 422) : réessayer ne changera rien.
final class RejectedException extends ApiException {
  const RejectedException(this.statusCode, super.message, {this.code});

  final int statusCode;

  /// Code métier du backend (FREE_PLAN_LIMIT_REACHED, OVERPAYMENT, ...).
  final String? code;

  bool get isNotFound => statusCode == 404;
}
