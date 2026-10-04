import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../core/validators.dart';
import '../../domain/ledger.dart';
import '../../domain/models.dart';
import '../local/app_database.dart';
import '../local/ledger_store.dart';
import '../local/outbox_store.dart';

/// Saisie refusée par une règle métier (message prêt à afficher).
class DomainException implements Exception {
  const DomainException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Une opération refusée par le serveur, en attente d'une décision.
class SyncIssue {
  const SyncIssue({required this.entry, required this.title, required this.reason});

  final OutboxEntry entry;
  final String title;
  final String reason;
}

/// Toutes les écritures sont locales et immédiates : chaque modification est
/// enregistrée avec son opération d'envoi dans UNE transaction, l'interface
/// n'attend jamais le réseau.
class LedgerRepository {
  LedgerRepository({
    required AppDatabase db,
    this._clock = systemClock,
    this._uuid = const Uuid(),
  })  : _db = db,
        _ledger = LedgerStore(db),
        _outbox = OutboxStore(db);

  final AppDatabase _db;
  final Clock _clock;
  final Uuid _uuid;
  final LedgerStore _ledger;
  final OutboxStore _outbox;

  // ---- Lecture ----

  List<CustomerView> customers() => Ledger.customerViews(
        customers: _ledger.customers(),
        debts: _ledger.debts(),
        payments: _ledger.payments(),
        pendingIds: _outbox.entityIds(),
        now: _clock(),
      );

  CustomerView? customer(String id) {
    for (final view in customers()) {
      if (view.customer.id == id) return view;
    }
    return null;
  }

  DebtView? debt(String id) {
    for (final customer in customers()) {
      for (final debt in customer.debts) {
        if (debt.debt.id == id) return debt;
      }
    }
    return null;
  }

  /// Émet la liste à jour à chaque modification de la base (écritures locales
  /// comme réception d'une synchronisation).
  Stream<List<CustomerView>> watchCustomers() async* {
    yield customers();
    await for (final _ in _db.changes) {
      yield customers();
    }
  }

  // ---- Clients ----

  Customer addCustomer({required String name, required String phone, Money? creditLimit}) {
    _check(Validators.customerName(name));
    _check(Validators.customerPhone(phone));
    _checkLimit(creditLimit);
    final customer = Customer(
      id: _uuid.v4(),
      name: name.trim(),
      phone: phone.trim(),
      creditLimit: creditLimit,
      createdAt: _clock().toUtc(),
    );
    _db.write((_) {
      _ledger.upsertCustomer(customer);
      _outbox.enqueue(
        entity: OutboxEntity.customer,
        entityId: customer.id,
        op: OutboxOp.create,
        now: _clock(),
        payload: <String, Object?>{
          'name': customer.name,
          'phone': customer.phone,
          'creditLimitCents': creditLimit?.cents,
        },
      );
    });
    return customer;
  }

  Customer updateCustomer(
    String id, {
    String? name,
    String? phone,
    Money? creditLimit,
    bool clearCreditLimit = false,
  }) {
    final current = _ledger.customer(id) ?? (throw const DomainException('Client introuvable.'));
    if (name != null) _check(Validators.customerName(name));
    if (phone != null) _check(Validators.customerPhone(phone));
    _checkLimit(creditLimit);
    final updated = current.copyWith(
      name: name?.trim(),
      phone: phone?.trim(),
      creditLimit: creditLimit,
      clearCreditLimit: clearCreditLimit,
    );
    _db.write((_) {
      _ledger.upsertCustomer(updated);
      _outbox.enqueue(
        entity: OutboxEntity.customer,
        entityId: id,
        op: OutboxOp.update,
        now: _clock(),
        payload: <String, Object?>{
          if (name != null) 'name': updated.name,
          if (phone != null) 'phone': updated.phone,
          if (creditLimit != null || clearCreditLimit) 'creditLimitCents': updated.creditLimit?.cents,
        },
      );
    });
    return updated;
  }

  void deleteCustomer(String id) {
    if (_ledger.customer(id) == null) return;
    _db.write((_) {
      _outbox.enqueue(
        entity: OutboxEntity.customer,
        entityId: id,
        op: OutboxOp.delete,
        now: _clock(),
        descendantIds: <String>{..._ledger.debtIdsOfCustomer(id), ..._ledger.paymentIdsOfCustomer(id)},
      );
      _ledger.deleteCustomer(id);
    });
  }

