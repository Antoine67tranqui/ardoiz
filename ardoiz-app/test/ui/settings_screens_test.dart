import 'dart:io';

import 'package:ardoiz/app/providers.dart';
import 'package:ardoiz/app/session_service.dart';
import 'package:ardoiz/app/sync_coordinator.dart';
import 'package:ardoiz/core/brand.dart';
import 'package:ardoiz/core/formatters.dart';
import 'package:ardoiz/core/money.dart';
import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/remote/backend_api.dart';
import 'package:ardoiz/ui/screens/settings/business_name_screen.dart';
import 'package:ardoiz/ui/screens/settings/change_pin_screen.dart';
import 'package:ardoiz/ui/screens/settings/reminder_rules_screen.dart';
import 'package:ardoiz/ui/screens/settings/settings_screen.dart';
import 'package:ardoiz/ui/screens/settings/subscription_screen.dart';
import 'package:ardoiz/ui/screens/settings/sync_issues_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../support/harness.dart';
import '../support/ui_harness.dart';

class _RecordingSharer implements FileSharer {
  final List<({String fileName, List<int> bytes, String mimeType})> shared = <({String fileName, List<int> bytes, String mimeType})>[];

  @override
  Future<void> share({required String fileName, required List<int> bytes, required String mimeType}) async {
    shared.add((fileName: fileName, bytes: bytes, mimeType: mimeType));
  }
}

