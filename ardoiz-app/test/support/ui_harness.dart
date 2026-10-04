import 'dart:async';

import 'package:ardoiz/app/connectivity.dart';
import 'package:ardoiz/app/providers.dart';
import 'package:ardoiz/app/routes.dart';
import 'package:ardoiz/app/session_service.dart';
import 'package:ardoiz/app/sync_coordinator.dart';
import 'package:ardoiz/core/theme/app_theme.dart';
import 'package:ardoiz/data/local/app_database.dart';
import 'package:ardoiz/data/local/ledger_store.dart';
import 'package:ardoiz/data/local/outbox_store.dart';
import 'package:ardoiz/data/local/secret_store.dart';
import 'package:ardoiz/data/remote/backend_api.dart';
import 'package:ardoiz/data/repositories/ledger_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'harness.dart';

class MockBackendApi extends Mock implements BackendApi {}

class FakeSyncControl implements SyncControl {
  SyncState _state = const SyncState();
  final StreamController<SyncState> _controller = StreamController<SyncState>.broadcast();
  int syncCalls = 0;

  @override
  SyncState get state => _state;

  @override
  Stream<SyncState> get states => _controller.stream;

  @override
  Future<void> syncNow() async => syncCalls++;

  void emit(SyncState next) {
    _state = next;
    _controller.add(next);
  }
}

class FakeConnectivityService implements ConnectivityService {
  @override
  Future<bool> get isOnline async => true;

  @override
  Stream<bool> get onChanged => const Stream<bool>.empty();
}

const Profile testProfile = Profile(
  id: 'user-1',
  phone: '+2290167000001',
  businessName: 'Boutique Fatou',
  plan: Plan.free,
);

final Profile premiumProfile = Profile(
  id: 'user-1',
  phone: '+2290167000001',
  businessName: 'Boutique Fatou',
  plan: Plan.premium,
  planExpiresAt: DateTime.utc(2026, 11, 1),
);

/// Environnement d'écran : base chiffrée réelle (en mémoire), dépôt réel,
/// API simulée (mocktail), synchronisation simulée, horloge fixe.
class UiEnv {
  UiEnv({DateTime? now})
      : now = now ?? DateTime.utc(2026, 10, 4, 12),
        db = AppDatabase.openInMemory(hexKey: testKey) {
    repo = LedgerRepository(db: db, clock: () => this.now);
    ledger = LedgerStore(db);
    outbox = OutboxStore(db);
  }

  DateTime now;
  final AppDatabase db;
  late final LedgerRepository repo;
  late final LedgerStore ledger;
  late final OutboxStore outbox;
  final MockBackendApi api = MockBackendApi();
  final FakeSyncControl sync = FakeSyncControl();
  final InMemorySecretStore secrets = InMemorySecretStore();

  List<Override> overrides(SessionState session) => <Override>[
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
        secretStoreProvider.overrideWithValue(secrets),
        backendApiProvider.overrideWithValue(api),
        syncControlProvider.overrideWithValue(sync),
        connectivityProvider.overrideWithValue(FakeConnectivityService()),
        initialSessionProvider.overrideWithValue(session),
      ];

  void dispose() => db.close();
}

/// Tous les motifs d'adresses de l'application : ceux qui ne sont pas fournis
/// par le test affichent « ROUTE: » suivi de l'adresse (on vérifie ainsi les navigations).
const List<String> _allPatterns = <String>[
  Routes.welcome,
  Routes.login,
  Routes.signup,
  Routes.signupCode,
  Routes.signupPin,
  Routes.customers,
  Routes.dashboard,
  Routes.settings,
  Routes.customerNew,
  '/customers/:id',
  '/customers/:id/edit',
  '/customers/:id/debts/new',
  '/debts/:id',
  '/debts/:id/edit',
  Routes.subscription,
  Routes.reminderRules,
  Routes.changePin,
  Routes.businessName,
  Routes.syncIssues,
];

typedef ScreenBuilder = Widget Function(GoRouterState state);

class AppHandle {
  AppHandle(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  String get location => router.routerDelegate.currentConfiguration.uri.toString();
}

/// Monte [screens] (motif → écran) dans une application de test.
Widget buildTestApp(
  UiEnv env, {
  required String initialLocation,
  required Map<String, ScreenBuilder> screens,
  SessionState session = const SignedIn(testProfile),
  void Function(ProviderContainer container, GoRouter router)? onReady,
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
  List<Override> extraOverrides = const <Override>[],
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      for (final pattern in _allPatterns)
        GoRoute(
          path: pattern,
          builder: (context, state) =>
              screens[pattern]?.call(state) ?? Scaffold(body: Center(child: Text('ROUTE:${state.uri}'))),
        ),
    ],
  );
  return ProviderScope(
    overrides: <Override>[...env.overrides(session), ...extraOverrides],
    child: Consumer(
      builder: (context, ref, _) {
        onReady?.call(ProviderScope.containerOf(context), router);
        return MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          routerConfig: router,
          locale: const Locale('fr'),
          supportedLocales: const <Locale>[Locale('fr')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        );
      },
    ),
  );
}

/// Écran de téléphone courant (390 × 844) : les boutons du bas restent atteignables.
void phoneScreen(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
