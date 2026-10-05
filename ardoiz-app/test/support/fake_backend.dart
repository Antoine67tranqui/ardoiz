import 'package:ardoiz/core/money.dart';
import 'package:ardoiz/data/local/outbox_store.dart';
import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/sync/ledger_transport.dart';
import 'package:ardoiz/domain/models.dart';

/// Faux serveur en mémoire qui reproduit les règles du vrai backend : créations
/// idempotentes par id client, 404 sur suppression d'un élément absent,
/// rejet des sur-paiements, plafond du plan gratuit, cascade des suppressions.
/// Sa fidélité est vérifiée par la suite de tests de contrat (test/contract),
/// exécutée aussi contre le vrai backend.
class FakeBackend implements LedgerTransport {
  final Map<String, Customer> customers = <String, Customer>{};
  final Map<String, Debt> debts = <String, Debt>{};
  final Map<String, Payment> payments = <String, Payment>{};
  final Map<String, CashEntry> cashEntries = <String, CashEntry>{};

  /// Journal des opérations reçues (id, nature).
  final List<String> log = <String>[];

  int freePlanCustomerLimit = 15;

  /// Pannes injectables : l'appel numéro N (1-based) échoue avec cette exception.
  final Map<int, ApiException> failures = <int, ApiException>{};

  /// Si vrai, l'opération est traitée PUIS la réponse est perdue (échec ambigu).
  bool loseNextResponse = false;

  /// Panne durable : tant qu'elle est définie, tout appel échoue.
  ApiException? downWith;

  int calls = 0;
  DateTime Function() now = DateTime.now;

  @override
  Future<void> send(OutboxEntry entry) async {
    calls++;
    final failure = downWith ?? failures[calls];
    if (failure != null) throw failure;

    _apply(entry);

    if (loseNextResponse) {
      loseNextResponse = false;
      throw const NetworkException('Réponse perdue.');
    }
  }

  @override
  Future<RemoteSnapshot> snapshot() async {
    calls++;
    final failure = downWith ?? failures[calls];
    if (failure != null) throw failure;
    return RemoteSnapshot(
      serverTime: now().toUtc(),
      customers: customers.values.toList(),
      debts: debts.values.toList(),
      payments: payments.values.toList(),
      cashEntries: cashEntries.values.toList(),
    );
  }

  // ---- Règles métier du backend ----

