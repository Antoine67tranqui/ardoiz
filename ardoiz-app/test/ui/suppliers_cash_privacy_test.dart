import 'package:ardoiz/app/app.dart';
import 'package:ardoiz/app/providers.dart';
import 'package:ardoiz/app/router.dart';
import 'package:ardoiz/app/routes.dart';
import 'package:ardoiz/app/session_service.dart';
import 'package:ardoiz/core/formatters.dart';
import 'package:ardoiz/core/legal.dart';
import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/remote/backend_api.dart';
import 'package:ardoiz/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../support/harness.dart';
import '../support/ui_harness.dart';

class _Sharer implements FileSharer {
  final List<({String fileName, List<int> bytes, String mimeType})> shared = <({String fileName, List<int> bytes, String mimeType})>[];

  @override
  Future<void> share({required String fileName, required List<int> bytes, required String mimeType}) async =>
      shared.add((fileName: fileName, bytes: bytes, mimeType: mimeType));
}

void main() {
  late UiEnv env;
  late ProviderContainer container;

  setUp(() => env = UiEnv());
  tearDown(() => env.dispose());

  Future<void> pumpApp(
    WidgetTester tester, {
    String? at,
    SessionState session = const SignedIn(testProfile),
    List<Override> extra = const <Override>[],
    double textScale = 1,
  }) async {
    phoneScreen(tester);
    when(() => env.api.profile()).thenAnswer((_) async => session is SignedIn ? session.profile : testProfile);
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[...env.overrides(session), ...extra],
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return MediaQuery(
          data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(textScale)),
          child: const CarneApp(),
        );
      }),
    ));
    await tester.pumpAndSettle();
    if (at != null) {
      container.read(routerProvider).go(at);
      await tester.pumpAndSettle();
    }
  }

  GoRouter router() => container.read(routerProvider);
  String here() => router().state.uri.toString();
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  group('fournisseurs', () {
    testWidgets('onglet vide : invite, puis création d\'un fournisseur (sans plafond de crédit)', (tester) async {
      await pumpApp(tester, at: Routes.suppliers);
      expect(find.text('Aucun fournisseur'), findsOneWidget);

      await tester.tap(find.text('Ajouter mon premier fournisseur'));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau fournisseur'), findsWidgets);
      expect(field('Plafond de crédit (facultatif)'), findsNothing, reason: 'on ne plafonne pas ce que JE dois');
      expect(find.text('Ce client refuse les relances'), findsNothing);

      await tester.enterText(field('Nom du fournisseur'), 'Grossiste Dossou');
      await tester.enterText(field('Téléphone'), '+229 05 55 12 34');
      await tester.tap(find.text('Ajouter le fournisseur'));
      await tester.pumpAndSettle();

      final saved = env.ledger.customers().single;
      expect(saved.kind, PartyKind.supplier);
      expect(find.text('Nouvel achat à crédit'), findsOneWidget);
    });

    testWidgets('liste : total à payer, séparée des clients', (tester) async {
      final supplier = env.repo.addCustomer(name: 'Grossiste', phone: '+22905551234', kind: PartyKind.supplier);
      env.repo.addDebt(customerId: supplier.id, amount: fcfa(10000));
      env.repo.addCustomer(name: 'Aïcha', phone: '+22901670000');
      await pumpApp(tester, at: Routes.suppliers);

      expect(find.text('Total à payer'), findsOneWidget);
      expect(find.text(formatMoney(fcfa(10000))), findsWidgets);
      expect(find.text('Grossiste'), findsOneWidget);
      expect(find.text('Aïcha'), findsNothing);

      container.read(routerProvider).go(Routes.customers);
      await tester.pumpAndSettle();
      expect(find.text('Aïcha'), findsOneWidget);
      expect(find.text('Grossiste'), findsNothing);
    });

    testWidgets('dette fournisseur : pas de relance ni de Mobile Money, paiement au fournisseur', (tester) async {
      final supplier = env.repo.addCustomer(name: 'Grossiste', phone: '+22905551234', kind: PartyKind.supplier);
      final debt = env.repo.addDebt(customerId: supplier.id, amount: fcfa(10000), reason: 'Sacs de riz');
      await pumpApp(tester, at: '/debts/${debt.id}');

      expect(find.text('Relancer le client'), findsNothing);
      expect(find.text('Demander un paiement Mobile Money'), findsNothing);
      expect(find.text('Reste à payer au fournisseur'), findsOneWidget);

      await tester.tap(find.text('Payer ce fournisseur'));
      await tester.pumpAndSettle();
      expect(find.text('Payer un fournisseur'), findsOneWidget);
      await tester.enterText(field('Montant payé'), '4000');
      await tester.tap(find.text('Enregistrer le paiement'));
      await tester.pumpAndSettle();

      expect(env.ledger.payments().single.amount, fcfa(4000));
      expect(env.repo.customer(supplier.id)!.outstanding, fcfa(6000));
      await tester.scrollUntilVisible(find.text('Paiements faits'), 200);
      expect(find.text('Paiements faits'), findsOneWidget);
    });

    testWidgets('formulaire de dette fournisseur : libellés d\'achat à crédit, sans alerte de plafond', (tester) async {
      final supplier = env.repo.addCustomer(name: 'Grossiste', phone: '+22905551234', kind: PartyKind.supplier);
      await pumpApp(tester, at: '/customers/${supplier.id}/debts/new');
      expect(find.text('Nouvel achat à crédit'), findsOneWidget);
      expect(field('Montant à payer'), findsOneWidget);
      await tester.enterText(field('Montant à payer'), '7500');
      await tester.tap(find.text('Enregistrer l\'achat'));
      await tester.pumpAndSettle();
      expect(env.ledger.debts().single.amount, fcfa(7500));
    });

    testWidgets('plan gratuit : le 16e fournisseur renvoie vers Premium, les clients ne sont pas comptés', (tester) async {
      for (var i = 0; i < freePlanCustomerLimit; i++) {
        env.repo.addCustomer(name: 'Fournisseur $i', phone: '+22905551234', kind: PartyKind.supplier);
      }
      await pumpApp(tester, at: Routes.supplierNew);
      expect(find.text('Limite du plan gratuit atteinte'), findsOneWidget);
      expect(find.textContaining('15 fournisseurs'), findsOneWidget);

      container.read(routerProvider).go(Routes.customerNew);
      await tester.pumpAndSettle();
      expect(find.text('Ajouter le client'), findsOneWidget);
    });

    testWidgets('client : l\'opposition aux relances s\'enregistre et s\'affiche sur la fiche', (tester) async {
      await pumpApp(tester, at: Routes.customerNew);
      await tester.enterText(field('Nom du client'), 'Aïcha');
      await tester.enterText(field('Téléphone'), '+22901670000');
      await reveal(tester, find.text('Ce client refuse les relances'));
      await tester.tap(find.text('Ce client refuse les relances'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Ajouter le client'));
      await tester.tap(find.text('Ajouter le client'));
      await tester.pumpAndSettle();

      expect(env.ledger.customers().single.reminderOptOut, isTrue);
      expect(find.text('Refuse les relances'), findsOneWidget);
      expect(env.outbox.all().single.payload['reminderOptOut'], isTrue);
    });

    testWidgets('exporter les données d\'une personne : appelle le serveur et partage le fichier', (tester) async {
      final sharer = _Sharer();
      final customer = env.repo.addCustomer(name: 'Aïcha Traoré', phone: '+22901670000');
      env.outbox.clear();
      when(() => env.api.exportPartyData(customer.id, fileName: any(named: 'fileName')))
          .thenAnswer((i) async => DownloadedFile(fileName: i.namedArguments[#fileName]! as String, bytes: const <int>[123, 125]));
      await pumpApp(tester, at: '/customers/${customer.id}', extra: <Override>[fileSharerProvider.overrideWithValue(sharer)]);

      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exporter les données de cette personne'));
      await tester.pumpAndSettle();

      expect(sharer.shared.single.fileName, 'carne-client-aicha-traore.json');
      expect(sharer.shared.single.mimeType, 'application/json');
    });
  });

  group('caisse', () {
    testWidgets('mois vide : bilan à zéro et invitation', (tester) async {
      await pumpApp(tester, at: Routes.cash);
      expect(find.text('Aucune vente ni dépense ce mois-ci'), findsOneWidget);
      expect(find.text('octobre 2026'), findsOneWidget);
      expect(find.text(formatMoney(fcfa(0))), findsWidgets);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull, reason: 'pas de mois futur');
    });

    testWidgets('vente puis dépense : saisie rapide, bilan, liste par jour', (tester) async {
      await pumpApp(tester, at: Routes.cash);

      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Une vente au comptant'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Montant'), '12 500');
      await tester.enterText(field('Libellé (facultatif)'), '3 sacs de riz');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Une dépense'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Montant'), '2000');
      await tester.tap(find.text('Transport'));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(env.ledger.cashEntries(), hasLength(2));
      expect(env.outbox.count(), 2);
      expect(find.text('3 sacs de riz'), findsOneWidget);
      expect(find.text('+ ${formatMoney(fcfa(12500))}'), findsWidgets);
      expect(find.text('- ${formatMoney(fcfa(2000))}'), findsWidgets);
      expect(find.text(formatMoney(fcfa(10500))), findsOneWidget, reason: 'solde du mois = 12 500 - 2 000');
      expect(find.textContaining("Aujourd'hui"), findsOneWidget);
    });

    testWidgets('le bilan compte aussi les remboursements reçus et les paiements aux fournisseurs, et signale le crédit non encaissé', (tester) async {
      final client = env.repo.addCustomer(name: 'Aïcha', phone: '+22901670000');
      final clientDebt = env.repo.addDebt(customerId: client.id, amount: fcfa(5000));
      env.repo.addPayment(debtId: clientDebt.id, amount: fcfa(2000));
      final supplier = env.repo.addCustomer(name: 'Grossiste', phone: '+22905551234', kind: PartyKind.supplier);
      final supplierDebt = env.repo.addDebt(customerId: supplier.id, amount: fcfa(9000));
      env.repo.addPayment(debtId: supplierDebt.id, amount: fcfa(3000));
      env.repo.addCashEntry(type: CashType.sale, amount: fcfa(10000));
      env.repo.addCashEntry(type: CashType.expense, amount: fcfa(1500), category: 'Loyer');
      await pumpApp(tester, at: Routes.cash);

      expect(find.text(formatMoney(fcfa(7500))), findsWidgets); // 10 000 + 2 000 - 1 500 - 3 000
      expect(find.text('Remboursements reçus de clients'), findsOneWidget);
      expect(find.text('Paiements à des fournisseurs'), findsOneWidget);
      expect(find.textContaining('Crédit accordé à des clients ce mois (pas encore encaissé) : ${formatMoney(fcfa(5000))}'), findsOneWidget);
      expect(find.textContaining('Achats à crédit chez des fournisseurs ce mois (pas encore payés) : ${formatMoney(fcfa(9000))}'), findsOneWidget);
      expect(find.text('Loyer'), findsWidgets);
    });

    testWidgets('modifier et supprimer une écriture ; la suppression demande confirmation', (tester) async {
      final entry = env.repo.addCashEntry(type: CashType.expense, amount: fcfa(500), label: 'Taxi', category: 'Transport');
      env.outbox.clear();
      await pumpApp(tester, at: Routes.cash);

      await tester.tap(find.text('Taxi'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier dépense'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, '500'), '700');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(env.ledger.cashEntry(entry.id)!.amount, fcfa(700));

      await tester.tap(find.text('Taxi'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Supprimer cette écriture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer cette écriture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(env.ledger.cashEntry(entry.id), isNotNull);

      await tester.ensureVisible(find.text('Supprimer cette écriture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer cette écriture'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(env.ledger.cashEntry(entry.id), isNull);
    });

    testWidgets('montant invalide refusé ; navigation entre mois ; date « Hier »', (tester) async {
      await pumpApp(tester, at: Routes.cash);
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Une vente au comptant'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Montant'), '0');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(env.ledger.cashEntries(), isEmpty);

      await tester.enterText(field('Montant'), '300');
      await tester.tap(find.text('Hier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(env.ledger.cashEntries().single.occurredAt.day, env.now.subtract(const Duration(days: 1)).day);

      await tester.tap(find.byTooltip('Mois précédent'));
      await tester.pumpAndSettle();
      expect(find.text('septembre 2026'), findsOneWidget);
      expect(find.text('Aucune vente ni dépense ce mois-ci'), findsOneWidget);
      await tester.tap(find.byTooltip('Mois suivant'));
      await tester.pumpAndSettle();
      expect(find.text('octobre 2026'), findsOneWidget);
    });

    testWidgets('texte agrandi : pas de débordement', (tester) async {
      env.repo.addCashEntry(type: CashType.sale, amount: fcfa(123456789), label: 'Une vente avec un libellé particulièrement long pour le test', category: 'Une catégorie longue');
      await pumpApp(tester, at: Routes.cash, textScale: 2);
      await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('consentement et vie privée', () {
    testWidgets('nouvelle version des conditions : écran de consentement bloquant, puis accès à l\'application', (tester) async {
      const pending = Profile(id: 'user-1', phone: '+2290167000001', businessName: 'Boutique Fatou', plan: Plan.free, termsAccepted: false, termsVersion: '2026-10-06');
      when(() => env.api.acceptTerms(any())).thenAnswer((_) async {});
      await pumpApp(tester, session: const SignedIn(pending));
      // Après acceptation le serveur renvoie le profil à jour.
      when(() => env.api.profile()).thenAnswer((_) async => testProfile);

      expect(here(), Routes.consent);
      expect(find.text('Nos conditions ont changé'), findsOneWidget);

      await tester.tap(find.text('Accepter et continuer'));
      await tester.pumpAndSettle();
      expect(find.text('Vous devez accepter pour continuer.'), findsOneWidget);
      verifyNever(() => env.api.acceptTerms(any()));

      await tester.tap(find.byKey(const Key('consent')));
      await tester.tap(find.text('Accepter et continuer'));
      await tester.pumpAndSettle();

      verify(() => env.api.acceptTerms(Legal.termsVersion)).called(1);
      expect(here(), Routes.customers);
    });

    testWidgets('application trop ancienne pour la nouvelle version : demande de mise à jour, pas d\'acceptation à l\'aveugle', (tester) async {
      const pending = Profile(id: 'user-1', phone: '+2290167000001', businessName: 'B', plan: Plan.free, termsAccepted: false, termsVersion: '2099-01-01');
      await pumpApp(tester, session: const SignedIn(pending));
      expect(find.textContaining('trop ancienne'), findsOneWidget);
      expect(find.text('Accepter et continuer'), findsNothing);
    });

    testWidgets('exporter toutes mes données : télécharge le JSON et le partage', (tester) async {
      final sharer = _Sharer();
      when(() => env.api.exportMyData()).thenAnswer((_) async => const DownloadedFile(fileName: 'carne-mes-donnees.json', bytes: <int>[123, 125]));
      await pumpApp(tester, at: Routes.settings, extra: <Override>[fileSharerProvider.overrideWithValue(sharer)]);

      await reveal(tester, find.text('Exporter toutes mes données'));
      await tester.tap(find.text('Exporter toutes mes données'));
      await tester.pumpAndSettle();
      expect(sharer.shared.single.mimeType, 'application/json');
    });

    testWidgets('export hors connexion : message clair, rien partagé', (tester) async {
      final sharer = _Sharer();
      when(() => env.api.exportMyData()).thenThrow(const NetworkException());
      await pumpApp(tester, at: Routes.settings, extra: <Override>[fileSharerProvider.overrideWithValue(sharer)]);
      await reveal(tester, find.text('Exporter toutes mes données'));
      await tester.tap(find.text('Exporter toutes mes données'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pas de connexion'), findsOneWidget);
      expect(sharer.shared, isEmpty);
    });

    testWidgets('journal d\'activité : libellés lisibles, jamais les codes techniques', (tester) async {
      when(() => env.api.activity()).thenAnswer((_) async => <ActivityEvent>[
            ActivityEvent(action: 'PIN_LOCKED', at: DateTime(2026, 10, 4, 14, 5)),
            ActivityEvent(action: 'LOGIN', at: DateTime(2026, 10, 3, 9, 30)),
            ActivityEvent(action: 'NOUVEAU_CODE_INCONNU', at: DateTime(2026, 10, 2)),
          ]);
      await pumpApp(tester, at: Routes.activity);

      expect(find.text('Compte verrouillé après plusieurs codes PIN erronés'), findsOneWidget);
      expect(find.text('Connexion'), findsOneWidget);
      expect(find.text('Activité du compte'), findsWidgets);
      expect(find.textContaining('PIN_LOCKED'), findsNothing);
      expect(find.textContaining('NOUVEAU_CODE'), findsNothing);
      expect(find.text('4 oct. 2026 à 14:05'), findsOneWidget);
    });

    testWidgets('la page de réglages crédite la structure qui a conçu Carné', (tester) async {
      await pumpApp(tester, at: Routes.settings);
      await reveal(tester, find.text('Conçu et développé par'));
      expect(find.text('CIVORA CONSEIL ET SOLUTIONS'), findsOneWidget);
      // Le logo de l'éditeur est affiché et décrit pour les lecteurs d'écran.
      await reveal(tester, find.bySemanticsLabel('Logo CIVORA Conseil et Solutions'));
      expect(find.bySemanticsLabel('Logo CIVORA Conseil et Solutions'), findsOneWidget);
    });
  });
}
