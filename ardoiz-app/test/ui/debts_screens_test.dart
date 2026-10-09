import 'dart:async';

import 'package:ardoiz/app/providers.dart';
import 'package:ardoiz/core/dates.dart';
import 'package:ardoiz/core/formatters.dart';
import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/remote/backend_api.dart';
import 'package:ardoiz/ui/screens/debts/debt_detail_screen.dart';
import 'package:ardoiz/ui/screens/debts/debt_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../support/harness.dart';
import '../support/ui_harness.dart';

class _RecordingOpener implements UrlOpener {
  final List<Uri> opened = <Uri>[];
  bool result = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

void main() {
  late UiEnv env;
  late GoRouter router;

  setUpAll(() => registerFallbackValue(ReminderChannel.sms));
  setUp(() => env = UiEnv());
  tearDown(() => env.dispose());

  Future<void> pump(
    WidgetTester tester, {
    required String initial,
    List<Override> extraOverrides = const <Override>[],
  }) async {
    phoneScreen(tester);
    await tester.pumpWidget(buildTestApp(
      env,
      initialLocation: initial,
      extraOverrides: extraOverrides,
      screens: <String, ScreenBuilder>{
        '/customers/:id': (s) => Scaffold(body: Text('FICHE:${s.pathParameters['id']}')),
        '/customers/:id/debts/new': (s) => DebtFormScreen(customerId: s.pathParameters['id']),
        '/debts/:id': (s) => DebtDetailScreen(debtId: s.pathParameters['id']!),
        '/debts/:id/edit': (s) => DebtFormScreen(debtId: s.pathParameters['id']),
      },
      onReady: (_, r) => router = r,
    ));
    await tester.pumpAndSettle();
  }

  String addCustomer({String name = 'Aïcha', String phone = '+229 01 67 00 11', int? limit}) =>
      env.repo.addCustomer(name: name, phone: phone, creditLimit: limit == null ? null : fcfa(limit)).id;

  String addDebt(String customerId, int amount, {String? reason, DateTime? due, bool synced = false}) {
    final id = env.repo.addDebt(customerId: customerId, amount: fcfa(amount), reason: reason, dueDate: due).id;
    if (synced) env.outbox.clear();
    return id;
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  group('formulaire de dette', () {
    testWidgets('crée une dette avec motif, catégorie et échéance, puis ouvre son détail', (tester) async {
      final customer = addCustomer();
      await pump(tester, initial: '/customers/$customer/debts/new');

      await tester.enterText(field('Montant'), '2 500');
      await tester.enterText(field('Motif (facultatif)'), '2 sacs de riz');
      await tester.tap(find.text('Boissons'));
      await tester.tap(find.text('7 jours'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer la dette'));
      await tester.pumpAndSettle();

      final debt = env.ledger.debts().single;
      expect(debt.amount, fcfa(2500));
      expect(debt.reason, '2 sacs de riz');
      expect(debt.category, 'Boissons');
      // Fin de la journée du 11 octobre : en retard seulement à partir du 12.
      expect(debt.dueDate, endOfLocalDay(DateTime(2026, 10, 11)).toUtc());
      expect(env.outbox.count(), 2); // client + dette
      expect(router.state.uri.toString(), '/debts/${debt.id}');
    });

    testWidgets('refuse un montant nul, négatif, mal formé ou trop grand', (tester) async {
      final customer = addCustomer();
      await pump(tester, initial: '/customers/$customer/debts/new');

      for (final bad in <String>['0', 'abc', '12,345', '99999999999']) {
        await tester.enterText(field('Montant'), bad);
        await tester.tap(find.text('Enregistrer la dette'));
        await tester.pumpAndSettle();
        expect(find.textContaining(RegExp('montant|Montant')), findsWidgets, reason: bad);
        expect(env.ledger.debts(), isEmpty, reason: bad);
      }
    });

    testWidgets('prévient quand le plafond de crédit est dépassé et laisse le choix', (tester) async {
      final customer = addCustomer(limit: 5000);
      addDebt(customer, 4000);
      await pump(tester, initial: '/customers/$customer/debts/new');

      await tester.enterText(field('Montant'), '2000');
      await tester.tap(find.text('Enregistrer la dette'));
      await tester.pumpAndSettle();
      expect(find.text('Plafond de crédit dépassé'), findsOneWidget);
      expect(find.textContaining(formatMoney(fcfa(6000))), findsOneWidget);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(env.ledger.debts(), hasLength(1));

      await tester.tap(find.text('Enregistrer la dette'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer quand même'));
      await tester.pumpAndSettle();
      expect(env.ledger.debts(), hasLength(2));
    });

    testWidgets('sans dépassement du plafond, aucune confirmation', (tester) async {
      final customer = addCustomer(limit: 5000);
      await pump(tester, initial: '/customers/$customer/debts/new');
      await tester.enterText(field('Montant'), '5000');
      await tester.tap(find.text('Enregistrer la dette'));
      await tester.pumpAndSettle();
      expect(find.text('Plafond de crédit dépassé'), findsNothing);
      expect(env.ledger.debts(), hasLength(1));
    });

    testWidgets('sélection d\'une date précise et retrait de l\'échéance', (tester) async {
      final customer = addCustomer();
      await pump(tester, initial: '/customers/$customer/debts/new');

      await tester.tap(find.text('Choisir une date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Sans échéance'), findsOneWidget);
      expect(find.text('11 oct. 2026'), findsOneWidget); // proposition par défaut : J+7

      await tester.tap(find.text('Sans échéance'));
      await tester.pumpAndSettle();
      expect(find.text('Sans échéance'), findsNothing);
      expect(find.text('Choisir une date'), findsOneWidget);
    });

    testWidgets('modification : préremplit, refuse un montant inférieur aux paiements, enregistre le reste', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000, reason: 'Riz', due: DateTime.utc(2026, 11, 1));
      env.repo.addPayment(debtId: debt, amount: fcfa(3000));
      await pump(tester, initial: '/debts/$debt/edit');

      expect(find.widgetWithText(TextFormField, '5000'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Riz'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, '5000'), '2000');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('inférieur aux paiements déjà reçus'), findsOneWidget);
      expect(env.ledger.debt(debt)!.amount, fcfa(5000));

      await tester.enterText(find.widgetWithText(TextFormField, '2000'), '6000');
      await tester.enterText(find.widgetWithText(TextFormField, 'Riz'), '');
      await tester.tap(find.text('Sans échéance'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Enregistrer'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final saved = env.ledger.debt(debt)!;
      expect(saved.amount, fcfa(6000));
      expect(saved.reason, isNull);
      expect(saved.dueDate, isNull);
    });

    testWidgets('dette ou client supprimé entre-temps : message clair', (tester) async {
      await pump(tester, initial: '/debts/inconnue/edit');
      expect(find.text('Dette introuvable'), findsOneWidget);
    });

    testWidgets('client inconnu à la création : message clair', (tester) async {
      await pump(tester, initial: '/customers/inconnu/debts/new');
      expect(find.text('Client introuvable'), findsOneWidget);
    });
  });

  group('détail d\'une dette', () {
    testWidgets('affiche reste à payer, avancement, statut, échéance et paiements', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000, reason: 'Riz', due: env.now.add(const Duration(days: 3)));
      env.repo.addPayment(debtId: debt, amount: fcfa(2000));
      await pump(tester, initial: '/debts/$debt');

      expect(find.text(formatMoney(fcfa(3000))), findsOneWidget);
      expect(find.text('${formatMoney(fcfa(2000))} payés sur ${formatMoney(fcfa(5000))}'), findsOneWidget);
      expect(find.text('Partielle'), findsOneWidget);
      expect(find.textContaining('Riz', findRichText: true), findsOneWidget);
      expect(find.textContaining('dans 3 jours', findRichText: true), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Paiements reçus'), 200);
      expect(find.text(formatMoney(fcfa(2000))), findsOneWidget);
    });

    testWidgets('dette en retard : statut explicite avec le nombre de jours', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 1000, due: env.now.subtract(const Duration(days: 4)));
      await pump(tester, initial: '/debts/$debt');
      expect(find.text('En retard de 4 j'), findsOneWidget);
      expect(find.textContaining('il y a 4 jours', findRichText: true), findsOneWidget);
    });

    testWidgets('paiement partiel : met à jour le solde et confirme', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000);
      await pump(tester, initial: '/debts/$debt');

      await tester.tap(find.text('Enregistrer un paiement'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Montant reçu'), '1 500');
      await tester.tap(find.text('Enregistrer le paiement'));
      await tester.pumpAndSettle();

      expect(env.ledger.payments().single.amount, fcfa(1500));
      expect(find.text('Paiement enregistré'), findsOneWidget);
      expect(find.text(formatMoney(fcfa(3500))), findsOneWidget);
    });

    testWidgets('« Solde total » préremplit le reste ; le paiement solde la dette et retire les actions', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000);
      env.repo.addPayment(debtId: debt, amount: fcfa(1250));
      await pump(tester, initial: '/debts/$debt');

      await tester.tap(find.text('Enregistrer un paiement'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Solde total'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '3750'), findsOneWidget);
      await tester.tap(find.text('Enregistrer le paiement'));
      await tester.pumpAndSettle();

      expect(find.text('Dette soldée, bravo !'), findsOneWidget);
      expect(find.text('Soldée'), findsOneWidget);
      expect(find.text('Enregistrer un paiement'), findsNothing);
      expect(find.text('Relancer le client'), findsNothing);
      expect(env.ledger.debt(debt)!.amount, fcfa(5000));
    });

    testWidgets('refuse un paiement supérieur au reste ou invalide', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000);
      await pump(tester, initial: '/debts/$debt');

      await tester.tap(find.text('Enregistrer un paiement'));
      await tester.pumpAndSettle();
      for (final bad in <String>['5001', '0', 'x']) {
        await tester.enterText(field('Montant reçu'), bad);
        await tester.tap(find.text('Enregistrer le paiement'));
        await tester.pumpAndSettle();
        expect(env.ledger.payments(), isEmpty, reason: bad);
      }
      expect(find.text('Le montant dépasse le solde restant.'), findsNothing); // dernier essai : « x »
      await tester.enterText(field('Montant reçu'), '5001');
      await tester.tap(find.text('Enregistrer le paiement'));
      await tester.pumpAndSettle();
      expect(find.text('Le montant dépasse le solde restant.'), findsOneWidget);
    });

    testWidgets('suppression d\'un paiement après confirmation : le solde remonte', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000);
      env.repo.addPayment(debtId: debt, amount: fcfa(2000));
      await pump(tester, initial: '/debts/$debt');

      await tester.tap(find.byTooltip('Supprimer ce paiement'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(env.ledger.payments(), hasLength(1));

      await tester.tap(find.byTooltip('Supprimer ce paiement'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(env.ledger.payments(), isEmpty);
      expect(find.text(formatMoney(fcfa(5000))), findsWidgets);
      expect(find.text('Aucun paiement pour le moment.'), findsOneWidget);
    });

    testWidgets('suppression de la dette avec ses paiements, après confirmation', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000);
      env.repo.addPayment(debtId: debt, amount: fcfa(2000));
      await pump(tester, initial: '/customers/$customer');
      unawaited(router.push<void>('/debts/$debt'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer la dette'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 paiement'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(env.ledger.debts(), isEmpty);
      expect(env.ledger.payments(), isEmpty);
      expect(find.text('Dette supprimée'), findsOneWidget);
    });

    testWidgets('le nom du client ouvre sa fiche', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000);
      await pump(tester, initial: '/debts/$debt');
      await tester.tap(find.text('Aïcha'));
      await tester.pumpAndSettle();
      expect(find.text('FICHE:$customer'), findsOneWidget);
    });
  });

  group('relance', () {
    Future<void> openReminder(WidgetTester tester) async {
      await tester.tap(find.text('Relancer le client'));
      await tester.pumpAndSettle();
    }

    testWidgets('SMS envoyé par Carné : appelle l\'API et confirme', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000, synced: true);
      when(() => env.api.sendReminder(debt, ReminderChannel.sms))
          .thenAnswer((_) async => const ReminderResult(channel: ReminderChannel.sms, sent: true));
      await pump(tester, initial: '/debts/$debt');

      await openReminder(tester);
      await tester.tap(find.text('SMS envoyé par Carné'));
      await tester.pumpAndSettle();

      verify(() => env.api.sendReminder(debt, ReminderChannel.sms)).called(1);
      expect(find.text('SMS de relance envoyé'), findsOneWidget);
    });

    testWidgets('envoi refusé par le fournisseur : le dit sans prétendre avoir envoyé', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000, synced: true);
      when(() => env.api.sendReminder(any(), any()))
          .thenAnswer((_) async => const ReminderResult(channel: ReminderChannel.sms, sent: false));
      await pump(tester, initial: '/debts/$debt');

      await openReminder(tester);
      await tester.tap(find.text('SMS envoyé par Carné'));
      await tester.pumpAndSettle();
      expect(find.textContaining('L\'envoi du SMS a échoué'), findsOneWidget);
    });

    testWidgets('hors connexion : message compréhensible', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000, synced: true);
      when(() => env.api.sendReminder(any(), any())).thenThrow(const NetworkException('timeout'));
      await pump(tester, initial: '/debts/$debt');

      await openReminder(tester);
      await tester.tap(find.text('SMS envoyé par Carné'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pas de connexion'), findsOneWidget);
    });

    testWidgets('dette non synchronisée : le SMS serveur est désactivé et rien n\'est envoyé', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000);
      await pump(tester, initial: '/debts/$debt');

      await openReminder(tester);
      expect(find.textContaining('après la synchronisation'), findsWidgets);
      await tester.tap(find.text('SMS envoyé par Carné'));
      await tester.pumpAndSettle();
      verifyNever(() => env.api.sendReminder(any(), any()));
    });

    testWidgets('pas de double envoi pendant qu\'une relance est en cours', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000, synced: true);
      final gate = Completer<ReminderResult>();
      when(() => env.api.sendReminder(any(), any())).thenAnswer((_) => gate.future);
      await pump(tester, initial: '/debts/$debt');

      await openReminder(tester);
      await tester.tap(find.text('SMS envoyé par Carné'));
      await tester.pump();
      // Bouton désactivé : un second appui ne fait rien.
      await tester.tap(find.text('Relancer le client'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('SMS depuis mon téléphone'), findsNothing, reason: 'le choix de relance ne se rouvre pas');
      verify(() => env.api.sendReminder(any(), any())).called(1);

      gate.complete(const ReminderResult(channel: ReminderChannel.sms, sent: true));
      await tester.pumpAndSettle();
      expect(find.text('SMS de relance envoyé'), findsOneWidget);
    });

    testWidgets('WhatsApp : ouvre le lien avec un message pré-rempli (nom, boutique, solde)', (tester) async {
      final opener = _RecordingOpener();
      final customer = addCustomer(phone: '+229 01 67 00 11');
      final debt = addDebt(customer, 5000);
      await pump(tester, initial: '/debts/$debt', extraOverrides: <Override>[urlOpenerProvider.overrideWithValue(opener)]);

      await openReminder(tester);
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();

      final link = opener.opened.single;
      expect(link.host, 'wa.me');
      expect(link.path, '/2290167 0011'.replaceAll(' ', ''));
      final text = link.queryParameters['text']!;
      expect(text, contains('Aïcha'));
      expect(text, contains('Boutique Fatou'));
      expect(text, contains(formatMoney(fcfa(5000))));
    });

    testWidgets('WhatsApp sans indicatif : explique quoi faire', (tester) async {
      final opener = _RecordingOpener();
      final customer = addCustomer(phone: '0167001100');
      final debt = addDebt(customer, 5000);
      await pump(tester, initial: '/debts/$debt', extraOverrides: <Override>[urlOpenerProvider.overrideWithValue(opener)]);

      await openReminder(tester);
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ajoutez l\'indicatif'), findsOneWidget);
      expect(opener.opened, isEmpty);
    });

    testWidgets('SMS depuis le téléphone : lien sms: avec le message', (tester) async {
      final opener = _RecordingOpener();
      final customer = addCustomer(phone: '0167001100');
      final debt = addDebt(customer, 5000);
      await pump(tester, initial: '/debts/$debt', extraOverrides: <Override>[urlOpenerProvider.overrideWithValue(opener)]);

      await openReminder(tester);
      await tester.tap(find.text('SMS depuis mon téléphone'));
      await tester.pumpAndSettle();
      expect(opener.opened.single.scheme, 'sms');
      expect(opener.opened.single.path, '0167001100');
      expect(Uri.decodeComponent(opener.opened.single.query), contains('Aïcha'));
    });
  });

  group('Mobile Money', () {
    testWidgets('demande confirmée : appelle l\'API et affiche le message du serveur', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000, synced: true);
      when(() => env.api.requestMobileMoneyPayment(debt))
          .thenAnswer((_) async => const MomoRequestResult(reference: 'R1', simulated: false, message: 'Demande envoyée au client.'));
      await pump(tester, initial: '/debts/$debt');

      await tester.tap(find.text('Demander un paiement Mobile Money'));
      await tester.pumpAndSettle();
      expect(find.textContaining(formatMoney(fcfa(5000))), findsWidgets);
      await tester.tap(find.text('Envoyer la demande'));
      await tester.pumpAndSettle();

      verify(() => env.api.requestMobileMoneyPayment(debt)).called(1);
      expect(find.text('Demande envoyée au client.'), findsOneWidget);
    });

    testWidgets('annulation : aucune demande envoyée', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000, synced: true);
      await pump(tester, initial: '/debts/$debt');

      await tester.tap(find.text('Demander un paiement Mobile Money'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      verifyNever(() => env.api.requestMobileMoneyPayment(any()));
    });

    testWidgets('dette non synchronisée : refuse proprement sans appeler le serveur', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000);
      await pump(tester, initial: '/debts/$debt');

      await tester.tap(find.text('Demander un paiement Mobile Money'));
      await tester.pumpAndSettle();
      expect(find.textContaining('pas encore synchronisée'), findsOneWidget);
      verifyNever(() => env.api.requestMobileMoneyPayment(any()));
    });

    testWidgets('fonctionnalité pas encore ouverte (FEATURE_UNAVAILABLE) : affiche le message du serveur, sans suggérer de réessayer', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000, synced: true);
      when(() => env.api.requestMobileMoneyPayment(any()))
          .thenThrow(const ServerException(503, 'Le paiement Mobile Money n\'est pas encore disponible.', 'FEATURE_UNAVAILABLE'));
      await pump(tester, initial: '/debts/$debt');

      await tester.tap(find.text('Demander un paiement Mobile Money'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Envoyer la demande'));
      await tester.pumpAndSettle();
      expect(find.text('Le paiement Mobile Money n\'est pas encore disponible.'), findsOneWidget);
      expect(find.textContaining('Réessayez'), findsNothing);
    });

    testWidgets('service indisponible (5xx) : message sans détail technique', (tester) async {
      final customer = addCustomer();
      final debt = addDebt(customer, 5000, synced: true);
      when(() => env.api.requestMobileMoneyPayment(any())).thenThrow(const ServerException(503, 'boom interne'));
      await pump(tester, initial: '/debts/$debt');

      await tester.tap(find.text('Demander un paiement Mobile Money'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Envoyer la demande'));
      await tester.pumpAndSettle();
      expect(find.textContaining('momentanément indisponible'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });
  });

  testWidgets('texte agrandi : le détail ne déborde pas', (tester) async {
    final customer = addCustomer(name: 'Un client au nom particulièrement long pour le test');
    final debt = addDebt(customer, 123456789, reason: 'Un motif long '.padRight(200, 'x'), due: env.now.subtract(const Duration(days: 40)));
    env.repo.addPayment(debtId: debt, amount: fcfa(1000));
    phoneScreen(tester);
    await tester.pumpWidget(buildTestApp(
      env,
      initialLocation: '/debts/$debt',
      textScale: 2,
      screens: <String, ScreenBuilder>{'/debts/:id': (s) => DebtDetailScreen(debtId: s.pathParameters['id']!)},
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