  void _apply(OutboxEntry entry) {
    final id = entry.entityId;
    final p = entry.payload;
    log.add('${entry.entity.name}.${entry.op.name}:$id');

    switch ((entry.entity, entry.op)) {
      case (OutboxEntity.customer, OutboxOp.create):
        if (customers.containsKey(id)) return; // idempotent : rejeu
        final kind = PartyKind.fromWire(p['kind'] as String?);
        if (customers.values.where((c) => c.kind == kind).length >= freePlanCustomerLimit) {
          throw RejectedException(
            403,
            'Le plan gratuit est limite a 15 ${kind == PartyKind.supplier ? 'fournisseurs' : 'clients'}.',
            code: 'FREE_PLAN_LIMIT_REACHED',
          );
        }
        customers[id] = Customer(
          id: id,
          name: p['name']! as String,
          phone: p['phone']! as String,
          creditLimit: p['creditLimitCents'] == null ? null : Money.fromCents(p['creditLimitCents']! as int),
          createdAt: now().toUtc(),
          kind: kind,
          reminderOptOut: p['reminderOptOut'] == true,
        );
      case (OutboxEntity.customer, OutboxOp.update):
        final current = customers[id] ?? (throw const RejectedException(404, 'Client introuvable'));
        customers[id] = Customer(
          id: id,
          name: p.containsKey('name') ? p['name']! as String : current.name,
          phone: p.containsKey('phone') ? p['phone']! as String : current.phone,
          creditLimit: p.containsKey('creditLimitCents')
              ? (p['creditLimitCents'] == null ? null : Money.fromCents(p['creditLimitCents']! as int))
              : current.creditLimit,
          createdAt: current.createdAt,
          kind: current.kind,
          reminderOptOut: p.containsKey('reminderOptOut') ? p['reminderOptOut']! as bool : current.reminderOptOut,
        );
      case (OutboxEntity.customer, OutboxOp.delete):
        if (customers.remove(id) == null) throw const RejectedException(404, 'Client introuvable');
        final debtIds = debts.values.where((d) => d.customerId == id).map((d) => d.id).toList();
        for (final debtId in debtIds) {
          debts.remove(debtId);
          payments.removeWhere((_, pay) => pay.debtId == debtId);
        }
      case (OutboxEntity.debt, OutboxOp.create):
        if (debts.containsKey(id)) return;
        if (!customers.containsKey(p['customerId'])) throw const RejectedException(404, 'Client introuvable');
        debts[id] = Debt(
          id: id,
          customerId: p['customerId']! as String,
          amount: Money.fromCents(p['amountCents']! as int),
          reason: p['reason'] as String?,
          category: p['category']! as String,
          dueDate: p['dueDate'] == null ? null : DateTime.parse(p['dueDate']! as String),
          createdAt: DateTime.parse(p['createdAt']! as String),
        );
      case (OutboxEntity.debt, OutboxOp.update):
        final current = debts[id] ?? (throw const RejectedException(404, 'Dette introuvable'));
        final amount = p.containsKey('amountCents') ? Money.fromCents(p['amountCents']! as int) : current.amount;
        final paid = Money.sum(payments.values.where((x) => x.debtId == id).map((x) => x.amount));
        if (amount < paid) {
          throw const RejectedException(400, 'Montant inférieur aux paiements.', code: 'AMOUNT_BELOW_PAYMENTS');
        }
        debts[id] = Debt(
          id: id,
          customerId: current.customerId,
          amount: amount,
          reason: p.containsKey('reason') ? p['reason'] as String? : current.reason,
          category: p.containsKey('category') ? p['category']! as String : current.category,
          dueDate: p.containsKey('dueDate')
              ? (p['dueDate'] == null ? null : DateTime.parse(p['dueDate']! as String))
              : current.dueDate,
          createdAt: current.createdAt,
        );
      case (OutboxEntity.debt, OutboxOp.delete):
        if (debts.remove(id) == null) throw const RejectedException(404, 'Dette introuvable');
        payments.removeWhere((_, pay) => pay.debtId == id);
      case (OutboxEntity.payment, OutboxOp.create):
        if (payments.containsKey(id)) return;
        final debt = debts[p['debtId']] ?? (throw const RejectedException(404, 'Dette introuvable'));
        final amount = Money.fromCents(p['amountCents']! as int);
        final paid = Money.sum(payments.values.where((x) => x.debtId == debt.id).map((x) => x.amount));
        if (amount > debt.amount - paid) {
          throw const RejectedException(400, 'Montant supérieur au solde.', code: 'OVERPAYMENT');
        }
        payments[id] = Payment(
          id: id,
          debtId: debt.id,
          amount: amount,
          method: PaymentMethod.fromWire(p['method']! as String),
          paidAt: DateTime.parse(p['paidAt']! as String),
        );
      case (OutboxEntity.payment, OutboxOp.update):
        throw StateError('Les paiements ne se modifient pas.');
      case (OutboxEntity.payment, OutboxOp.delete):
        if (payments.remove(id) == null) throw const RejectedException(404, 'Paiement introuvable');
      case (OutboxEntity.cashEntry, OutboxOp.create):
        if (cashEntries.containsKey(id)) return;
        cashEntries[id] = CashEntry(
          id: id,
          type: CashType.fromWire(p['type']! as String),
          amount: Money.fromCents(p['amountCents']! as int),
          label: p['label'] as String?,
          category: p['category']! as String,
          occurredAt: DateTime.parse(p['occurredAt']! as String),
        );
      case (OutboxEntity.cashEntry, OutboxOp.update):
        final current = cashEntries[id] ?? (throw const RejectedException(404, 'Écriture introuvable'));
        cashEntries[id] = CashEntry(
          id: id,
          type: current.type,
          amount: p.containsKey('amountCents') ? Money.fromCents(p['amountCents']! as int) : current.amount,
          label: p.containsKey('label') ? p['label'] as String? : current.label,
          category: p.containsKey('category') ? p['category']! as String : current.category,
          occurredAt: p.containsKey('occurredAt') ? DateTime.parse(p['occurredAt']! as String) : current.occurredAt,
        );
      case (OutboxEntity.cashEntry, OutboxOp.delete):
        if (cashEntries.remove(id) == null) throw const RejectedException(404, 'Écriture introuvable');
    }
  }

  // ---- Aides de test (état serveur modifié « depuis un autre appareil ») ----

  void seedCustomer(Customer customer) => customers[customer.id] = customer;
  void seedDebt(Debt debt) => debts[debt.id] = debt;
  void seedPayment(Payment payment) => payments[payment.id] = payment;
  void seedCash(CashEntry entry) => cashEntries[entry.id] = entry;
}
