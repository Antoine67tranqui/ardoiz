import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/clock.dart';
import '../core/config.dart';
import '../data/local/app_database.dart';
import '../data/local/secret_store.dart';
import '../data/remote/api_client.dart';
import '../data/remote/backend_api.dart';
import '../data/remote/token_store.dart';
import '../data/repositories/ledger_repository.dart';
import '../data/sync/ledger_transport.dart';
import '../data/sync/sync_engine.dart';
import '../domain/dashboard.dart';
import '../domain/models.dart';
import 'connectivity.dart';
import 'session_service.dart';
import 'sync_coordinator.dart';

// ---- Infrastructure (remplacée dans les tests) ----

final Provider<Clock> clockProvider = Provider<Clock>((ref) => systemClock);

/// Ouverte au démarrage (bootstrap) ; remplacée par une base en mémoire dans les tests.
final Provider<AppDatabase> databaseProvider =
    Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider doit être remplacé au démarrage'));

final Provider<SecretStore> secretStoreProvider = Provider<SecretStore>((ref) => const SecureSecretStore());

final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore(ref.watch(secretStoreProvider)));

final Provider<ConnectivityService> connectivityProvider =
    Provider<ConnectivityService>((ref) => PluginConnectivityService());

final Provider<String> apiBaseUrlProvider = Provider<String>((ref) => ApiConfig.baseUrl);

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    baseUrl: ref.watch(apiBaseUrlProvider),
    tokens: ref.watch(tokenStoreProvider),
    onSessionExpired: () => ref.read(sessionProvider.notifier).sessionExpired(),
  ),
);

final Provider<BackendApi> backendApiProvider = Provider<BackendApi>((ref) => HttpBackendApi(ref.watch(apiClientProvider)));

final Provider<LedgerTransport> transportProvider =
    Provider<LedgerTransport>((ref) => HttpLedgerTransport(ref.watch(apiClientProvider)));

final Provider<LedgerRepository> repositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(db: ref.watch(databaseProvider), clock: ref.watch(clockProvider)),
);

/// Synchronisation automatique, propre à la session ouverte : un autre compte
/// obtient un nouveau moteur (l'ancien est arrêté).
final Provider<SyncControl> syncControlProvider = Provider<SyncControl>((ref) {
  ref.watch(sessionProvider.select((s) => s is SignedIn ? s.profile.id : null));
  final coordinator = SyncCoordinator(
    engine: SyncEngine(
      db: ref.watch(databaseProvider),
      transport: ref.watch(transportProvider),
      clock: ref.watch(clockProvider),
    ),
    db: ref.watch(databaseProvider),
    connectivity: ref.watch(connectivityProvider),
    clock: ref.watch(clockProvider),
    onUnauthorized: () => ref.read(sessionProvider.notifier).sessionExpired(),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final StreamProvider<SyncState> syncStateProvider = StreamProvider<SyncState>((ref) async* {
  final control = ref.watch(syncControlProvider);
  yield control.state;
  yield* control.states;
});

// ---- Session ----

final Provider<SessionState> initialSessionProvider = Provider<SessionState>((ref) => const SignedOut());

final Provider<SessionService> sessionServiceProvider = Provider<SessionService>(
  (ref) => SessionService(
    api: ref.watch(backendApiProvider),
    tokens: ref.watch(tokenStoreProvider),
    secrets: ref.watch(secretStoreProvider),
    db: ref.watch(databaseProvider),
    clientFactory: (tokens) => ApiClient(baseUrl: ref.read(apiBaseUrlProvider), tokens: tokens),
  ),
);

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() => ref.read(initialSessionProvider);

  SessionService get _service => ref.read(sessionServiceProvider);

  /// Au lancement : session restaurée depuis le coffre sécurisé et la base locale
  /// (fonctionne hors ligne). Le réseau n'est sollicité qu'en dernier recours.
  Future<void> restore({Duration timeout = const Duration(seconds: 8)}) async {
    try {
      state = await _service.restore().timeout(timeout);
    } on Object {
      state = const SignedOut();
    }
  }

  Future<void> login({required String phone, required String pin, bool discardUnsynced = false}) async {
    state = await _service.login(phone: phone, pin: pin, discardUnsyncedFromOtherAccount: discardUnsynced);
  }

  Future<void> completeSignUp({
    required String otpSessionToken,
    required String businessName,
    required String pin,
    bool discardUnsynced = false,
  }) async {
    state = await _service.completeSignUp(
      otpSessionToken: otpSessionToken,
      businessName: businessName,
      pin: pin,
      discardUnsyncedFromOtherAccount: discardUnsynced,
    );
  }

  /// Le serveur a refusé la session : retour à la connexion par PIN, données conservées.
  void sessionExpired() {
    final current = state;
    if (current is SignedIn) {
      state = SignedOut(phone: current.profile.phone, reason: SignedOutReason.expired);
    }
  }

  Future<LogoutResult> logout({bool force = false}) async {
    final result = await _service.logout(force: force);
    if (result is LoggedOut) state = const SignedOut(reason: SignedOutReason.loggedOut);
    return result;
  }

  Future<void> changePin({required String currentPin, required String newPin}) async {
    await _service.changePin(currentPin: currentPin, newPin: newPin);
  }

  Future<void> deleteAccount({required String pin}) async {
    await _service.deleteAccount(pin: pin);
    state = const SignedOut(reason: SignedOutReason.loggedOut);
  }

  Future<void> updateBusinessName(String name) async {
    final profile = await _service.updateBusinessName(name);
    state = SignedIn(profile);
  }

  /// Rafraîchit le profil (plan, nom) sans bloquer : échec réseau ignoré.
  Future<void> refreshProfile() async {
    if (state is! SignedIn) return;
    try {
      state = SignedIn(await _service.refreshProfile());
    } on Object {
      // Hors ligne : le profil en cache reste affiché.
    }
  }
}

final NotifierProvider<SessionNotifier, SessionState> sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

// ---- Données affichées ----

final StreamProvider<List<CustomerView>> customersProvider =
    StreamProvider<List<CustomerView>>((ref) => ref.watch(repositoryProvider).watchCustomers());

final customerByIdProvider = Provider.family<CustomerView?, String>((ref, id) {
  final customers = ref.watch(customersProvider).value ?? const <CustomerView>[];
  for (final c in customers) {
    if (c.customer.id == id) return c;
  }
  return null;
});

final debtByIdProvider = Provider.family<DebtView?, String>((ref, id) {
  final customers = ref.watch(customersProvider).value ?? const <CustomerView>[];
  for (final c in customers) {
    for (final d in c.debts) {
      if (d.debt.id == id) return d;
    }
  }
  return null;
});

/// Premium valide maintenant (expiration vérifiée même hors ligne).
final Provider<bool> isPremiumProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  return session is SignedIn && session.profile.isPremiumAt(ref.watch(clockProvider)());
});

