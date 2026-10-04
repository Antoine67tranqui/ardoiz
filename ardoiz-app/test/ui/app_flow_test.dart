import 'package:ardoiz/app/app.dart';
import 'package:ardoiz/app/providers.dart';
import 'package:ardoiz/app/router.dart';
import 'package:ardoiz/app/routes.dart';
import 'package:ardoiz/app/session_service.dart';
import 'package:ardoiz/app/sync_coordinator.dart';
import 'package:ardoiz/core/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../support/harness.dart';
import '../support/ui_harness.dart';

void main() {
  late UiEnv env;
  late ProviderContainer container;

  setUp(() => env = UiEnv());
  tearDown(() => env.dispose());

  Future<void> pumpApp(WidgetTester tester, SessionState session) async {
    phoneScreen(tester);
    when(() => env.api.profile()).thenAnswer((_) async => testProfile);
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides(session),
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return const CarneApp();
      }),
    ));
    await tester.pumpAndSettle();
  }

  GoRouter router() => container.read(routerProvider);
  String here() => router().state.uri.toString();

  group('redirections', () {
    test('selon la session', () {
      const out = SignedOut();
      const expired = SignedOut(phone: '+2290167000001', reason: SignedOutReason.expired);
      const loggedOut = SignedOut(phone: '+2290167000001', reason: SignedOutReason.loggedOut);
      const inn = SignedIn(testProfile);

      expect(redirectFor(out, '/'), Routes.welcome);
      expect(redirectFor(out, Routes.customers), Routes.welcome);
      expect(redirectFor(out, '/debts/x'), Routes.welcome);
      expect(redirectFor(out, Routes.login), isNull);
      expect(redirectFor(out, Routes.signupPin), isNull);
      expect(redirectFor(expired, Routes.customers), Routes.login, reason: 'session expirée : retour direct au PIN');
      expect(redirectFor(expired, Routes.login), isNull);
      expect(redirectFor(loggedOut, Routes.customers), Routes.welcome, reason: 'déconnexion volontaire : accueil');
      expect(redirectFor(inn, '/'), Routes.customers);
      expect(redirectFor(inn, Routes.welcome), Routes.customers);
      expect(redirectFor(inn, Routes.login), Routes.customers);
      expect(redirectFor(inn, Routes.dashboard), isNull);
      expect(redirectFor(inn, '/customers/abc'), isNull);
    });
  });

  group('application complète', () {
    testWidgets('déconnecté : accueil ; connecté : liste des clients avec la barre d\'onglets', (tester) async {
      await pumpApp(tester, const SignedOut());
      expect(find.text('Bienvenue sur Carné'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(env.sync.startCalls, 0);
    });

    testWidgets('connecté au lancement : synchronisation démarrée une fois, onglets utilisables', (tester) async {
      await pumpApp(tester, const SignedIn(testProfile));
      expect(here(), Routes.customers);
      expect(find.text('Votre carnet est vide'), findsOneWidget);
      expect(env.sync.startCalls, 1);

      await tester.tap(find.text('Réglages'));
      await tester.pumpAndSettle();
      expect(here(), Routes.settings);
      await tester.tap(find.text('Tableau de bord'));
      await tester.pumpAndSettle();
      expect(here(), Routes.dashboard);
      await tester.tap(find.text('Clients'));
      await tester.pumpAndSettle();
      expect(here(), Routes.customers);
      expect(env.sync.startCalls, 1, reason: 'changer d\'onglet ne redémarre pas la synchronisation');
    });

    testWidgets('parcours complet hors ligne : client, dette, paiement partiel puis solde, totaux à jour', (tester) async {
      await pumpApp(tester, const SignedIn(testProfile));

      await tester.tap(find.text('Ajouter mon premier client'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Nom du client'), 'Aïcha Traoré');
      await tester.enterText(find.widgetWithText(TextFormField, 'Téléphone'), '+229 01 67 00 11');
      await tester.tap(find.text('Ajouter le client'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune dette'), findsOneWidget);

      await tester.tap(find.text('Nouvelle dette'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Montant'), '5000');
      await tester.enterText(find.widgetWithText(TextFormField, 'Motif (facultatif)'), 'Riz');
      await tester.tap(find.text('Enregistrer la dette'));
      await tester.pumpAndSettle();
      expect(find.text('Reste à payer'), findsOneWidget);

      await tester.tap(find.text('Enregistrer un paiement'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Montant reçu'), '2000');
      await tester.tap(find.text('Enregistrer le paiement'));
      await tester.pumpAndSettle();
      expect(find.text('Partielle'), findsOneWidget);

      // Retour à la liste : le total reflète le reste dû.
      router().go(Routes.customers);
      await tester.pumpAndSettle();
      expect(find.text(formatMoney(fcfa(3000))), findsWidgets);
      expect(find.text('1 client'), findsOneWidget);

      // Tout est dans la file d'envoi (client, dette, paiement) : rien n'a nécessité le réseau.
      expect(env.outbox.count(), 3);
      verifyNever(() => env.api.requestMobileMoneyPayment(any()));
    });

    testWidgets('session refusée par le serveur : retour au PIN avec le numéro, données conservées', (tester) async {
      env.repo.addCustomer(name: 'Aïcha', phone: '+22901670000');
      await pumpApp(tester, const SignedIn(testProfile));
      expect(find.text('Aïcha'), findsOneWidget);

      container.read(sessionProvider.notifier).sessionExpired();
      await tester.pumpAndSettle();

      expect(here(), Routes.login);
      expect(find.widgetWithText(TextFormField, '+2290167000001'), findsOneWidget);
      expect(env.ledger.customers(), hasLength(1), reason: 'une session expirée ne détruit jamais les données');
    });

    testWidgets('déconnexion volontaire depuis les réglages : retour à l\'accueil', (tester) async {
      when(() => env.api.logout()).thenAnswer((_) async {});
      await pumpApp(tester, const SignedIn(testProfile));
      router().go(Routes.settings);
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Se déconnecter'));
      await tester.pumpAndSettle();
      expect(here(), Routes.welcome);
    });

    testWidgets('adresse inconnue : page claire avec retour à l\'accueil', (tester) async {
      await pumpApp(tester, const SignedIn(testProfile));
      router().go('/nimporte/quoi');
      await tester.pumpAndSettle();
      expect(find.text('Page introuvable'), findsOneWidget);
      await tester.tap(find.text('Retour à l\'accueil'));
      await tester.pumpAndSettle();
      expect(here(), Routes.customers);
    });

    testWidgets('bandeau de synchronisation : modifications refusées menant à leur écran', (tester) async {
      await pumpApp(tester, const SignedIn(testProfile));
      env.sync.emit(const SyncState(blocked: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 modification à vérifier'));
      await tester.pumpAndSettle();
      expect(here(), Routes.syncIssues);
      expect(find.text('Tout est en ordre'), findsOneWidget);
    });
  });
}
