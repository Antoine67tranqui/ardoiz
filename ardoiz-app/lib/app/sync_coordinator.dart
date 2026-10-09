import 'dart:async';

import '../core/clock.dart';
import '../data/local/app_database.dart';
import '../data/local/ledger_store.dart';
import '../data/local/outbox_store.dart';
import '../data/sync/sync_engine.dart';
import 'connectivity.dart';

class SyncState {
  const SyncState({
    this.syncing = false,
    this.online = true,
    this.pending = 0,
    this.blocked = 0,
    this.lastSyncAt,
    this.lastStop = SyncStop.none,
  });

  final bool syncing;
  final bool online;

  /// Modifications locales pas encore envoyées.
  final int pending;

  /// Modifications refusées par le serveur, en attente d'une décision.
  final int blocked;
  final DateTime? lastSyncAt;
  final SyncStop lastStop;

  SyncState copyWith({
    bool? syncing,
    bool? online,
    int? pending,
    int? blocked,
    DateTime? lastSyncAt,
    SyncStop? lastStop,
  }) =>
      SyncState(
        syncing: syncing ?? this.syncing,
        online: online ?? this.online,
        pending: pending ?? this.pending,
        blocked: blocked ?? this.blocked,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastStop: lastStop ?? this.lastStop,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.syncing == syncing &&
      other.online == online &&
      other.pending == pending &&
      other.blocked == blocked &&
      other.lastSyncAt == lastSyncAt &&
      other.lastStop == lastStop;

  @override
  int get hashCode => Object.hash(syncing, online, pending, blocked, lastSyncAt, lastStop);
}

/// Ce que l'interface voit de la synchronisation (simulable dans les tests).
abstract interface class SyncControl {
  SyncState get state;
  Stream<SyncState> get states;

  /// Démarre les déclencheurs automatiques (une session est ouverte). Sans effet si déjà démarré.
  Future<void> start();

  /// Synchronise maintenant (bouton, tirer pour rafraîchir).
  Future<void> syncNow();
}

/// Déclenche la synchronisation au bon moment : au démarrage, au retour du
/// réseau, après une saisie locale (légèrement différé pour grouper les
/// frappes), périodiquement, et à l'échéance d'une reprise après échec.
///
/// Les écritures de la synchronisation elle-même ne la redéclenchent pas :
/// seules les opérations réellement à envoyer le font.
class SyncCoordinator implements SyncControl {
  SyncCoordinator({
    required this._engine,
    required AppDatabase db,
    required this._connectivity,
    required this.onUnauthorized,
    this.clock = systemClock,
    this.debounce = const Duration(milliseconds: 1500),
    this.period = const Duration(seconds: 60),
  })  : _db = db,
        _outbox = OutboxStore(db),
        _ledger = LedgerStore(db);

  final SyncEngine _engine;
  final AppDatabase _db;
  final ConnectivityService _connectivity;
  final OutboxStore _outbox;
  final LedgerStore _ledger;
  final Clock clock;
  final Duration debounce;
  final Duration period;

  /// Appelé quand le serveur refuse la session (jetons invalides).
  final void Function() onUnauthorized;

  final StreamController<SyncState> _states = StreamController<SyncState>.broadcast();
  SyncState _state = const SyncState();
  StreamSubscription<void>? _changes;
  StreamSubscription<bool>? _connectivitySub;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  Timer? _retryTimer;
  bool _running = false;
  bool _again = false;
  bool _started = false;
  bool _disposed = false;

  @override
  SyncState get state => _state;
  @override
  Stream<SyncState> get states => _states.stream;

  /// Démarre les déclencheurs et lance une première synchronisation.
  @override
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _outbox.resetInFlight();
    final online = await _connectivity.isOnline;
    _emit(_snapshot(online: online));

    _changes = _db.changes.listen((_) {
      if (_running) return; // nos propres écritures ne nous réveillent pas
      _emit(_snapshot());
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, () => unawaited(_syncIfWork()));
    });
    _connectivitySub = _connectivity.onChanged.listen((online) {
      _emit(_state.copyWith(online: online));
      if (online) unawaited(syncNow());
    });
    _periodicTimer = Timer.periodic(period, (_) => unawaited(_syncIfWork(orPull: true)));

    if (online) await syncNow();
  }

  Future<void> _syncIfWork({bool orPull = false}) async {
    if (_disposed || !_state.online) return;
    if (orPull || _outbox.due(clock()).isNotEmpty) await syncNow();
  }

  /// Un appel pendant une passe en cours demande une passe supplémentaire, sans doublon.
  @override
  Future<void> syncNow() async {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _emit(_snapshot().copyWith(syncing: true));
    try {
      var passes = 0;
      SyncReport report;
      do {
        _again = false;
        report = await _engine.run();
        passes++;
        _handle(report);
        // Des saisies faites pendant la passe partent tout de suite.
      } while (!_disposed && passes < 5 && report.stop == SyncStop.none && (_again || _outbox.due(clock()).isNotEmpty));
    } on Object {
      _emit(_snapshot().copyWith(lastStop: SyncStop.server));
    } finally {
      _running = false;
      if (!_disposed) _emit(_snapshot().copyWith(syncing: false));
    }
  }

  void _handle(SyncReport report) {
    _retryTimer?.cancel();
    if (report.stop == SyncStop.unauthorized) {
      onUnauthorized();
      return;
    }
    final retryAt = report.retryAt;
    if (retryAt != null) {
      final delay = retryAt.difference(clock());
      _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () => unawaited(syncNow()));
    }
    final raw = _ledger.meta(SyncEngine.lastSyncMetaKey);
    _emit(_snapshot().copyWith(
      lastStop: report.stop,
      lastSyncAt: raw == null ? null : DateTime.parse(raw),
      online: report.stop == SyncStop.network ? false : (report.completed ? true : _state.online),
    ));
  }

  SyncState _snapshot({bool? online}) => SyncState(
        syncing: _state.syncing,
        online: online ?? _state.online,
        pending: _outbox.count(status: OutboxStatus.pending) + _outbox.count(status: OutboxStatus.inFlight),
        blocked: _outbox.count(status: OutboxStatus.blocked),
        lastSyncAt: _state.lastSyncAt,
        lastStop: _state.lastStop,
      );

  void _emit(SyncState next) {
    if (_disposed || next == _state) return;
    _state = next;
    _states.add(next);
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _retryTimer?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_connectivitySub?.cancel());
    unawaited(_states.close());
  }
}
