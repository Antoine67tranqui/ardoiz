// Test d'intégration : l'app (base chiffrée, dépôt, moteur de synchronisation,
// client HTTP) contre le VRAI backend. Exécuté seulement si CARNE_BACKEND_URL
// est défini (ex. http://localhost:3998/api/v1), backend lancé hors production.
import 'dart:io';
import 'dart:math';

import 'package:ardoiz/core/money.dart';
import 'package:ardoiz/data/local/app_database.dart';
import 'package:ardoiz/data/local/ledger_store.dart';
import 'package:ardoiz/data/local/outbox_store.dart';
import 'package:ardoiz/data/local/secret_store.dart';
import 'package:ardoiz/data/remote/api_client.dart';
import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/remote/backend_api.dart';
import 'package:ardoiz/data/remote/token_store.dart';
import 'package:ardoiz/data/repositories/ledger_repository.dart';
import 'package:ardoiz/data/sync/ledger_transport.dart';
import 'package:ardoiz/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

final String? backendUrl = Platform.environment['CARNE_BACKEND_URL'];

/// Transport qui traite la requête côté serveur puis « perd » la réponse.
class LossyTransport implements LedgerTransport {
  LossyTransport(this._inner);

  final LedgerTransport _inner;
  bool loseNext = false;

  @override
  Future<void> send(OutboxEntry entry) async {
    await _inner.send(entry);
    if (loseNext) {
      loseNext = false;
      throw const NetworkException('Réponse perdue.');
    }
  }

  @override
  Future<RemoteSnapshot> snapshot() => _inner.snapshot();
}

/// Un appareil réel : stockage de jetons, client HTTP, base chiffrée, moteur.
class RealDevice {
  RealDevice(this.client, this.tokens, {LedgerTransport Function(LedgerTransport)? wrap}) : db = AppDatabase.openInMemory(hexKey: testKey) {
    final base = HttpLedgerTransport(client);
    transport = wrap == null ? base : wrap(base);
    repo = LedgerRepository(db: db);
    ledger = LedgerStore(db);
    outbox = OutboxStore(db);
    engine = SyncEngine(db: db, transport: transport, baseBackoff: Duration.zero);
  }

  final ApiClient client;
  final TokenStore tokens;
  final AppDatabase db;
  late final LedgerTransport transport;
  late final LedgerRepository repo;
  late final LedgerStore ledger;
  late final OutboxStore outbox;
  late final SyncEngine engine;

  Future<SyncReport> sync() => engine.run();
}

String uniquePhone() {
  final n = Random().nextInt(1000000).toString().padLeft(6, '0');
  return '+2290167$n';
}

ApiClient newClient(TokenStore tokens, {void Function()? onExpired}) =>
    ApiClient(baseUrl: backendUrl!, tokens: tokens, onSessionExpired: onExpired);

/// Inscrit un nouveau commerçant (OTP → PIN) et renvoie son identité.
Future<({String phone, String pin, TokenStore tokens, ApiClient client, BackendApi api})> signUp({String businessName = 'Boutique Test'}) async {
  final tokens = TokenStore(InMemorySecretStore());
  final client = newClient(tokens);
  final api = HttpBackendApi(client);
  final phone = uniquePhone();
  final otp = await api.requestOtp(phone);
  expect(otp.devCode, isNotNull, reason: 'le backend de test doit tourner hors production');
  final verification = await api.verifyOtp(phone, otp.devCode!);
  expect(verification.isNewUser, isTrue);
  final session = await api.setupPin(otpSessionToken: verification.otpSessionToken, businessName: businessName, pin: '1234');
  await tokens.save(accessToken: session.accessToken, refreshToken: session.refreshToken);
  return (phone: phone, pin: '1234', tokens: tokens, client: client, api: api);
}

/// Second appareil du même commerçant (connexion par PIN).
Future<RealDevice> secondDevice(String phone, String pin) async {
  final tokens = TokenStore(InMemorySecretStore());
  final client = newClient(tokens);
  final session = await HttpBackendApi(client).login(phone: phone, pin: pin);
  await tokens.save(accessToken: session.accessToken, refreshToken: session.refreshToken);
  return RealDevice(client, tokens);
}

