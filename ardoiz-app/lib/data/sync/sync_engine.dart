import 'dart:async';
import 'dart:math';

import '../../core/clock.dart';
import '../local/app_database.dart';
import '../local/ledger_store.dart';
import '../local/outbox_store.dart';
import '../remote/api_exceptions.dart';
import 'ledger_transport.dart';

/// Pourquoi une synchronisation s'est arrêtée avant la fin.
enum SyncStop { none, network, server, unauthorized }

class SyncReport {
  const SyncReport({
    this.sent = 0,
    this.newlyBlocked = 0,
    this.pulled = false,
    this.stop = SyncStop.none,
    this.retryAt,
  });

  /// Opérations envoyées avec succès.
  final int sent;

  /// Opérations refusées définitivement par le serveur pendant cette passe.
  final int newlyBlocked;

  /// L'état du serveur a été récupéré et appliqué au cache local.
  final bool pulled;

  final SyncStop stop;

  /// Prochaine reprise automatique conseillée (après un échec temporaire).
  final DateTime? retryAt;

  bool get completed => stop == SyncStop.none;
}

/// Messages affichés au commerçant pour les refus serveur les plus courants.
String friendlyRejection(RejectedException error) => switch (error.code) {
      'FREE_PLAN_LIMIT_REACHED' => error.message.contains('fournisseurs')
          ? 'Le plan gratuit est limité à 15 fournisseurs. Passez à Premium ou supprimez un fournisseur.'
          : 'Le plan gratuit est limité à 15 clients. Passez à Premium ou supprimez un client.',
      'OVERPAYMENT' => 'Le montant dépasse le solde restant de la dette sur le serveur.',
      'AMOUNT_BELOW_PAYMENTS' => 'Le montant est inférieur aux paiements déjà reçus sur le serveur.',
      _ => switch (error.statusCode) {
          404 => 'Élément introuvable sur le serveur (supprimé depuis un autre appareil ?).',
          409 => 'Cet élément existe déjà sur le serveur sous un autre compte.',
          _ => error.message,
        },
    };