/// Tableau de bord calculé sur l'appareil (fonctionne hors connexion).
final Provider<DashboardSummary?> dashboardProvider = Provider<DashboardSummary?>((ref) {
  final customers = ref.watch(customersProvider).value;
  if (customers == null) return null;
  return DashboardCalculator.compute(customers, ref.watch(clockProvider)());
});

// ---- Plateforme ----

/// Ouverture de liens externes (appel, WhatsApp) ; simulée dans les tests.
abstract interface class UrlOpener {
  Future<bool> open(Uri uri);
}

class PluginUrlOpener implements UrlOpener {
  const PluginUrlOpener();

  @override
  Future<bool> open(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
}

final Provider<UrlOpener> urlOpenerProvider = Provider<UrlOpener>((ref) => const PluginUrlOpener());

/// Partage d'un fichier (export CSV) ; simulé dans les tests.
abstract interface class FileSharer {
  Future<void> share({required String fileName, required List<int> bytes, required String mimeType});
}

class PluginFileSharer implements FileSharer {
  const PluginFileSharer();

  /// Le fichier contient les noms et numéros des clients : il est écrit dans le
  /// dossier temporaire puis supprimé dès le partage terminé.
  @override
  Future<void> share({required String fileName, required List<int> bytes, required String mimeType}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    try {
      await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(file.path, mimeType: mimeType)], subject: fileName));
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }
}

final Provider<FileSharer> fileSharerProvider = Provider<FileSharer>((ref) => const PluginFileSharer());

// ---- Données du serveur (en ligne) ----

final subscriptionStatusProvider =
    FutureProvider.autoDispose<SubscriptionStatus>((ref) => ref.watch(backendApiProvider).subscriptionStatus());

final reminderRulesProvider =
    FutureProvider.autoDispose<List<ReminderRule>>((ref) => ref.watch(backendApiProvider).reminderRules());

final syncIssuesProvider =
    StreamProvider.autoDispose<List<SyncIssue>>((ref) => ref.watch(repositoryProvider).watchIssues());

/// Limite de clients du plan gratuit (identique au serveur).
const int freePlanCustomerLimit = 15;
