import 'dart:async';
import 'dart:convert';

import '../data/local/app_database.dart';
import '../data/local/ledger_store.dart';
import '../data/local/outbox_store.dart';
import '../data/local/secret_store.dart';
import '../data/remote/api_client.dart';
import '../data/remote/api_exceptions.dart';
import '../data/remote/backend_api.dart';
import '../data/remote/token_store.dart';

enum SignedOutReason { none, expired, loggedOut }

sealed class SessionState {
  const SessionState();
}

/// Aucun jeton. [phone] est renseigné quand des données locales du commerçant
/// sont conservées (session expirée) : la connexion par PIN est pré-remplie.
final class SignedOut extends SessionState {
  const SignedOut({this.phone, this.reason = SignedOutReason.none});

  final String? phone;
  final SignedOutReason reason;
}

final class SignedIn extends SessionState {
  const SignedIn(this.profile);

  final Profile profile;
}

/// Des saisies non envoyées d'un autre compte seraient perdues.
class UnsyncedDataException implements Exception {
  const UnsyncedDataException(this.count);

  final int count;

  @override
  String toString() => '$count modification(s) non envoyée(s) d\'un autre compte.';
}

sealed class LogoutResult {
  const LogoutResult();
}

final class LoggedOut extends LogoutResult {
  const LoggedOut({required this.remoteRevoked});

  /// Faux si le serveur n'a pas pu être prévenu (hors ligne) : la révocation
  /// sera retentée dès que possible.
  final bool remoteRevoked;
}

/// Déconnexion refusée : [unsyncedCount] saisies ne sont pas encore envoyées.
final class LogoutBlocked extends LogoutResult {
  const LogoutBlocked(this.unsyncedCount);

  final int unsyncedCount;
}

/// Logique de session : connexion, restauration hors ligne, déconnexion sûre.
/// Les jetons vivent dans le coffre sécurisé, les données du commerçant dans la
/// base chiffrée ; la base est liée à UN compte et effacée si un autre se connecte.
class SessionService {
  SessionService({
    required this.api,
    required this.tokens,
    required this.secrets,
    required this.db,
    required this.clientFactory,
    this.logoutTimeout = const Duration(seconds: 5),
  })  : _ledger = LedgerStore(db),
        _outbox = OutboxStore(db);

  final BackendApi api;
  final TokenStore tokens;
  final SecretStore secrets;
  final AppDatabase db;

  /// Crée un client HTTP isolé (jetons fournis) pour révoquer une session
  /// fermée hors ligne.
  final ApiClient Function(TokenStore tokens) clientFactory;
  final Duration logoutTimeout;

  final LedgerStore _ledger;
  final OutboxStore _outbox;

  static const String _userKey = 'user_id';
  static const String _profileKey = 'profile';

  /// État au lancement, utilisable hors ligne.
  Future<SessionState> restore() async {
    final cached = _cachedProfile();
    if (await tokens.hasSession) {
      if (cached != null) return SignedIn(cached);
      try {
        return SignedIn(await refreshProfile());
      } on ApiException {
        return const SignedOut();
      }
    }
    return cached == null ? const SignedOut() : SignedOut(phone: cached.phone, reason: SignedOutReason.expired);
  }

  Future<SignedIn> login({
    required String phone,
    required String pin,
    bool discardUnsyncedFromOtherAccount = false,
  }) async {
    final session = await api.login(phone: phone, pin: pin);
    return _establish(session, discard: discardUnsyncedFromOtherAccount);
  }

  /// Fin de l'inscription (ou réinitialisation du PIN) après vérification du code SMS.
  Future<SignedIn> completeSignUp({
    required String otpSessionToken,
    required String businessName,
    required String pin,
    bool discardUnsyncedFromOtherAccount = false,
  }) async {
    final session = await api.setupPin(otpSessionToken: otpSessionToken, businessName: businessName, pin: pin);
    return _establish(session, discard: discardUnsyncedFromOtherAccount);
  }

  Future<SignedIn> _establish(SessionTokens session, {required bool discard}) async {
    await tokens.save(accessToken: session.accessToken, refreshToken: session.refreshToken);
    final Profile profile;
    try {
      profile = await api.profile();
    } on Object {
      // Connexion atomique : sans profil, pas de session à moitié établie.
      await tokens.clear();
      rethrow;
    }

    final boundUser = _ledger.meta(_userKey);
    if (boundUser != null && boundUser != profile.id) {
      final unsynced = _outbox.count();
      if (unsynced > 0 && !discard) {
        await tokens.clear();
        throw UnsyncedDataException(unsynced);
      }
      db.clearAllData();
    }
    _ledger
      ..setMeta(_userKey, profile.id)
      ..setMeta(_profileKey, _encode(profile));
    await _finishPendingRevocation();
    return SignedIn(profile);
  }

