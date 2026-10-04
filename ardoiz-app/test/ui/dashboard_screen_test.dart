import 'package:ardoiz/app/session_service.dart';
import 'package:ardoiz/core/formatters.dart';
import 'package:ardoiz/data/remote/backend_api.dart';
import 'package:ardoiz/ui/screens/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/harness.dart';
import '../support/ui_harness.dart';

void main() {
  late UiEnv env;
  late GoRouter router;

  setUp(() => env = UiEnv());
  tearDown(() => env.dispose());

  Future<void> pump(WidgetTester tester, {SessionState? session, double textScale = 1}) async {
    phoneScreen(tester);
    await tester.pumpWidget(buildTestApp(
      env,
      initialLocation: '/home/dashboard',
      session: session ?? SignedIn(premiumProfile),
      textScale: textScale,
      screens: <String, ScreenBuilder>{'/home/dashboard': (_) => const DashboardScreen()},
      onReady: (_, r) => router = r,
    ));
    await tester.pumpAndSettle();
  }

  DateTime ago(int days) => env.now.subtract(Duration(days: days));

  testWidgets('plan gratuit : présente Premium sans afficher de chiffres', (tester) async {
    env.repo.addCustomer(name: 'Aïcha', phone: '+22901670000');
    await pump(tester, session: const SignedIn(testProfile));

    expect(find.text('Gardez le contrôle de votre crédit'), findsOneWidget);
    expect(find.text('À encaisser'), findsNothing);
    await tester.scrollUntilVisible(find.text('Découvrir Premium'), 200);
    await tester.tap(find.text('Découvrir Premium'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/settings/subscription');
  });

  testWidgets('Premium expiré (profil en cache) : redevient l\'écran de présentation', (tester) async {
    final expired = Profile(
      id: 'u',
      phone: '+2290167000001',
      businessName: 'Boutique',
      plan: Plan.premium,
      planExpiresAt: env.now.subtract(const Duration(days: 1)),
    );
    await pump(tester, session: SignedIn(expired));
    expect(find.text('Gardez le contrôle de votre crédit'), findsOneWidget);
  });

  testWidgets('Premium sans donnée : message d\'attente de contenu', (tester) async {
    await pump(tester);
    expect(find.text('Rien à analyser pour le moment'), findsOneWidget);
  });

  testWidgets('Premium : indicateurs, clients à surveiller, retards, catégories, tendance', (tester) async {
    final aicha = env.repo.addCustomer(name: 'Aïcha', phone: '+22901670000');
    final bako = env.repo.addCustomer(name: 'Bako', phone: '+22901670001');
    env.repo.addDebt(customerId: aicha.id, amount: fcfa(5000), category: 'Alimentation', dueDate: ago(10));
    env.repo.addDebt(customerId: aicha.id, amount: fcfa(2000), category: 'Boissons', dueDate: ago(4));
    final settled = env.repo.addDebt(customerId: bako.id, amount: fcfa(1000), category: 'Alimentation');
    env.repo.addPayment(debtId: settled.id, amount: fcfa(1000));
    await pump(tester);

    expect(find.text(formatMoney(fcfa(7000))), findsWidgets); // à encaisser et en retard
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);
    expect(find.text('Clients à surveiller'), findsOneWidget);
    expect(find.textContaining('2 dettes en retard'), findsOneWidget);
    expect(find.text('Dettes en retard (2)'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Argent dû par catégorie'), 300);
    expect(find.text('Alimentation (1)'), findsOneWidget);
    expect(find.text('Boissons (1)'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('octobre 2026'), 300);
    expect(find.text('octobre 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('une dette en retard ouvre son détail ; un client à surveiller ouvre sa fiche', (tester) async {
    final aicha = env.repo.addCustomer(name: 'Aïcha', phone: '+22901670000');
    final debt = env.repo.addDebt(customerId: aicha.id, amount: fcfa(5000), dueDate: ago(10));
    await pump(tester);

    await tester.tap(find.textContaining('1 dette en retard'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/customers/${aicha.id}');
    router.pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.textContaining('10 jours de retard'), 200);
    await tester.tap(find.textContaining('10 jours de retard'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/debts/${debt.id}');
  });

  testWidgets('se met à jour hors connexion dès qu\'une dette est ajoutée', (tester) async {
    final aicha = env.repo.addCustomer(name: 'Aïcha', phone: '+22901670000');
    await pump(tester);
    expect(find.text('Aucun'), findsOneWidget);

    env.repo.addDebt(customerId: aicha.id, amount: fcfa(900), dueDate: ago(3));
    await tester.pumpAndSettle();
    expect(find.text('Aucun'), findsNothing);
    expect(find.text(formatMoney(fcfa(900))), findsWidgets);
  });

  testWidgets('texte agrandi : pas de débordement', (tester) async {
    final aicha = env.repo.addCustomer(name: 'Un client au nom très très long pour le test', phone: '+22901670000');
    env.repo.addDebt(customerId: aicha.id, amount: fcfa(123456789), category: 'Une catégorie au nom assez long', dueDate: ago(100));
    await pump(tester, textScale: 2);
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
