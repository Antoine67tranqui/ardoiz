import 'package:ardoiz/app/providers.dart';
import 'package:ardoiz/app/session_service.dart';
import 'package:ardoiz/app/signup_flow.dart';
import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/remote/backend_api.dart';
import 'package:ardoiz/ui/screens/auth/login_screen.dart';
import 'package:ardoiz/ui/screens/auth/otp_screen.dart';
import 'package:ardoiz/ui/screens/auth/pin_setup_screen.dart';
import 'package:ardoiz/ui/screens/auth/signup_phone_screen.dart';
import 'package:ardoiz/ui/screens/auth/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/ui_harness.dart';

/// Parcours d'inscription déjà vérifié par SMS (état de départ de l'écran du PIN).
class _VerifiedFlow extends SignupFlowNotifier {
  _VerifiedFlow({required this.isNew});

  final bool isNew;

  @override
  SignupFlow build() => SignupFlow(phone: '+2290167000001', otpSessionToken: 'tok', isNewUser: isNew);
}

void main() {
  late UiEnv env;
  late ProviderContainer container;

  setUp(() => env = UiEnv());
  tearDown(() => env.dispose());

  Future<void> pump(
    WidgetTester tester, {
    required String initial,
    required Map<String, ScreenBuilder> screens,
    SessionState session = const SignedOut(),
    List<Override> extraOverrides = const <Override>[],
  }) async {
    phoneScreen(tester);
    await tester.pumpWidget(buildTestApp(
      env,
      initialLocation: initial,
      screens: screens,
      session: session,
      extraOverrides: extraOverrides,
      onReady: (c, _) => container = c,
    ));
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.byKey(Key(key));

  /// Fait défiler jusqu'au widget avant de le toucher (les écrans d'accès défilent).
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  group('accueil', () {
    testWidgets('présente la marque et mène à l\'inscription ou à la connexion', (tester) async {
      await pump(tester, initial: '/welcome', screens: {'/welcome': (_) => const WelcomeScreen()});

      expect(find.text('Bienvenue sur Carné'), findsOneWidget);
      expect(find.text('Le carnet de crédit de votre commerce'), findsOneWidget);
      expect(find.textContaining('sans internet'), findsOneWidget);

      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(find.text('ROUTE:/signup'), findsOneWidget);
    });

    testWidgets('« J\'ai déjà un compte » mène à la connexion', (tester) async {
      await pump(tester, initial: '/welcome', screens: {'/welcome': (_) => const WelcomeScreen()});
      await tester.tap(find.text('J\'ai déjà un compte'));
      await tester.pumpAndSettle();
      expect(find.text('ROUTE:/login'), findsOneWidget);
    });
  });

  group('connexion', () {
    Map<String, ScreenBuilder> screens({String? phone}) => {'/login': (_) => LoginScreen(phone: phone)};

    testWidgets('valide les champs avant tout appel réseau', (tester) async {
      await pump(tester, initial: '/login', screens: screens());

      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(find.textContaining('indicatif du pays'), findsNothing); // vide : message dédié
      expect(find.text('Saisissez votre numéro de téléphone.'), findsOneWidget);
      expect(find.text('Le code PIN comporte exactement 4 chiffres.'), findsOneWidget);
      verifyNever(() => env.api.login(phone: any(named: 'phone'), pin: any(named: 'pin')));
    });

    testWidgets('refuse un numéro sans indicatif et un PIN trop court', (tester) async {
      await pump(tester, initial: '/login', screens: screens());
      await tester.enterText(field('phone'), '0167077027');
      await tester.enterText(field('pin'), '12');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(find.textContaining('indicatif du pays'), findsOneWidget);
      expect(find.text('Le code PIN comporte exactement 4 chiffres.'), findsOneWidget);
    });

    testWidgets('connexion réussie : envoie le numéro normalisé et ouvre la session', (tester) async {
      when(() => env.api.login(phone: any(named: 'phone'), pin: any(named: 'pin')))
          .thenAnswer((_) async => const SessionTokens(accessToken: 'a', refreshToken: 'r'));
      when(() => env.api.profile()).thenAnswer((_) async => testProfile);
      await pump(tester, initial: '/login', screens: screens());

      await tester.enterText(field('phone'), '+229 01 67 07 00 01');
      await tester.enterText(field('pin'), '1234');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      verify(() => env.api.login(phone: '+2290167070001', pin: '1234')).called(1);
      expect(container.read(sessionProvider), isA<SignedIn>());
    });

    testWidgets('mauvais PIN : message clair, rien n\'est ouvert, le PIN reste à ressaisir', (tester) async {
      when(() => env.api.login(phone: any(named: 'phone'), pin: any(named: 'pin')))
          .thenThrow(const RejectedException(401, 'Identifiants invalides'));
      await pump(tester, initial: '/login', screens: screens());

      await tester.enterText(field('phone'), '+2290167000001');
      await tester.enterText(field('pin'), '0000');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(find.text('Numéro ou code PIN incorrect.'), findsOneWidget);
      expect(container.read(sessionProvider), isA<SignedOut>());
    });

    testWidgets('compte verrouillé : affiche le message du serveur avec la durée', (tester) async {
      when(() => env.api.login(phone: any(named: 'phone'), pin: any(named: 'pin')))
          .thenThrow(const RejectedException(401, 'Trop de tentatives echouees. Reessayez dans 14 minute(s).'));
      await pump(tester, initial: '/login', screens: screens());

      await tester.enterText(field('phone'), '+2290167000001');
      await tester.enterText(field('pin'), '0000');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(find.textContaining('14 minute(s)'), findsOneWidget);
    });

    testWidgets('hors ligne : message de réseau, pas de trace technique', (tester) async {
      when(() => env.api.login(phone: any(named: 'phone'), pin: any(named: 'pin'))).thenThrow(const NetworkException());
      await pump(tester, initial: '/login', screens: screens());

      await tester.enterText(field('phone'), '+2290167000001');
      await tester.enterText(field('pin'), '1234');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Pas de connexion'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('session expirée : numéro pré-rempli et explication rassurante', (tester) async {
      await pump(
        tester,
        initial: '/login',
        screens: screens(),
        session: const SignedOut(phone: '+2290167000001', reason: SignedOutReason.expired),
      );

      expect(find.textContaining('vos données sont conservées'), findsOneWidget);
      expect(tester.widget<TextFormField>(field('phone')).controller!.text, '+2290167000001');
    });

    testWidgets('le PIN est masqué et limité à 4 chiffres', (tester) async {
      await pump(tester, initial: '/login', screens: screens());
      await tester.enterText(field('pin'), '12ab3456');
      await tester.pump();

      final editable = tester.widget<EditableText>(find.descendant(of: field('pin'), matching: find.byType(EditableText)));
      expect(editable.obscureText, isTrue);
      expect(editable.controller.text, '1234');
    });

    testWidgets('saisies d\'un autre compte non envoyées : demande confirmation avant de les perdre', (tester) async {
      var calls = 0;
      when(() => env.api.login(phone: any(named: 'phone'), pin: any(named: 'pin')))
          .thenAnswer((_) async => const SessionTokens(accessToken: 'a', refreshToken: 'r'));
      when(() => env.api.profile()).thenAnswer((_) async {
        calls++;
        return const Profile(id: 'autre-compte', phone: '+2290167000002', businessName: 'B', plan: Plan.free);
      });
      env.ledger.setMeta('user_id', 'user-1');
      env.repo.addCustomer(name: 'Saisie non envoyée', phone: '+229 01 67 07 70 27');
      await pump(tester, initial: '/login', screens: screens());

      await tester.enterText(field('phone'), '+2290167000002');
      await tester.enterText(field('pin'), '1234');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(find.text('Données non envoyées'), findsOneWidget);
      expect(env.ledger.customers(), hasLength(1)); // rien perdu à ce stade
      expect(container.read(sessionProvider), isA<SignedOut>());

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(env.ledger.customers(), hasLength(1));

      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer et perdre'));
      await tester.pumpAndSettle();

      expect(env.ledger.customers(), isEmpty);
      expect(container.read(sessionProvider), isA<SignedIn>());
      expect(calls, 3); // 1er essai, nouvel essai après « Annuler », puis confirmation
    });

    testWidgets('« Code PIN oublié ? » mène au parcours SMS avec le numéro déjà saisi', (tester) async {
      await pump(tester, initial: '/login', screens: screens());
      await tester.enterText(field('phone'), '+2290167000001');
      await tester.tap(find.text('Code PIN oublié ?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ROUTE:/signup?phone='), findsOneWidget);
    });
  });

  group('inscription par SMS', () {
    testWidgets('numéro invalide : aucune demande de code', (tester) async {
      await pump(tester, initial: '/signup', screens: {'/signup': (_) => const SignupPhoneScreen()});
      await tester.enterText(field('phone'), '123');
      await tester.tap(find.text('Recevoir le code'));
      await tester.pumpAndSettle();

      expect(find.textContaining('indicatif du pays'), findsOneWidget);
      verifyNever(() => env.api.requestOtp(any()));
    });

    testWidgets('demande le code, mémorise le numéro, passe à la saisie du code', (tester) async {
      when(() => env.api.requestOtp(any())).thenAnswer((_) async => const OtpRequestResult());
      await pump(tester, initial: '/signup', screens: {'/signup': (_) => const SignupPhoneScreen()});

      await tester.enterText(field('phone'), '+229 01 67 07 00 01');
      await tester.tap(find.text('Recevoir le code'));
      await tester.pumpAndSettle();

      verify(() => env.api.requestOtp('+2290167070001')).called(1);
      expect(container.read(signupFlowProvider).phone, '+2290167070001');
      expect(find.text('ROUTE:/signup/code'), findsOneWidget);
    });

    testWidgets('délai de 60 s entre deux envois : le message du serveur est affiché', (tester) async {
      when(() => env.api.requestOtp(any())).thenThrow(const RejectedException(429, 'Un code vient d\'etre envoye. Patientez 60 secondes.'));
      await pump(tester, initial: '/signup', screens: {'/signup': (_) => const SignupPhoneScreen()});

      await tester.enterText(field('phone'), '+2290167000001');
      await tester.tap(find.text('Recevoir le code'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Patientez 60 secondes'), findsOneWidget);
      expect(find.text('ROUTE:/signup/code'), findsNothing);
    });

    testWidgets('« PIN oublié » : le numéro transmis est pré-rempli', (tester) async {
      await pump(tester, initial: '/signup', screens: {'/signup': (_) => const SignupPhoneScreen(phone: '+2290167000001')});
      expect(tester.widget<TextFormField>(field('phone')).controller!.text, '+2290167000001');
    });
  });

  group('saisie du code SMS', () {
    void startFlow({String? devCode}) {
      container.read(signupFlowProvider.notifier).codeSent(phone: '+2290167000001', devCode: devCode);
    }

    Future<void> pumpOtp(WidgetTester tester, {String? devCode}) async {
      await pump(tester, initial: '/signup/code', screens: {'/signup/code': (_) => const OtpScreen()});
      startFlow(devCode: devCode);
      await tester.pumpAndSettle();
    }

    testWidgets('refuse un code incomplet, accepte 6 chiffres et passe à la création du PIN', (tester) async {
      when(() => env.api.verifyOtp(any(), any())).thenAnswer((_) async => const OtpVerification(otpSessionToken: 'tok', isNewUser: true));
      await pumpOtp(tester);

      await tester.enterText(field('otp'), '123');
      await tester.tap(find.text('Vérifier'));
      await tester.pumpAndSettle();
      expect(find.text('Le code reçu par SMS comporte 6 chiffres.'), findsOneWidget);
      verifyNever(() => env.api.verifyOtp(any(), any()));

      await tester.enterText(field('otp'), '123456');
      await tester.tap(find.text('Vérifier'));
      await tester.pumpAndSettle();

      verify(() => env.api.verifyOtp('+2290167000001', '123456')).called(1);
      expect(container.read(signupFlowProvider).otpSessionToken, 'tok');
      expect(find.text('ROUTE:/signup/pin'), findsOneWidget);
    });

    testWidgets('mauvais code : message du serveur, on reste sur l\'écran', (tester) async {
      when(() => env.api.verifyOtp(any(), any())).thenThrow(const RejectedException(400, 'Code OTP invalide'));
      await pumpOtp(tester);

      await tester.enterText(field('otp'), '000000');
      await tester.tap(find.text('Vérifier'));
      await tester.pumpAndSettle();

      expect(find.text('Code OTP invalide'), findsOneWidget);
      expect(find.text('ROUTE:/signup/pin'), findsNothing);
    });

    testWidgets('le renvoi est bloqué 60 s (compte à rebours) puis proposé ; un nouvel envoi remet le compte à rebours', (tester) async {
      when(() => env.api.requestOtp(any())).thenAnswer((_) async => const OtpRequestResult());
      await pumpOtp(tester);

      expect(find.text('Renvoyer le code dans 60 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 59));
      expect(find.text('Renvoyer le code dans 1 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Renvoyer le code'), findsOneWidget);

      await tester.tap(find.text('Renvoyer le code'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      verify(() => env.api.requestOtp('+2290167000001')).called(1);
      expect(find.text('Renvoyer le code dans 60 s'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // libère les minuteurs
    });

    testWidgets('serveur de test : affiche le code ; en production (aucun code renvoyé) rien n\'est affiché', (tester) async {
      await pumpOtp(tester, devCode: '482915');
      expect(find.textContaining('Votre code est 482915'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      env.dispose();
      env = UiEnv();
      await pumpOtp(tester);
      expect(find.textContaining('Serveur de test'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('création du PIN', () {
    Future<void> pumpPin(WidgetTester tester, {bool isNew = true}) => pump(
          tester,
          initial: '/signup/pin',
          screens: {'/signup/pin': (_) => const PinSetupScreen()},
          extraOverrides: [signupFlowProvider.overrideWith(() => _VerifiedFlow(isNew: isNew))],
        );

    testWidgets('refuse un PIN de confirmation différent, un PIN court et un nom vide', (tester) async {
      await pumpPin(tester);

      await tapVisible(tester, find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(find.text('Saisissez le nom de votre boutique.'), findsOneWidget);

      await tester.enterText(field('business'), 'Boutique Awa');
      await tester.enterText(field('pin'), '1234');
      await tester.enterText(field('confirm'), '4321');
      await tapVisible(tester, find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(find.text('Les deux codes PIN ne correspondent pas.'), findsOneWidget);
      verifyNever(() => env.api.setupPin(otpSessionToken: any(named: 'otpSessionToken'), businessName: any(named: 'businessName'), pin: any(named: 'pin'), termsVersion: any(named: 'termsVersion')));
    });

    testWidgets('crée le compte : envoie le jeton OTP, le nom nettoyé et le PIN, ouvre la session, réinitialise le parcours', (tester) async {
      when(() => env.api.setupPin(otpSessionToken: any(named: 'otpSessionToken'), businessName: any(named: 'businessName'), pin: any(named: 'pin'), termsVersion: any(named: 'termsVersion')))
          .thenAnswer((_) async => const SessionTokens(accessToken: 'a', refreshToken: 'r'));
      when(() => env.api.profile()).thenAnswer((_) async => testProfile);
      await pumpPin(tester);

      await tester.enterText(field('business'), '  Boutique Awa  ');
      await tester.enterText(field('pin'), '4321');
      await tester.enterText(field('confirm'), '4321');
      await tapVisible(tester, find.byKey(const Key('consent')));
      await tapVisible(tester, find.text('Créer mon compte'));
      await tester.pumpAndSettle();

      verify(() => env.api.setupPin(otpSessionToken: 'tok', businessName: 'Boutique Awa', pin: '4321', termsVersion: any(named: 'termsVersion'))).called(1);
      expect(container.read(sessionProvider), isA<SignedIn>());
      expect(container.read(signupFlowProvider).phone, isNull);
    });

    testWidgets('sans consentement explicite, aucun compte n\'est créé (case jamais cochée d\'avance)', (tester) async {
      await pumpPin(tester);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('consent'))).value, isFalse);

      await tester.enterText(field('business'), 'Boutique Awa');
      await tester.enterText(field('pin'), '4321');
      await tester.enterText(field('confirm'), '4321');
      await tapVisible(tester, find.text('Créer mon compte'));
      await tester.pumpAndSettle();

      expect(find.text('Vous devez accepter pour continuer.'), findsOneWidget);
      verifyNever(() => env.api.setupPin(otpSessionToken: any(named: 'otpSessionToken'), businessName: any(named: 'businessName'), pin: any(named: 'pin'), termsVersion: any(named: 'termsVersion')));
    });

    testWidgets('le résumé « ce que Carné fait de mes données » est lisible dans l\'application', (tester) async {
      await pumpPin(tester);
      await tester.ensureVisible(find.text('Voir ce que Carné fait de mes données'));
      await tester.tap(find.text('Voir ce que Carné fait de mes données'));
      await tester.pumpAndSettle();
      expect(find.text('Vos données et Carné'), findsOneWidget);
      expect(find.textContaining('empreinte de votre code PIN'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('supprimer votre compte'), 100, scrollable: find.byType(Scrollable).last);
      expect(find.textContaining('supprimer votre compte'), findsOneWidget);
    });

    testWidgets('PIN oublié (compte existant) : libellés de réinitialisation', (tester) async {
      await pumpPin(tester, isNew: false);
      expect(find.text('Choisissez un nouveau PIN'), findsOneWidget);
      expect(find.text('Enregistrer le nouveau PIN'), findsOneWidget);
      expect(find.textContaining('autres appareils devront se reconnecter'), findsOneWidget);
    });

    testWidgets('sans vérification préalable (retour arrière), on est renvoyé au début du parcours', (tester) async {
      await pump(tester, initial: '/signup/pin', screens: {'/signup/pin': (_) => const PinSetupScreen()});
      await tester.pumpAndSettle();
      expect(find.text('ROUTE:/signup'), findsOneWidget);
    });

    testWidgets('session OTP expirée : erreur claire, bouton de nouveau disponible', (tester) async {
      when(() => env.api.setupPin(otpSessionToken: any(named: 'otpSessionToken'), businessName: any(named: 'businessName'), pin: any(named: 'pin'), termsVersion: any(named: 'termsVersion')))
          .thenThrow(const UnauthorizedException('Session OTP invalide ou expiree'));
      await pumpPin(tester);

      await tester.enterText(field('business'), 'Boutique Awa');
      await tester.enterText(field('pin'), '4321');
      await tester.enterText(field('confirm'), '4321');
      await tapVisible(tester, find.byKey(const Key('consent')));
      await tapVisible(tester, find.text('Créer mon compte'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Session OTP invalide'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });
  });
}