  /// Profil à jour (nom de la boutique, plan), mis en cache pour l'usage hors ligne.
  Future<Profile> refreshProfile() async {
    final profile = await api.profile();
    _ledger.setMeta(_profileKey, _encode(profile));
    // Base vierge (données locales réinitialisées) : elle appartient désormais à ce
    // compte, sinon la connexion d'un autre commerçant n'effacerait pas ces données.
    if (_ledger.meta(_userKey) == null) _ledger.setMeta(_userKey, profile.id);
    return profile;
  }

  Future<Profile> updateBusinessName(String businessName) async {
    final profile = await api.updateBusinessName(businessName);
    _ledger.setMeta(_profileKey, _encode(profile));
    return profile;
  }

  /// Changer le PIN révoque TOUTES les sessions, celle de cet appareil comprise :
  /// on se reconnecte aussitôt avec le nouveau PIN.
  Future<void> changePin({required String currentPin, required String newPin}) async {
    final phone = _cachedProfile()?.phone;
    await api.changePin(currentPin: currentPin, newPin: newPin);
    if (phone == null) {
      await tokens.clear();
      return;
    }
    final session = await api.login(phone: phone, pin: newPin);
    await tokens.save(accessToken: session.accessToken, refreshToken: session.refreshToken);
  }

  /// Suppression définitive du compte (côté serveur) puis de tout ce que ce
  /// téléphone en garde : jetons et base locale, y compris les saisies non envoyées
  /// (elles appartiennent à un compte qui n'existe plus).
  Future<void> deleteAccount({required String pin}) async {
    await api.deleteAccount(pin: pin);
    await tokens.clear();
    await secrets.delete(SecretKeys.pendingRevocation);
    db.clearAllData();
  }

  /// Déconnexion volontaire. Refusée tant que des saisies ne sont pas envoyées,
  /// sauf [force] (le commerçant a confirmé la perte).
  Future<LogoutResult> logout({bool force = false}) async {
    final unsynced = _outbox.count();
    if (unsynced > 0 && !force) return LogoutBlocked(unsynced);

    var revoked = false;
    final refreshToken = await tokens.refreshToken;
    try {
      await api.logout().timeout(logoutTimeout);
      revoked = true;
    } on ApiException {
      // Hors ligne ou session déjà invalide : voir ci-dessous.
    } on TimeoutException {
      // Réseau trop lent.
    }
    if (!revoked && refreshToken != null) {
      // La session reste valable côté serveur jusqu'à sa révocation : on garde
      // de quoi la révoquer au prochain accès réseau.
      await secrets.write(SecretKeys.pendingRevocation, refreshToken);
    }
    await tokens.clear();
    db.clearAllData();
    return LoggedOut(remoteRevoked: revoked);
  }

  /// Révoque côté serveur une session fermée hors ligne (à appeler quand le réseau revient).
  Future<bool> revokePendingSession() async {
    final refreshToken = await secrets.read(SecretKeys.pendingRevocation);
    if (refreshToken == null) return true;
    final isolated = TokenStore(InMemorySecretStore());
    await isolated.save(accessToken: '', refreshToken: refreshToken);
    try {
      await HttpBackendApi(clientFactory(isolated)).logout();
    } on UnauthorizedException {
      // Déjà révoquée : rien de plus à faire.
    } on ApiException {
      return false;
    }
    await secrets.delete(SecretKeys.pendingRevocation);
    return true;
  }

  Future<void> _finishPendingRevocation() async {
    // Une nouvelle connexion ne doit pas laisser traîner l'ancienne session.
    unawaited(revokePendingSession());
  }

  // ---- Cache du profil ----

  Profile? _cachedProfile() {
    final raw = _ledger.meta(_profileKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return Profile(
        id: json['id'] as String,
        phone: json['phone'] as String,
        businessName: json['businessName'] as String,
        plan: json['plan'] == 'PREMIUM' ? Plan.premium : Plan.free,
        planExpiresAt: json['planExpiresAt'] == null ? null : DateTime.parse(json['planExpiresAt'] as String),
      );
    } on Object {
      return null;
    }
  }

  static String _encode(Profile profile) => jsonEncode(<String, Object?>{
        'id': profile.id,
        'phone': profile.phone,
        'businessName': profile.businessName,
        'plan': profile.isPremium ? 'PREMIUM' : 'FREE',
        'planExpiresAt': profile.planExpiresAt?.toIso8601String(),
      });
}