  // ---- Dettes ----

  Debt addDebt({
    required String customerId,
    required Money amount,
    String? reason,
    String? category,
    DateTime? dueDate,
  }) {
    if (_ledger.customer(customerId) == null) throw const DomainException('Client introuvable.');
    _checkAmount(amount);
    _check(Validators.reason(reason));
    final cleanCategory = (category ?? '').trim().isEmpty ? fallbackDebtCategory : category!.trim();
    _check(Validators.category(cleanCategory));
    final cleanReason = (reason ?? '').trim().isEmpty ? null : reason!.trim();

    final now = _clock().toUtc();
    final debt = Debt(
      id: _uuid.v4(),
      customerId: customerId,
      amount: amount,
      reason: cleanReason,
      category: cleanCategory,
      dueDate: dueDate?.toUtc(),
      createdAt: now,
    );
    _db.write((_) {
      _ledger.upsertDebt(debt);
      _outbox.enqueue(
        entity: OutboxEntity.debt,
        entityId: debt.id,
        op: OutboxOp.create,
        now: now,
        payload: <String, Object?>{
          'customerId': customerId,
          'amountCents': amount.cents,
          'reason': cleanReason,
          'category': cleanCategory,
          'dueDate': debt.dueDate?.toIso8601String(),
          'createdAt': now.toIso8601String(),
        },
      );
    });
    return debt;
  }