void main() {
  final skip = backendUrl == null ? 'CARNE_BACKEND_URL non défini' : false;
  const customerPhone = '+229 01 67 07 70 27';

  test('parcours complet hors ligne puis synchronisation : mêmes ids, aucun doublon, appareil 2 identique', skip: skip, () async {
    final owner = await signUp();
    final a = RealDevice(owner.client, owner.tokens);

    final customer = a.repo.addCustomer(name: 'Aïcha Traoré', phone: customerPhone, creditLimit: fcfa(20000));
    final debt = a.repo.addDebt(customerId: customer.id, amount: const Money.fromCents(125050), reason: 'Riz + huile', category: 'Alimentation', dueDate: DateTime.now().add(const Duration(days: 7)));
    final payment = a.repo.addPayment(debtId: debt.id, amount: const Money.fromCents(25050));

    final report = await a.sync();
    expect(report.completed, isTrue);
    expect(report.sent, 3);
    expect(a.outbox.count(), 0);

    // Les identifiants locaux sont ceux du serveur (ancien bug : ids divergents → doublons).
    expect(a.ledger.customers().map((c) => c.id), [customer.id]);
    expect(a.ledger.debts().single.id, debt.id);
    expect(a.ledger.payments().single.id, payment.id);

    // Exactitude au centime, aller-retour complet.
    final view = a.repo.customer(customer.id)!;
    expect(view.debts.single.debt.amount, const Money.fromCents(125050));
    expect(view.outstanding, const Money.fromCents(100000));

    // Un second appareil récupère exactement le même état.
    final b = await secondDevice(owner.phone, owner.pin);
    await b.sync();
    expect(b.repo.customers().single.customer.name, 'Aïcha Traoré');
    expect(b.repo.customers().single.customer.creditLimit, fcfa(20000));
    expect(b.repo.customer(customer.id)!.outstanding, const Money.fromCents(100000));
    expect(b.repo.debt(debt.id)!.debt.reason, 'Riz + huile');
    expect(b.repo.debt(debt.id)!.payments.single.id, payment.id);
  });

  test('réponse perdue après traitement : le renvoi ne duplique ni client, ni dette, ni paiement', skip: skip, () async {
    final owner = await signUp();
    late LossyTransport lossy;
    final a = RealDevice(owner.client, owner.tokens, wrap: (base) => lossy = LossyTransport(base));

    final customer = a.repo.addCustomer(name: 'Bako', phone: customerPhone);
    final debt = a.repo.addDebt(customerId: customer.id, amount: fcfa(5000));
    final payment = a.repo.addPayment(debtId: debt.id, amount: fcfa(2000));

    // Chaque envoi est traité par le serveur puis sa réponse se perd ; l'app réessaie.
    for (var i = 0; i < 3; i++) {
      lossy.loseNext = true;
      final lost = await a.sync();
      expect(lost.stop, SyncStop.network, reason: 'passe ${i + 1}');
    }
    expect((await a.sync()).completed, isTrue);

    final b = await secondDevice(owner.phone, owner.pin);
    await b.sync();
    expect(b.ledger.customers(), hasLength(1));
    expect(b.ledger.debts(), hasLength(1));
    expect(b.ledger.payments(), hasLength(1));
    expect(b.ledger.payments().single.id, payment.id);
    expect(b.repo.customer(customer.id)!.outstanding, fcfa(3000)); // 5000 - 2000, pas 5000 - 4000
  });

  test('deux appareils : le sur-paiement est refusé par le serveur, bloqué avec un message, puis abandonnable', skip: skip, () async {
    final owner = await signUp();
    final a = RealDevice(owner.client, owner.tokens);
    final customer = a.repo.addCustomer(name: 'Chez Awa', phone: customerPhone);
    final debt = a.repo.addDebt(customerId: customer.id, amount: fcfa(1000));
    await a.sync();

    final b = await secondDevice(owner.phone, owner.pin);
    await b.sync(); // B voit la dette de 1000

    a.repo.addPayment(debtId: debt.id, amount: fcfa(800));
    await a.sync();

    b.repo.addPayment(debtId: debt.id, amount: fcfa(500)); // B ignore le paiement de A
    final report = await b.sync();

    expect(report.newlyBlocked, 1);
    final issue = b.repo.issues().single;
    expect(issue.title, contains('Remboursement de 500'));
    expect(issue.reason, contains('dépasse le solde'));

    b.repo.discardIssue(issue.entry);
    await b.sync();
    expect(b.repo.customer(customer.id)!.outstanding, fcfa(200)); // aligné sur le serveur
    expect(b.outbox.count(), 0);
  });

  test('suppression et modification depuis deux appareils : les 404 sont traités comme un succès', skip: skip, () async {
    final owner = await signUp();
    final a = RealDevice(owner.client, owner.tokens);
    final customer = a.repo.addCustomer(name: 'Cheikh', phone: customerPhone);
    final debt = a.repo.addDebt(customerId: customer.id, amount: fcfa(100));
    await a.sync();
    final b = await secondDevice(owner.phone, owner.pin);
    await b.sync();

    a.repo.deleteCustomer(customer.id);
    await a.sync();

    // B, pas encore au courant, modifie puis supprime ce qui n'existe plus.
    b.repo.updateCustomer(customer.id, name: 'Cheikh (modifié)');
    b.repo.updateDebt(debt.id, amount: fcfa(150));
    var report = await b.sync();
    expect(report.newlyBlocked, 0);
    expect(b.ledger.customers(), isEmpty);

    // Double suppression de la même dette depuis A puis B.
    final c = a.repo.addCustomer(name: 'Autre', phone: customerPhone);
    final d = a.repo.addDebt(customerId: c.id, amount: fcfa(100));
    await a.sync();
    await b.sync();
    a.repo.deleteDebt(d.id);
    b.repo.deleteDebt(d.id);
    await a.sync();
    report = await b.sync();
    expect(report.newlyBlocked, 0);
    expect(report.sent, 1);
  });

  test('plan gratuit : le 16e client est refusé avec un message clair, sans perdre les 15 autres', skip: skip, () async {
    final owner = await signUp();
    final a = RealDevice(owner.client, owner.tokens);
    for (var i = 0; i < 16; i++) {
      a.repo.addCustomer(name: 'Client ${i + 1}', phone: customerPhone);
    }

    final report = await a.sync();

    expect(report.sent, 15);
    expect(report.newlyBlocked, 1);
    expect(a.repo.issues().single.reason, contains('15 clients'));
    final b = await secondDevice(owner.phone, owner.pin);
    await b.sync();
    expect(b.ledger.customers(), hasLength(15));
  });

  test('jeton d\'accès expiré : renouvelé en silence ; session révoquée : arrêt propre sans perte', skip: skip, () async {
    final owner = await signUp();
    final a = RealDevice(owner.client, owner.tokens);
    final customer = a.repo.addCustomer(name: 'Aicha', phone: customerPhone);

    // Jeton d'accès invalide (expiré) : le client rafraîchit et rejoue sans que l'app s'en aperçoive.
    await owner.tokens.save(accessToken: 'jeton.expire.invalide', refreshToken: (await owner.tokens.refreshToken)!);
    expect((await a.sync()).completed, isTrue);
    expect((await owner.tokens.accessToken), isNot('jeton.expire.invalide'));

    // Déconnexion depuis un autre appareil : tous les jetons sont révoqués.
    final other = await secondDevice(owner.phone, owner.pin);
    await other.client.send('POST', '/auth/logout');
    a.repo.addDebt(customerId: customer.id, amount: fcfa(100));
    final report = await a.sync();

    expect(report.stop, SyncStop.unauthorized);
    expect(a.outbox.count(), 1); // la saisie est conservée
    expect(await owner.tokens.hasSession, isFalse);
  });

  test('API : profil, abonnement, tableau de bord réservé Premium, relance manuelle, règles', skip: skip, () async {
    final owner = await signUp(businessName: 'Boutique Fatou');
    final api = owner.api;

    final profile = await api.profile();
    expect(profile.businessName, 'Boutique Fatou');
    expect(profile.phone, owner.phone);
    expect(profile.isPremium, isFalse);
    expect((await api.updateBusinessName('Nouveau nom')).businessName, 'Nouveau nom');

    final status = await api.subscriptionStatus();
    expect(status.plan, Plan.free);
    expect(status.customerLimit, 15);
    expect(status.monthlyPrice, fcfa(2000));

    await expectLater(api.dashboard(), throwsA(isA<RejectedException>().having((e) => e.code, 'code', 'PREMIUM_REQUIRED')));

    final a = RealDevice(owner.client, owner.tokens);
    final customer = a.repo.addCustomer(name: 'Aicha', phone: customerPhone);
    final debt = a.repo.addDebt(customerId: customer.id, amount: fcfa(5000), dueDate: DateTime.now().subtract(const Duration(days: 3)));
    await a.sync();

    expect((await api.sendReminder(debt.id, ReminderChannel.sms)).sent, isTrue);
    final momo = await api.requestMobileMoneyPayment(debt.id);
    expect(momo.simulated, isTrue);

    final upgrade = await api.upgrade(); // hors production : activation simulée
    expect(upgrade.activated, isTrue);
    final summary = await api.dashboard();
    expect(summary.totalOutstanding, fcfa(5000));
    expect(summary.customersWithDebt, 1);
    expect(summary.overdue.single.daysOverdue, greaterThanOrEqualTo(2));
    expect(summary.byCategory.single.category, 'Autre');
    expect(summary.trend, hasLength(6));

    final rules = await api.reminderRules();
    expect(rules.map((r) => r.offsetDays), [-3, 0, 7]);
    final saved = await api.saveReminderRule(offsetDays: 14, channel: ReminderChannel.whatsapp, tone: ReminderTone.firm, enabled: false);
    expect(saved.enabled, isFalse);
    await api.deleteReminderRule(saved.id);
    expect((await api.reminderRules()).length, 3);

    final csv = await api.exportHistory();
    expect(String.fromCharCodes(csv.bytes), contains('Aicha'));
  });

  test('connexion par PIN, changement de PIN et révocation', skip: skip, () async {
    final owner = await signUp();
    await owner.api.changePin(currentPin: '1234', newPin: '5678');

    // L'ancienne session est révoquée immédiatement (jeton d'accès compris).
    await expectLater(owner.api.profile(), throwsA(isA<UnauthorizedException>()));
    await expectLater(HttpBackendApi(newClient(TokenStore(InMemorySecretStore()))).login(phone: owner.phone, pin: '1234'), throwsA(isA<UnauthorizedException>()));
    final session = await HttpBackendApi(newClient(TokenStore(InMemorySecretStore()))).login(phone: owner.phone, pin: '5678');
    expect(session.accessToken, isNotEmpty);
  });
}
