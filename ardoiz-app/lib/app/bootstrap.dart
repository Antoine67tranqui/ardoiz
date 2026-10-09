import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/config.dart';
import '../data/local/app_database.dart';
import '../data/local/secret_store.dart';
import 'providers.dart';

enum BootstrapProblem {
  /// Adresse du serveur invalide (ou non sécurisée en version de production).
  configuration,

  /// SQLCipher indisponible : on refuse de stocker des données en clair.
  encryptionUnavailable,

  /// La clé du coffre ne déchiffre pas la base (clé perdue, sauvegarde restaurée ailleurs).
  keyMismatch,

  /// Tout autre échec d'ouverture de la base.
  database,
}

sealed class BootstrapResult {
  const BootstrapResult();
}

final class BootstrapReady extends BootstrapResult {
  const BootstrapReady(this.container);

  final ProviderContainer container;
}

final class BootstrapFailed extends BootstrapResult {
  const BootstrapFailed(this.problem, this.message);

  final BootstrapProblem problem;
  final String message;

  /// Seul un désaccord de clé se règle en repartant d'une base vierge : les
  /// données se récupèrent ensuite depuis le serveur.
  bool get canResetLocalData => problem == BootstrapProblem.keyMismatch || problem == BootstrapProblem.database;
}

/// Démarrage : configuration, clé de chiffrement, base locale, session. Tout
/// échec devient un écran d'explication (jamais un écran blanc).
class Bootstrap {
  Bootstrap({
    required this.secrets,
    required this.databasePath,
    this.apiBaseUrl = ApiConfig.baseUrl,
    this.websiteUrl = ApiConfig.websiteUrl,
    this.release = false,
    this.overrides = const <Override>[],
  });

  final SecretStore secrets;

  /// Chemin du fichier de la base (dossier privé de l'application).
  final Future<String> Function() databasePath;
  final String apiBaseUrl;
  final String websiteUrl;
  final bool release;
  final List<Override> overrides;

  Future<BootstrapResult> run() async {
    final configError = ApiConfig.validate(apiBaseUrl, release: release);
    final siteError = ApiConfig.validateWebsite(websiteUrl, release: release);
    final problem = configError ?? siteError;
    if (problem != null) return BootstrapFailed(BootstrapProblem.configuration, problem);

    final AppDatabase db;
    try {
      final key = await DatabaseKeyProvider(secrets).getOrCreate();
      db = AppDatabase.open(path: await databasePath(), hexKey: key);
    } on EncryptionUnavailableException catch (e) {
      return BootstrapFailed(BootstrapProblem.encryptionUnavailable, e.message);
    } on DatabaseKeyMismatchException catch (e) {
      return BootstrapFailed(BootstrapProblem.keyMismatch, e.message);
    } on Object catch (e) {
      return BootstrapFailed(BootstrapProblem.database, e is DatabaseException ? e.message : 'La base locale n\'a pas pu être ouverte.');
    }

    final container = ProviderContainer(overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      secretStoreProvider.overrideWithValue(secrets),
      apiBaseUrlProvider.overrideWithValue(apiBaseUrl),
      ...overrides,
    ]);
    container.listen(sessionProvider, (_, _) {}); // garde l'état de session vivant
    await container.read(sessionProvider.notifier).restore();
    return BootstrapReady(container);
  }

  /// Repart d'une base vierge : supprime le fichier chiffré illisible. Les données
  /// du serveur reviennent à la reconnexion ; les saisies jamais envoyées sont perdues.
  Future<BootstrapResult> resetLocalDataAndRun() async {
    final path = await databasePath();
    for (final suffix in <String>['', '-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (file.existsSync()) await file.delete();
    }
    return run();
  }
}
