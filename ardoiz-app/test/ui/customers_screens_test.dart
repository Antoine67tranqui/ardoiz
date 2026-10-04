import 'package:ardoiz/app/providers.dart';
import 'package:ardoiz/app/session_service.dart';
import 'package:ardoiz/core/formatters.dart';
import 'package:ardoiz/ui/screens/customers/customer_detail_screen.dart';
import 'package:ardoiz/ui/screens/customers/customer_form_screen.dart';
import 'package:ardoiz/ui/screens/customers/customers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

  setUp(() => env = UiEnv());
  tearDown(() => env.dispose());

  Future<void> pump(
    WidgetTester tester, {
    required String initial,
    SessionState session = const SignedIn(testProfile),
    List<Override> extraOverrides = const <Override>[],
  }) async {
    phoneScreen(tester);
    await tester.pumpWidget(buildTestApp(
      env,
      initialLocation: initial,
      session: session,
      extraOverrides: extraOverrides,
      screens: <String, ScreenBuilder>{
        '/home/customers': (_) => const CustomersScreen(),
        '/customers/new': (_) => const CustomerFormScreen(),
        '/customers/:id': (s) => CustomerDetailScreen(customerId: s.pathParameters['id']!),
        '/customers/:id/edit': (s) => CustomerFormScreen(customerId: s.pathParameters['id']!),
      },
      onReady: (_, r) => router = r,
    ));
    await tester.pumpAndSettle();
  }

  String addCustomer(String name, {String phone = '+22901670000', int? debt, int paid = 0, DateTime? due, int? limit}) {
    final customer = env.repo.addCustomer(name: name, phone: phone, creditLimit: limit == null ? null : fcfa(limit));
    if (debt != null) {
      final d = env.repo.addDebt(customerId: customer.id, amount: fcfa(debt), dueDate: due);
      if (paid > 0) env.repo.addPayment(debtId: d.id, amount: fcfa(paid));
    }
    return customer.id;
  }

  group('liste des clients', () {
    testWidgets('carnet vide : invite à ajouter le premier client', (tester) async {
      await pump(tester, initial: '/home/customers');
      expect(find.text('Votre carnet est vide'), findsOneWidget);

      await tester.tap(find.text('Ajouter mon premier client'));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau client'), findsWidgets);
      expect(router.state.uri.toString(), '/customers/new');
    });

    testWidgets('affiche le total à encaisser, les soldes et les états', (tester) async {
      addCustomer('Aïcha Traoré', debt: 5000, paid: 2000);
      addCustomer('Bako Sow', debt: 1000, due: env.now.subtract(const Duration(days: 3)));
      addCustomer('Chantal Dossou');
      await pump(tester, initial: '/home/customers');

      expect(find.text(formatMoney(fcfa(4000))), findsOneWidget); // total 3000 + 1000
      expect(find.text('3 clients'), findsOneWidget);
      expect(find.text(formatMoney(fcfa(3000))), findsOneWidget);
      expect(find.text('En retard de 3 j'), findsOneWidget);
      expect(find.text('À jour'), findsOneWidget);
      // Tri par nom par défaut.
      final names = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
      expect(names.indexOf('Aïcha Traoré') < names.indexOf('Bako Sow'), isTrue);
    });

    testWidgets('recherche sans accents ni casse, et par numéro', (tester) async {
      addCustomer('Aïcha Traoré', phone: '+229 01 67 00 11');
      addCustomer('Bako Sow', phone: '+229 05 55 12 34');
      await pump(tester, initial: '/home/customers');

      await tester.enterText(find.byType(TextField), 'aicha');
      await tester.pumpAndSettle();
      expect(find.text('Aïcha Traoré'), findsOneWidget);
      expect(find.text('Bako Sow'), findsNothing);

      await tester.enterText(find.byType(TextField), '5551');
      await tester.pumpAndSettle();
      expect(find.text('Bako Sow'), findsOneWidget);
      expect(find.text('Aïcha Traoré'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Aucun client trouvé'), findsOneWidget);

      await tester.tap(find.byTooltip('Effacer la recherche'));
      await tester.pumpAndSettle();
      expect(find.text('Aïcha Traoré'), findsOneWidget);
    });

    testWidgets('filtre « En retard » avec compteur', (tester) async {
      addCustomer('Aïcha', debt: 5000);
      addCustomer('Bako', debt: 1000, due: env.now.subtract(const Duration(days: 2)));
      await pump(tester, initial: '/home/customers');

      expect(find.text('En retard (1)'), findsOneWidget);
      await tester.tap(find.text('En retard (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Bako'), findsOneWidget);
      expect(find.text('Aïcha'), findsNothing);
    });

    testWidgets('tri par solde décroissant', (tester) async {
      addCustomer('Aïcha', debt: 1000);
      addCustomer('Bako', debt: 9000);
      await pump(tester, initial: '/home/customers');

      await tester.tap(find.byTooltip('Trier les clients'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solde le plus élevé'));
      await tester.pumpAndSettle();

      final names = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
      expect(names.indexOf('Bako') < names.indexOf('Aïcha'), isTrue);
    });

    testWidgets('un client non synchronisé porte l\'icône d\'attente ; tirer vers le bas lance la synchronisation', (tester) async {
      addCustomer('Aïcha', debt: 1000);
      await pump(tester, initial: '/home/customers');
      expect(find.byIcon(Icons.cloud_upload_outlined), findsWidgets);

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(env.sync.syncCalls, 1);
    });

    testWidgets('se met à jour quand les données changent', (tester) async {
      await pump(tester, initial: '/home/customers');
      expect(find.text('Votre carnet est vide'), findsOneWidget);
      addCustomer('Nouveau Client');
      await tester.pumpAndSettle();
      expect(find.text('Nouveau Client'), findsOneWidget);
    });

    testWidgets('texte agrandi : pas de débordement', (tester) async {
      addCustomer('Un client avec un nom vraiment très très long pour tester', debt: 123456789);
      phoneScreen(tester);
      await tester.pumpWidget(buildTestApp(
        env,
        initialLocation: '/home/customers',
        textScale: 2,
        screens: <String, ScreenBuilder>{'/home/customers': (_) => const CustomersScreen()},
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('formulaire client', () {
    testWidgets('crée un client, enregistre l\'envoi et ouvre sa fiche', (tester) async {
      await pump(tester, initial: '/customers/new');

      await tester.enterText(find.widgetWithText(TextFormField, 'Nom du client'), '  Aïcha Traoré ');
      await tester.enterText(find.widgetWithText(TextFormField, 'Téléphone'), '+229 01 67 00 11');
      await tester.enterText(find.widgetWithText(TextFormField, 'Plafond de crédit (facultatif)'), '50 000');
      await tester.tap(find.text('Ajouter le client'));
      await tester.pumpAndSettle();

      final saved = env.ledger.customers().single;
      expect(saved.name, 'Aïcha Traoré');
      expect(saved.creditLimit, fcfa(50000));
      expect(env.outbox.count(), 1);
      expect(router.state.uri.toString(), '/customers/${saved.id}');
      expect(find.text('Aïcha Traoré'), findsWidgets);
    });

    testWidgets('refuse un nom, un téléphone et un plafond invalides, sans rien enregistrer', (tester) async {
      await pump(tester, initial: '/customers/new');

      await tester.enterText(find.widgetWithText(TextFormField, 'Nom du client'), 'A');
      await tester.enterText(find.widgetWithText(TextFormField, 'Téléphone'), '12');
      await tester.enterText(find.widgetWithText(TextFormField, 'Plafond de crédit (facultatif)'), 'abc');
      await tester.tap(find.text('Ajouter le client'));
      await tester.pumpAndSettle();

      expect(find.text('Le nom doit comporter au moins 2 caractères.'), findsOneWidget);
      expect(find.textContaining('Numéro invalide'), findsOneWidget);
      expect(find.textContaining('montant valide'), findsOneWidget);
      expect(env.ledger.customers(), isEmpty);
    });

    testWidgets('modifie un client existant (nom, plafond retiré)', (tester) async {
      final id = addCustomer('Aïcha', limit: 10000);
      await pump(tester, initial: '/customers/$id/edit');

      expect(find.widgetWithText(TextFormField, 'Aïcha'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '10000'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Aïcha'), 'Aïcha Traoré');
      await tester.enterText(find.widgetWithText(TextFormField, '10000'), '');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final saved = env.ledger.customer(id)!;
      expect(saved.name, 'Aïcha Traoré');
      expect(saved.creditLimit, isNull);
    });

    testWidgets('plan gratuit : à 15 clients, propose Premium au lieu du formulaire', (tester) async {
      for (var i = 0; i < freePlanCustomerLimit; i++) {
        addCustomer('Client $i');
      }
      await pump(tester, initial: '/customers/new');

      expect(find.text('Limite du plan gratuit atteinte'), findsOneWidget);
      expect(find.text('Ajouter le client'), findsNothing);
      await tester.tap(find.text('Découvrir Premium'));
      await tester.pumpAndSettle();
      expect(find.text('ROUTE:/settings/subscription'), findsOneWidget);
    });

    testWidgets('plan Premium : pas de limite à 15 clients', (tester) async {
      for (var i = 0; i < freePlanCustomerLimit; i++) {
        addCustomer('Client $i');
      }
      await pump(tester, initial: '/customers/new', session: SignedIn(premiumProfile));
      expect(find.text('Ajouter le client'), findsOneWidget);
    });

    testWidgets('modification d\'un client supprimé entre-temps : message clair', (tester) async {
      await pump(tester, initial: '/customers/inconnu/edit');
      expect(find.text('Client introuvable'), findsOneWidget);
    });
  });

  group('fiche client', () {
    testWidgets('affiche solde, retard, plafond dépassé et sépare dettes en cours et soldées', (tester) async {
      final id = addCustomer('Aïcha', debt: 5000, due: env.now.subtract(const Duration(days: 4)), limit: 4000);
      final settled = env.repo.addDebt(customerId: id, amount: fcfa(800), reason: 'Riz');
      env.repo.addPayment(debtId: settled.id, amount: fcfa(800));
      await pump(tester, initial: '/customers/$id');

      expect(find.text('Solde dû'), findsOneWidget);
      expect(find.text('Retard de 4 jours'), findsOneWidget);
      expect(find.text('Plafond de ${formatMoney(fcfa(4000))} dépassé'), findsOneWidget);
      expect(find.text('En cours'), findsOneWidget);
      expect(find.text('Soldées'), findsOneWidget);
      expect(find.text('Riz'), findsOneWidget);
      expect(find.text('Soldée'), findsOneWidget);
    });

    testWidgets('client sans dette : invite à noter la première', (tester) async {
      final id = addCustomer('Aïcha');
      await pump(tester, initial: '/customers/$id');
      expect(find.text('Aucune dette'), findsOneWidget);
      await tester.tap(find.text('Nouvelle dette'));
      await tester.pumpAndSettle();
      expect(find.text('ROUTE:/customers/$id/debts/new'), findsOneWidget);
    });

    testWidgets('ouvrir une dette mène à son détail', (tester) async {
      final id = addCustomer('Aïcha', debt: 5000);
      final debtId = env.ledger.debts().single.id;
      await pump(tester, initial: '/customers/$id');
      await tester.tap(find.text('Autre'));
      await tester.pumpAndSettle();
      expect(find.text('ROUTE:/debts/$debtId'), findsOneWidget);
    });

    testWidgets('appel et WhatsApp utilisent le numéro du client', (tester) async {
      final opener = _RecordingOpener();
      final id = addCustomer('Aïcha', phone: '+229 01 67 00 11');
      await pump(tester, initial: '/customers/$id', extraOverrides: <Override>[urlOpenerProvider.overrideWithValue(opener)]);

      await tester.tap(find.byTooltip('Appeler Aïcha'));
      await tester.pump();
      await tester.tap(find.byTooltip('Écrire sur WhatsApp à Aïcha'));
      await tester.pump();

      expect(opener.opened[0].toString(), 'tel:+2290167 0011'.replaceAll(' ', ''));
      expect(opener.opened[1].toString(), 'https://wa.me/2290167 0011'.replaceAll(' ', ''));
    });

    testWidgets('WhatsApp sans indicatif : explique quoi faire, n\'ouvre rien', (tester) async {
      final opener = _RecordingOpener();
      final id = addCustomer('Aïcha', phone: '0167001100');
      await pump(tester, initial: '/customers/$id', extraOverrides: <Override>[urlOpenerProvider.overrideWithValue(opener)]);

      await tester.tap(find.byTooltip('Écrire sur WhatsApp à Aïcha'));
      await tester.pump();
      expect(find.textContaining('ajoutez l\'indicatif'), findsOneWidget);
      expect(opener.opened, isEmpty);
    });

    testWidgets('aucune application disponible : message au lieu d\'un échec silencieux', (tester) async {
      final opener = _RecordingOpener()..result = false;
      final id = addCustomer('Aïcha');
      await pump(tester, initial: '/customers/$id', extraOverrides: <Override>[urlOpenerProvider.overrideWithValue(opener)]);

      await tester.tap(find.byTooltip('Appeler Aïcha'));
      await tester.pump();
      expect(find.textContaining('Aucune application'), findsOneWidget);
    });

    testWidgets('suppression : confirmation mentionnant les dettes, puis retour à la liste', (tester) async {
      final id = addCustomer('Aïcha', debt: 5000);
      await pump(tester, initial: '/home/customers');
      await tester.tap(find.text('Aïcha'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer le client'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 dette'), findsOneWidget);

      // Annuler ne supprime rien.
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(env.ledger.customer(id), isNotNull);

      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer le client'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(env.ledger.customer(id), isNull);
      expect(env.ledger.debts(), isEmpty);
      expect(find.text('Client supprimé'), findsOneWidget);
      expect(find.text('Votre carnet est vide'), findsOneWidget);
    });

    testWidgets('fiche d\'un client supprimé ailleurs (synchronisation) : message clair', (tester) async {
      final id = addCustomer('Aïcha');
      await pump(tester, initial: '/customers/$id');
      env.repo.deleteCustomer(id);
      await tester.pumpAndSettle();
      expect(find.text('Client introuvable'), findsOneWidget);
    });
  });
}