/// Moteur de synchronisation : rejoue la file d'envoi dans l'ordre, puis aligne
/// le cache local sur l'état du serveur.
///
/// Règles de conflit : les modifications locales en attente l'emportent tant
/// qu'elles ne sont pas envoyées (le serveur n'écrase jamais une entité qui a
/// une opération en attente), puis le serveur fait foi. Chaque envoi est
/// idempotent (ids générés par l'app), donc rejouable sans risque après un
/// échec ambigu (réponse perdue après traitement par le serveur).
class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required this._transport,
    this._clock = systemClock,
    Random? random,
    this.maxBackoff = const Duration(minutes: 5),
    this.baseBackoff = const Duration(seconds: 5),
  })  : _db = db,
        _random = random ?? Random(),
        _outbox = OutboxStore(db),
        _ledger = LedgerStore(db);

  final AppDatabase _db;
  final LedgerTransport _transport;
  final Clock _clock;
  final Random _random;
  final OutboxStore _outbox;
  final LedgerStore _ledger;
  final Duration maxBackoff;
  final Duration baseBackoff;

  Future<SyncReport>? _running;

  static const String lastSyncMetaKey = 'last_sync_at';

  /// Une seule synchronisation à la fois : un appel pendant une passe en cours
  /// rejoint cette passe.
  Future<SyncReport> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<SyncReport> _run() async {
    // Une passe n'est jamais en cours ici (single-flight) : aucun envoi ne peut être "en cours".
    _outbox.resetInFlight();
    var sent = 0;
    var newlyBlocked = 0;

    // La liste est relue à chaque tour : un refus définitif bloque aussi les
    // opérations qui en dépendent, elles ne doivent pas être envoyées.
    while (true) {
      final entry = _outbox.due(_clock()).firstOrNull;
      if (entry == null) break;
      _outbox.markInFlight(entry.seq);
      try {
        await _transport.send(entry);
        _outbox.complete(entry.seq);
        sent++;
      } on UnauthorizedException {
        _outbox.markPending(entry.seq);
        return SyncReport(sent: sent, newlyBlocked: newlyBlocked, stop: SyncStop.unauthorized);
      } on NetworkException catch (error) {
        return _retryLater(entry, error.message, SyncStop.network, sent, newlyBlocked);
      } on ServerException catch (error) {
        return _retryLater(entry, error.message, SyncStop.server, sent, newlyBlocked);
      } on RejectedException catch (error) {
        if (error.isNotFound && entry.op != OutboxOp.create) {
          // Déjà supprimé côté serveur : l'effet voulu est atteint.
          _outbox.complete(entry.seq);
          sent++;
        } else {
          _outbox.block(entry, friendlyRejection(error));
          newlyBlocked++;
        }
      }
    }

    try {
      final snapshot = await _transport.snapshot();
      _apply(snapshot);
      return SyncReport(sent: sent, newlyBlocked: newlyBlocked, pulled: true, retryAt: _outbox.nextRetryAt());
    } on UnauthorizedException {
      return SyncReport(sent: sent, newlyBlocked: newlyBlocked, stop: SyncStop.unauthorized);
    } on NetworkException {
      return SyncReport(sent: sent, newlyBlocked: newlyBlocked, stop: SyncStop.network);
    } on ServerException {
      return SyncReport(sent: sent, newlyBlocked: newlyBlocked, stop: SyncStop.server);
    }
  }

  SyncReport _retryLater(OutboxEntry entry, String error, SyncStop stop, int sent, int newlyBlocked) {
    final retryAt = _clock().add(_backoff(entry.attempts));
    _outbox.recordFailure(entry.seq, error: error, nextAttemptAt: retryAt);
    return SyncReport(sent: sent, newlyBlocked: newlyBlocked, stop: stop, retryAt: retryAt);
  }

  /// 5 s, 10 s, 20 s... plafonné, avec ±20 % d'aléa pour que les appareils
  /// ne retentent pas tous au même instant après une panne serveur.
  Duration _backoff(int attempts) {
    final exponential = baseBackoff.inMilliseconds * pow(2, min(attempts, 20));
    final capped = min(exponential, maxBackoff.inMilliseconds.toDouble());
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    return Duration(milliseconds: (capped * jitter).round());
  }

  /// Aligne le cache local sur le serveur, en une transaction : les entités
  /// ayant des envois en attente (ou bloqués) ne sont jamais touchées.
  void _apply(RemoteSnapshot snapshot) {
    _db.write((_) {
      final protectedIds = _outbox.entityIds();
      final localCustomers = _ledger.customers();
      final localDebts = _ledger.debts();
      final localPayments = _ledger.payments();
      final localCash = _ledger.cashEntries();

      // Un parent est protégé dès qu'un de ses descendants l'est (supprimer le
      // parent ferait disparaître, en cascade, une saisie pas encore envoyée).
      final debtParent = {for (final d in localDebts) d.id: d.customerId};
      final paymentParent = {for (final p in localPayments) p.id: p.debtId};
      final protectedDebts = <String>{
        ...protectedIds,
        for (final p in protectedIds)
          if (paymentParent[p] != null) paymentParent[p]!,
      };
      final protectedCustomers = <String>{
        ...protectedIds,
        for (final d in protectedDebts)
          if (debtParent[d] != null) debtParent[d]!,
      };

      final serverCustomerIds = snapshot.customers.map((c) => c.id).toSet();
      final serverDebtIds = snapshot.debts.map((d) => d.id).toSet();
      final serverPaymentIds = snapshot.payments.map((p) => p.id).toSet();
      final serverCashIds = snapshot.cashEntries.map((e) => e.id).toSet();

      // Suppressions : ce qui a disparu du serveur (supprimé ailleurs).
      for (final p in localPayments) {
        if (!serverPaymentIds.contains(p.id) && !protectedIds.contains(p.id)) _ledger.deletePayment(p.id);
      }
      for (final d in localDebts) {
        if (!serverDebtIds.contains(d.id) && !protectedDebts.contains(d.id)) _ledger.deleteDebt(d.id);
      }
      for (final c in localCustomers) {
        if (!serverCustomerIds.contains(c.id) && !protectedCustomers.contains(c.id)) _ledger.deleteCustomer(c.id);
      }

      for (final e in localCash) {
        if (!serverCashIds.contains(e.id) && !protectedIds.contains(e.id)) _ledger.deleteCashEntry(e.id);
      }

      // Insertions / mises à jour, parents d'abord.
      for (final customer in snapshot.customers) {
        if (!protectedIds.contains(customer.id)) _ledger.upsertCustomer(customer);
      }
      for (final debt in snapshot.debts) {
        if (protectedIds.contains(debt.id)) continue;
        if (_ledger.customer(debt.customerId) == null) continue; // parent supprimé localement, envoi en attente
        _ledger.upsertDebt(debt);
      }
      for (final payment in snapshot.payments) {
        if (protectedIds.contains(payment.id)) continue;
        if (_ledger.debt(payment.debtId) == null) continue;
        _ledger.upsertPayment(payment);
      }

      for (final entry in snapshot.cashEntries) {
        if (!protectedIds.contains(entry.id)) _ledger.upsertCashEntry(entry);
      }

      _ledger.setMeta(lastSyncMetaKey, snapshot.serverTime.toUtc().toIso8601String());
    });
  }
}