  /// Corrige une dette. [reason] et [dueDate] à null avec leur `clear*` effacent la valeur.
  Debt updateDebt(
    String id, {
    Money? amount,
    String? reason,
    bool clearReason = false,
    String? category,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) {
    final view = debt(id) ?? (throw const DomainException('Dette introuvable.'));
    if (amount != null) {
      _checkAmount(amount);
      if (amount < view.paid) {
        throw DomainException('Le montant ne peut pas être inférieur aux paiements déjà reçus (${formatMoney(view.paid)}).');
      }
    }
    _check(Validators.reason(reason));
    if (category != null) _check(Validators.category(category));

    final current = view.debt;
    final cleanReason = clearReason ? null : ((reason ?? '').trim().isEmpty ? current.reason : reason!.trim());
    final updated = Debt(
      id: current.id,
      customerId: current.customerId,
      amount: amount ?? current.amount,
      reason: cleanReason,
      category: category?.trim() ?? current.category,
      dueDate: clearDueDate ? null : (dueDate?.toUtc() ?? current.dueDate),
      createdAt: current.createdAt,
    );
    _db.write((_) {
      _ledger.upsertDebt(updated);
      _outbox.enqueue(
        entity: OutboxEntity.debt,
        entityId: id,
        op: OutboxOp.update,
        now: _clock(),
        payload: <String, Object?>{
          if (amount != null) 'amountCents': amount.cents,
          if (clearReason || (reason ?? '').trim().isNotEmpty) 'reason': cleanReason,
          if (category != null) 'category': updated.category,
          if (clearDueDate || dueDate != null) 'dueDate': updated.dueDate?.toIso8601String(),
        },
      );
    });
    return updated;
  }

  void deleteDebt(String id) {
    if (_ledger.debt(id) == null) return;
    _db.write((_) {
      _outbox.enqueue(
        entity: OutboxEntity.debt,
        entityId: id,
        op: OutboxOp.delete,
        now: _clock(),
        descendantIds: _ledger.paymentIdsOfDebt(id),
      );
      _ledger.deleteDebt(id);
    });
  }

  // ---- Paiements ----

  /// Enregistre un remboursement en espèces ([amount] au plus égal au solde restant).
  Payment addPayment({required String debtId, required Money amount, DateTime? paidAt}) {
    final view = debt(debtId) ?? (throw const DomainException('Dette introuvable.'));
    _checkAmount(amount);
    if (view.remaining.isZero) throw const DomainException('Cette dette est déjà soldée.');
    if (amount > view.remaining) {
      throw DomainException('Le montant dépasse le solde restant (${formatMoney(view.remaining)}).');
    }
    final now = _clock().toUtc();
    final payment = Payment(
      id: _uuid.v4(),
      debtId: debtId,
      amount: amount,
      method: PaymentMethod.cash,
      paidAt: (paidAt ?? now).toUtc(),
    );
    _db.write((_) {
      _ledger.upsertPayment(payment);
      _outbox.enqueue(
        entity: OutboxEntity.payment,
        entityId: payment.id,
        op: OutboxOp.create,
        now: now,
        payload: <String, Object?>{
          'debtId': debtId,
          'amountCents': amount.cents,
          'method': payment.method.wire,
          'paidAt': payment.paidAt.toIso8601String(),
        },
      );
    });
    return payment;
  }

  void deletePayment(String id) {
    if (_ledger.payment(id) == null) return;
    _db.write((_) {
      _outbox.enqueue(entity: OutboxEntity.payment, entityId: id, op: OutboxOp.delete, now: _clock());
      _ledger.deletePayment(id);
    });
  }

  // ---- Problèmes de synchronisation ----

  int pendingCount() => _outbox.count(status: OutboxStatus.pending) + _outbox.count(status: OutboxStatus.inFlight);

  int blockedCount() => _outbox.count(status: OutboxStatus.blocked);

  List<SyncIssue> issues() => _outbox.blocked().map((entry) {
        return SyncIssue(entry: entry, title: _describe(entry), reason: entry.lastError ?? 'Refusé par le serveur.');
      }).toList();

  Stream<List<SyncIssue>> watchIssues() async* {
    yield issues();
    await for (final _ in _db.changes) {
      yield issues();
    }
  }

  void retryIssue(OutboxEntry entry) => _outbox.retry(entry);

  /// Abandonne une opération refusée : annule ses effets locaux (une création
  /// refusée disparaît de l'écran ; une modification redevient celle du serveur
  /// à la prochaine synchronisation).
  void discardIssue(OutboxEntry entry) => _db.write((_) {
        for (final removed in _outbox.discard(entry)) {
          if (removed.op != OutboxOp.create) continue;
          switch (removed.entity) {
            case OutboxEntity.customer:
              _ledger.deleteCustomer(removed.entityId);
            case OutboxEntity.debt:
              _ledger.deleteDebt(removed.entityId);
            case OutboxEntity.payment:
              _ledger.deletePayment(removed.entityId);
          }
        }
      });

  // ---- Interne ----

  String _describe(OutboxEntry entry) {
    final p = entry.payload;
    return switch ((entry.entity, entry.op)) {
      (OutboxEntity.customer, OutboxOp.create) => 'Nouveau client « ${p['name']} »',
      (OutboxEntity.customer, OutboxOp.update) => 'Modification du client « ${_ledger.customer(entry.entityId)?.name ?? 'client'} »',
      (OutboxEntity.customer, OutboxOp.delete) => 'Suppression d\'un client',
      (OutboxEntity.debt, OutboxOp.create) => 'Nouvelle dette de ${formatMoney(Money.fromCents(p['amountCents']! as int))}${_forCustomer(p['customerId'])}',
      (OutboxEntity.debt, OutboxOp.update) => 'Modification d\'une dette',
      (OutboxEntity.debt, OutboxOp.delete) => 'Suppression d\'une dette',
      (OutboxEntity.payment, OutboxOp.create) => 'Remboursement de ${formatMoney(Money.fromCents(p['amountCents']! as int))}',
      (OutboxEntity.payment, OutboxOp.update) => 'Modification d\'un remboursement',
      (OutboxEntity.payment, OutboxOp.delete) => 'Suppression d\'un remboursement',
    };
  }

  String _forCustomer(Object? customerId) {
    final name = customerId is String ? _ledger.customer(customerId)?.name : null;
    return name == null ? '' : ' pour $name';
  }

  void _check(String? error) {
    if (error != null) throw DomainException(error);
  }

  void _checkAmount(Money amount) {
    if (!amount.isPositive) throw const DomainException('Le montant doit être supérieur à zéro.');
    if (amount > Money.max) throw const DomainException('Montant trop élevé.');
  }

  void _checkLimit(Money? limit) {
    if (limit == null) return;
    if (limit.cents < 0 || limit > Money.max) throw const DomainException('Plafond de crédit invalide.');
  }
}
