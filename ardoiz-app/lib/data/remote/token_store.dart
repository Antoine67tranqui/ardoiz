import '../local/secret_store.dart';

/// Jetons de session, conservés dans le coffre sécurisé et en mémoire.
class TokenStore {
  TokenStore(this._secrets);

  final SecretStore _secrets;
  String? _access;
  String? _refresh;
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _access = await _secrets.read(SecretKeys.accessToken);
    _refresh = await _secrets.read(SecretKeys.refreshToken);
    _loaded = true;
  }

  Future<String?> get accessToken async {
    await _load();
    return _access;
  }

  Future<String?> get refreshToken async {
    await _load();
    return _refresh;
  }

  Future<bool> get hasSession async => (await refreshToken) != null;

  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _secrets.write(SecretKeys.accessToken, accessToken);
    await _secrets.write(SecretKeys.refreshToken, refreshToken);
    _access = accessToken;
    _refresh = refreshToken;
    _loaded = true;
  }

  Future<void> clear() async {
    await _secrets.delete(SecretKeys.accessToken);
    await _secrets.delete(SecretKeys.refreshToken);
    _access = null;
    _refresh = null;
    _loaded = true;
  }
}
