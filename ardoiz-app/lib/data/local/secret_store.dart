import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage des secrets de l'app (jetons, clé de chiffrement de la base) dans
/// le coffre sécurisé du système (Keystore Android).
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretStore implements SecretStore {
  const SecureSecretStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Implémentation mémoire pour les tests.
class InMemorySecretStore implements SecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class SecretKeys {
  const SecretKeys._();
  static const String accessToken = 'carne_access_token';
  static const String refreshToken = 'carne_refresh_token';
  static const String databaseKey = 'carne_database_key';
  // Jeton de rafraîchissement d'une session fermée hors ligne, à révoquer côté
  // serveur dès que le réseau revient.
  static const String pendingRevocation = 'carne_pending_revocation';
}

/// Clé de chiffrement de la base locale : 256 bits aléatoires (CSPRNG), générés
/// au premier lancement et conservés dans le coffre sécurisé, jamais en clair
/// sur le disque ni dans le code.
class DatabaseKeyProvider {
  DatabaseKeyProvider(this._store, {Random? random}) : _random = random ?? Random.secure();

  final SecretStore _store;
  final Random _random;

  static final RegExp _validKey = RegExp(r'^[0-9a-f]{64}$');

  /// Clé hexadécimale de 64 caractères.
  Future<String> getOrCreate() async {
    final existing = await _store.read(SecretKeys.databaseKey);
    if (existing != null && _validKey.hasMatch(existing)) return existing;
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final key = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _store.write(SecretKeys.databaseKey, key);
    return key;
  }

  Future<void> forget() => _store.delete(SecretKeys.databaseKey);
}