void main() {
  late UiEnv env;
  late ProviderContainer container;
  late GoRouter router;

  setUpAll(() {
    registerFallbackValue(ReminderChannel.sms);
    registerFallbackValue(ReminderTone.neutral);
  });
  setUp(() => env = UiEnv());
  tearDown(() => env.dispose());

  Future<void> pump(
    WidgetTester tester, {
    required String initial,
    SessionState? session,
    List<Override> extraOverrides = const <Override>[],
    double textScale = 1,
  }) async {
    phoneScreen(tester);
    await tester.pumpWidget(buildTestApp(
      env,
      initialLocation: initial,
      session: session ?? const SignedIn(testProfile),
      extraOverrides: extraOverrides,
      textScale: textScale,
      screens: <String, ScreenBuilder>{
        '/home/settings': (_) => const SettingsScreen(),
        '/settings/business': (_) => const BusinessNameScreen(),
        '/settings/pin': (_) => const ChangePinScreen(),
        '/settings/subscription': (_) => const SubscriptionScreen(),
        '/settings/reminders': (_) => const ReminderRulesScreen(),
        '/settings/sync': (_) => const SyncIssuesScreen(),
      },
      onReady: (c, r) {
        container = c;
        router = r;
      },
    ));
    await tester.pumpAndSettle();
  }

  /// Fait défiler jusqu'au widget (même s'il est déjà construit mais hors écran).
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  group('réglages', () {
    testWidgets('affiche la boutique, le téléphone et le plan', (tester) async {
      await pump(tester, initial: '/home/settings');
      expect(find.text('Boutique Fatou'), findsWidgets);
      expect(find.text('+2290167000001'), findsOneWidget);
      expect(find.text('Plan gratuit'), findsOneWidget);
      await reveal(tester, find.text('${Brand.name} ${Brand.version}'));
      expect(find.text('${Brand.name} ${Brand.version}'), findsOneWidget);
    });

    testWidgets('Premium : indique la date de fin', (tester) async {
      await pump(tester, initial: '/home/settings', session: SignedIn(premiumProfile));
      expect(find.text('Premium jusqu\'au ${formatDate(DateTime.utc(2026, 11, 1))}'), findsOneWidget);
    });

    testWidgets('chaque ligne mène au bon écran', (tester) async {
      final targets = <String, String>{
        'Nom de la boutique': '/settings/business',
        'Abonnement': '/settings/subscription',
        'Relances automatiques': '/settings/reminders',
        'Changer mon code PIN': '/settings/pin',
      };
      for (final entry in targets.entries) {
        await pump(tester, initial: '/home/settings');
        await reveal(tester, find.text(entry.key));
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(find.text('ROUTE:${entry.value}'), findsNothing, reason: 'écran réel attendu pour ${entry.key}');
        expect(router.state.uri.toString(), entry.value);
      }
    });

    testWidgets('synchronisation : états hors ligne, en attente et dernière synchro', (tester) async {
      await pump(tester, initial: '/home/settings');
      await reveal(tester, find.text('Synchronisation'));
      expect(find.text('Pas encore synchronisé'), findsOneWidget);

      env.sync.emit(SyncState(pending: 2, lastSyncAt: DateTime(2026, 10, 4, 14, 5)));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 en attente d\'envoi'), findsOneWidget);
      expect(find.textContaining('4 oct. 2026 à 14:05'), findsOneWidget);

      env.sync.emit(const SyncState(online: false, pending: 1));
      await tester.pumpAndSettle();
      expect(find.text('Hors ligne · 1 modification en attente'), findsOneWidget);
    });

    testWidgets('« Synchroniser » lance la synchronisation, désactivé pendant celle-ci', (tester) async {
      await pump(tester, initial: '/home/settings');
      await reveal(tester, find.text('Synchroniser'));
      await tester.tap(find.text('Synchroniser'));
      await tester.pump();
      expect(env.sync.syncCalls, 1);

      env.sync.emit(const SyncState(syncing: true));
      await tester.pump();
      expect(find.text('En cours…'), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'En cours…')).onPressed, isNull);
    });

    testWidgets('modifications refusées : ligne d\'alerte visible seulement s\'il y en a', (tester) async {
      await pump(tester, initial: '/home/settings');
      expect(find.text('Modifications à vérifier'), findsNothing);

      env.sync.emit(const SyncState(blocked: 2));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Modifications à vérifier'));
      expect(find.text('2 refusées par le serveur'), findsOneWidget);
      await tester.tap(find.text('Modifications à vérifier'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/settings/sync');
    });

    testWidgets('export : télécharge le CSV et le partage', (tester) async {
      final sharer = _RecordingSharer();
      when(() => env.api.exportHistory()).thenAnswer((_) async => const DownloadedFile(fileName: 'carne-historique.csv', bytes: <int>[65, 66]));
      await pump(tester, initial: '/home/settings', extraOverrides: <Override>[fileSharerProvider.overrideWithValue(sharer)]);

      await reveal(tester, find.text('Exporter l\'historique'));
      await tester.tap(find.text('Exporter l\'historique'));
      await tester.pumpAndSettle();
      expect(sharer.shared.single.fileName, 'carne-historique.csv');
      expect(sharer.shared.single.bytes, <int>[65, 66]);
      expect(sharer.shared.single.mimeType, 'text/csv');
    });

    testWidgets('export hors connexion : message clair, rien partagé', (tester) async {
      final sharer = _RecordingSharer();
      when(() => env.api.exportHistory()).thenThrow(const NetworkException());
      await pump(tester, initial: '/home/settings', extraOverrides: <Override>[fileSharerProvider.overrideWithValue(sharer)]);

      await reveal(tester, find.text('Exporter l\'historique'));
      await tester.tap(find.text('Exporter l\'historique'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pas de connexion'), findsOneWidget);
      expect(sharer.shared, isEmpty);
    });

    testWidgets('déconnexion : confirmation, synchronisation préalable, données effacées', (tester) async {
      when(() => env.api.logout()).thenAnswer((_) async {});
      final customer = env.repo.addCustomer(name: 'Aïcha', phone: '+22901670000');
      env.outbox.clear(); // tout est envoyé
      await pump(tester, initial: '/home/settings');

      await reveal(tester, find.text('Se déconnecter'));
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.textContaining('effacées de ce téléphone'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Se déconnecter'));
      await tester.pumpAndSettle();

      expect(env.sync.syncCalls, 1, reason: 'on envoie ce qui peut l\'être avant de partir');
      verify(() => env.api.logout()).called(1);
      expect(container.read(sessionProvider), isA<SignedOut>());
      expect(env.ledger.customer(customer.id), isNull);
    });

    testWidgets('déconnexion annulée : rien ne change', (tester) async {
      await pump(tester, initial: '/home/settings');
      await reveal(tester, find.text('Se déconnecter'));
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(container.read(sessionProvider), isA<SignedIn>());
      verifyNever(() => env.api.logout());
    });

    testWidgets('données non envoyées : avertit, puis déconnecte seulement sur confirmation de la perte', (tester) async {
      when(() => env.api.logout()).thenAnswer((_) async {});
      final customer = env.repo.addCustomer(name: 'Aïcha', phone: '+22901670000'); // reste dans la file d'envoi
      await pump(tester, initial: '/home/settings');

      await reveal(tester, find.text('Se déconnecter'));
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Se déconnecter'));
      await tester.pumpAndSettle();

      expect(find.text('Données non envoyées'), findsOneWidget);
      expect(find.textContaining('1 modification n\'a pas encore été envoyée'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(container.read(sessionProvider), isA<SignedIn>());
      expect(env.ledger.customer(customer.id), isNotNull);
      verifyNever(() => env.api.logout());

      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Se déconnecter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Déconnecter et perdre'));
      await tester.pumpAndSettle();
      expect(container.read(sessionProvider), isA<SignedOut>());
      expect(env.ledger.customer(customer.id), isNull);
    });

    testWidgets('texte agrandi : pas de débordement', (tester) async {
      await pump(tester, initial: '/home/settings', textScale: 2);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('nom de la boutique', () {
    testWidgets('prérempli ; enregistre via le serveur et met à jour la session', (tester) async {
      when(() => env.api.updateBusinessName('Chez Fatou')).thenAnswer((_) async => const Profile(
            id: 'user-1',
            phone: '+2290167000001',
            businessName: 'Chez Fatou',
            plan: Plan.free,
          ));
      await pump(tester, initial: '/settings/business');
      expect(find.widgetWithText(TextFormField, 'Boutique Fatou'), findsOneWidget);

      await tester.enterText(field('Nom de la boutique'), '  Chez Fatou ');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      verify(() => env.api.updateBusinessName('Chez Fatou')).called(1);
      expect((container.read(sessionProvider) as SignedIn).profile.businessName, 'Chez Fatou');
    });

    testWidgets('nom vide refusé sans appel réseau ; erreur réseau affichée', (tester) async {
      when(() => env.api.updateBusinessName(any())).thenThrow(const NetworkException());
      await pump(tester, initial: '/settings/business');

      await tester.enterText(field('Nom de la boutique'), '   ');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Saisissez le nom de votre boutique.'), findsOneWidget);
      verifyNever(() => env.api.updateBusinessName(any()));

      await tester.enterText(field('Nom de la boutique'), 'Nouveau');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pas de connexion'), findsOneWidget);
      expect((container.read(sessionProvider) as SignedIn).profile.businessName, 'Boutique Fatou');
    });
  });

  group('changement de PIN', () {
    Future<void> fill(WidgetTester tester, {String current = '1234', String next = '5678', String? confirm}) async {
      await tester.enterText(find.byKey(const Key('pin-current')), current);
      await tester.enterText(find.byKey(const Key('pin-new')), next);
      await tester.enterText(find.byKey(const Key('pin-confirm')), confirm ?? next);
      await tester.tap(find.text('Changer le code'));
      await tester.pumpAndSettle();
    }

    testWidgets('valide les trois champs avant tout appel réseau', (tester) async {
      await pump(tester, initial: '/settings/pin');

      await fill(tester, current: '12', next: '5678');
      expect(find.text('Le code PIN comporte exactement 4 chiffres.'), findsOneWidget);

      await fill(tester, current: '1234', next: '1234');
      expect(find.text('Choisissez un code différent de l\'actuel.'), findsOneWidget);

      await fill(tester, current: '1234', next: '5678', confirm: '5679');
      expect(find.text('Les deux codes ne sont pas identiques.'), findsOneWidget);
      verifyNever(() => env.api.changePin(currentPin: any(named: 'currentPin'), newPin: any(named: 'newPin')));
    });

    testWidgets('succès : appelle le serveur et confirme', (tester) async {
      when(() => env.api.changePin(currentPin: '1234', newPin: '5678')).thenAnswer((_) async {});
      await pump(tester, initial: '/settings/pin');
      await fill(tester);
      verify(() => env.api.changePin(currentPin: '1234', newPin: '5678')).called(1);
    });

    testWidgets('PIN actuel erroné : message du serveur, on reste sur l\'écran', (tester) async {
      when(() => env.api.changePin(currentPin: any(named: 'currentPin'), newPin: any(named: 'newPin')))
          .thenThrow(const RejectedException(400, 'Le PIN actuel est incorrect'));
      await pump(tester, initial: '/settings/pin');
      await fill(tester, current: '0000');
      expect(find.text('Le PIN actuel est incorrect'), findsOneWidget);
      expect(find.text('Changer le code'), findsOneWidget);
    });
  });

  group('abonnement', () {
    SubscriptionStatus free({int customers = 3}) =>
        SubscriptionStatus(plan: Plan.free, customerCount: customers, customerLimit: 15, monthlyPrice: const Money.fromCents(200000));

    testWidgets('plan gratuit : situation, comparatif et prix', (tester) async {
      when(() => env.api.subscriptionStatus()).thenAnswer((_) async => free());
      await pump(tester, initial: '/settings/subscription');

      expect(find.text('Gratuit'), findsWidgets);
      expect(find.text('3 clients sur 15 autorisés'), findsOneWidget);
      expect(find.text('Clients'), findsOneWidget);
      expect(find.text('Passer à Premium (${formatMoney(const Money.fromCents(200000))} / mois)'), findsOneWidget);
    });

    testWidgets('paiement confirmé : active Premium, rafraîchit le profil et annonce le résultat', (tester) async {
      var status = free();
      when(() => env.api.subscriptionStatus()).thenAnswer((_) async => status);
      when(() => env.api.upgrade()).thenAnswer((_) async {
        status = SubscriptionStatus(
          plan: Plan.premium,
          planExpiresAt: DateTime.utc(2026, 11, 3),
          customerCount: 3,
          monthlyPrice: const Money.fromCents(200000),
        );
        return const UpgradeResult(activated: true, simulated: false, message: 'Premium activé.');
      });
      when(() => env.api.profile()).thenAnswer((_) async => premiumProfile);
      await pump(tester, initial: '/settings/subscription');

      await tester.tap(find.textContaining('Passer à Premium ('));
      await tester.pumpAndSettle();
      expect(find.textContaining('Premium dure 30 jours'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Payer ${formatMoney(const Money.fromCents(200000))}'));
      await tester.pumpAndSettle();

      verify(() => env.api.upgrade()).called(1);
      expect(find.text('Premium activé.'), findsOneWidget);
      expect(find.text('Actif jusqu\'au ${formatDate(DateTime.utc(2026, 11, 3))}'), findsOneWidget);
      expect(container.read(isPremiumProvider), isTrue);
    });

    testWidgets('paiement en attente de confirmation : n\'active rien et le dit', (tester) async {
      when(() => env.api.subscriptionStatus()).thenAnswer((_) async => free());
      when(() => env.api.upgrade())
          .thenAnswer((_) async => const UpgradeResult(activated: false, simulated: false, message: 'Validez le paiement sur votre téléphone.'));
      await pump(tester, initial: '/settings/subscription');

      await tester.tap(find.textContaining('Passer à Premium ('));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Payer ${formatMoney(const Money.fromCents(200000))}'));
      await tester.pumpAndSettle();

      expect(find.text('Validez le paiement sur votre téléphone.'), findsOneWidget);
      expect(container.read(isPremiumProvider), isFalse);
      verifyNever(() => env.api.profile());
    });

    testWidgets('annulation de la confirmation : aucun paiement', (tester) async {
      when(() => env.api.subscriptionStatus()).thenAnswer((_) async => free());
      await pump(tester, initial: '/settings/subscription');
      await tester.tap(find.textContaining('Passer à Premium ('));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      verifyNever(() => env.api.upgrade());
    });

    testWidgets('service de paiement indisponible : message du serveur, pas de crash', (tester) async {
      when(() => env.api.subscriptionStatus()).thenAnswer((_) async => free());
      when(() => env.api.upgrade()).thenThrow(const ServerException(503, 'indisponible'));
      await pump(tester, initial: '/settings/subscription');
      await tester.tap(find.textContaining('Passer à Premium ('));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Payer ${formatMoney(const Money.fromCents(200000))}'));
      await tester.pumpAndSettle();
      expect(find.textContaining('momentanément indisponible'), findsOneWidget);
    });

    testWidgets('hors connexion : écran d\'erreur avec « Réessayer »', (tester) async {
      var online = false;
      when(() => env.api.subscriptionStatus()).thenAnswer((_) async {
        if (!online) throw const NetworkException();
        return free();
      });
      await pump(tester, initial: '/settings/subscription');
      expect(find.text('Abonnement indisponible'), findsOneWidget);

      online = true;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Votre abonnement'), findsOneWidget);
    });
  });

  group('relances automatiques', () {
    ReminderRule rule(String id, int offset, {ReminderTone tone = ReminderTone.neutral, bool enabled = true}) =>
        ReminderRule(id: id, offsetDays: offset, channel: ReminderChannel.sms, tone: tone, enabled: enabled);

    testWidgets('plan gratuit : présentation Premium, aucun appel serveur', (tester) async {
      await pump(tester, initial: '/settings/reminders');
      expect(find.text('Réservé à Premium'), findsOneWidget);
      verifyNever(() => env.api.reminderRules());
      await tester.tap(find.text('Découvrir Premium'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/settings/subscription');
    });

    testWidgets('Premium : liste les relances avec un libellé clair', (tester) async {
      when(() => env.api.reminderRules()).thenAnswer((_) async => <ReminderRule>[
            rule('1', -3, tone: ReminderTone.gentle),
            rule('2', 0),
            rule('3', 1, tone: ReminderTone.firm, enabled: false),
          ]);
      await pump(tester, initial: '/settings/reminders', session: SignedIn(premiumProfile));
      expect(find.text('3 jours avant l\'échéance'), findsOneWidget);
      expect(find.text('Le jour de l\'échéance'), findsOneWidget);
      expect(find.text('1 jour après l\'échéance'), findsOneWidget);
      expect(find.text('SMS · ton courtois'), findsOneWidget);
    });

    testWidgets('activer / désactiver enregistre et recharge', (tester) async {
      when(() => env.api.reminderRules()).thenAnswer((_) async => <ReminderRule>[rule('1', 7, tone: ReminderTone.firm)]);
      when(() => env.api.saveReminderRule(
            offsetDays: any(named: 'offsetDays'),
            channel: any(named: 'channel'),
            tone: any(named: 'tone'),
            enabled: any(named: 'enabled'),
          )).thenAnswer((_) async => rule('1', 7, tone: ReminderTone.firm, enabled: false));
      await pump(tester, initial: '/settings/reminders', session: SignedIn(premiumProfile));

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      verify(() => env.api.saveReminderRule(offsetDays: 7, channel: ReminderChannel.sms, tone: ReminderTone.firm, enabled: false)).called(1);
      verify(() => env.api.reminderRules()).called(2);
    });

    testWidgets('ajout : 2 jours avant, ton ferme', (tester) async {
      when(() => env.api.reminderRules()).thenAnswer((_) async => <ReminderRule>[]);
      when(() => env.api.saveReminderRule(
            offsetDays: any(named: 'offsetDays'),
            channel: any(named: 'channel'),
            tone: any(named: 'tone'),
            enabled: any(named: 'enabled'),
          )).thenAnswer((_) async => rule('9', -2));
      await pump(tester, initial: '/settings/reminders', session: SignedIn(premiumProfile));
      expect(find.text('Aucune relance'), findsOneWidget);

      await tester.tap(find.text('Ajouter une relance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avant'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Un jour de moins')); // 3 -> 2
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ferme'));
      await tester.pumpAndSettle();
      expect(find.text('2 jours avant l\'échéance'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();

      verify(() => env.api.saveReminderRule(offsetDays: -2, channel: ReminderChannel.sms, tone: ReminderTone.firm, enabled: true)).called(1);
    });

    testWidgets('suppression après confirmation seulement', (tester) async {
      when(() => env.api.reminderRules()).thenAnswer((_) async => <ReminderRule>[rule('1', 7)]);
      when(() => env.api.deleteReminderRule('1')).thenAnswer((_) async {});
      await pump(tester, initial: '/settings/reminders', session: SignedIn(premiumProfile));

      await tester.tap(find.byTooltip('Supprimer cette relance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      verifyNever(() => env.api.deleteReminderRule(any()));

      await tester.tap(find.byTooltip('Supprimer cette relance'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      verify(() => env.api.deleteReminderRule('1')).called(1);
    });

    testWidgets('erreur réseau à l\'enregistrement : message, la liste reste affichée', (tester) async {
      when(() => env.api.reminderRules()).thenAnswer((_) async => <ReminderRule>[rule('1', 7)]);
      when(() => env.api.saveReminderRule(
            offsetDays: any(named: 'offsetDays'),
            channel: any(named: 'channel'),
            tone: any(named: 'tone'),
            enabled: any(named: 'enabled'),
          )).thenThrow(const NetworkException());
      await pump(tester, initial: '/settings/reminders', session: SignedIn(premiumProfile));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pas de connexion'), findsOneWidget);
      expect(find.text('7 jours après l\'échéance'), findsOneWidget);
    });

    test('describeOffset', () {
      expect(describeOffset(-1), '1 jour avant l\'échéance');
      expect(describeOffset(0), 'Le jour de l\'échéance');
      expect(describeOffset(14), '14 jours après l\'échéance');
    });
  });

  group('modifications à vérifier', () {
    testWidgets('liste vide : tout est en ordre', (tester) async {
      await pump(tester, initial: '/settings/sync');
      expect(find.text('Tout est en ordre'), findsOneWidget);
    });

    testWidgets('affiche la raison ; « Réessayer » relance, « Abandonner » annule les effets locaux', (tester) async {
      final customer = env.repo.addCustomer(name: 'Aïcha', phone: '+22901670000');
      final debt = env.repo.addDebt(customerId: customer.id, amount: fcfa(5000));
      env.outbox.block(env.outbox.all().first, 'Limite du plan gratuit atteinte');
      await pump(tester, initial: '/settings/sync');

      expect(find.text('Nouveau client « Aïcha »'), findsOneWidget);
      expect(find.text('Limite du plan gratuit atteinte'), findsOneWidget);
      expect(find.text('Dépend d\'une opération refusée par le serveur.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Réessayer').first);
      await tester.pumpAndSettle();
      expect(env.outbox.blocked(), isEmpty);
      expect(env.sync.syncCalls, 1);
      expect(find.text('Tout est en ordre'), findsOneWidget);

      env.outbox.block(env.outbox.all().first, 'Refusé');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Abandonner').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(env.ledger.customer(customer.id), isNotNull);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Abandonner').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
      await tester.pumpAndSettle();
      expect(env.ledger.customer(customer.id), isNull);
      expect(env.ledger.debt(debt.id), isNull);
      expect(env.outbox.count(), 0);
      expect(find.text('Tout est en ordre'), findsOneWidget);
    });
  });

  test('la version de la marque correspond à pubspec.yaml', () {
    // Dépendance volontaire : un changement de version doit être fait aux deux endroits.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(Brand.version, version);
  });
}
