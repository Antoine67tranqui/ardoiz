import 'package:ardoiz/app/session_service.dart';
import 'package:ardoiz/data/local/app_database.dart';
import 'package:ardoiz/data/local/ledger_store.dart';
import 'package:ardoiz/data/local/outbox_store.dart';
import 'package:ardoiz/data/local/secret_store.dart';
import 'package:ardoiz/data/remote/api_client.dart';
import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/remote/backend_api.dart';
import 'package:ardoiz/data/remote/token_store.dart';
import 'package:ardoiz/data/repositories/ledger_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/harness.dart';
import '../support/scripted_adapter.dart';

void main() {
  late FakeBackendApi api;
  late InMemorySecretStore secrets;
  late TokenStore tokens;
  late AppDatabase db;
  late SessionService service;
  late LedgerStore ledger;
  late OutboxStore outbox;
  late LedgerRepository repo;
  late ScriptedAdapter revokeAdapter;

  setUp(() {
    api = FakeBackendApi();
    secrets = InMemorySecretStore();
    tokens = TokenStore(secrets);
    db = AppDatabase.openInMemory(hexKey: testKey);
    ledger = LedgerStore(db);
    outbox = OutboxStore(db);
    repo = LedgerRepository(db: db);
    revokeAdapter = ScriptedAdapter((r) => ScriptedResponse(201, {'message': 'Deconnecte'}));
    service = SessionService(
      api: api,
      tokens: tokens,
      secrets: secrets,
      db: db,
      clientFactory: (isolated) => ApiClient(
        baseUrl: 'http://api.test',
        tokens: isolated,
        dio: Dio()..httpClientAdapter = revokeAdapter,
        refreshDio: Dio()..httpClientAdapter = ScriptedAdapter((r) => ScriptedResponse(201, {'accessToken': 'a2', 'refreshToken': 'r2'})),
      ),
    );
  });
  tearDown(() => db.close());

  group('connexion', () {
    test('enregistre les jetons, met le profil en cache et lie la base au compte', () async {
      final account = api.addAccount();

      final state = await service.login(phone: account.phone, pin: '1234');

      expect(state.profile.businessName, 'Boutique A');
      expect(await tokens.hasSession, isTrue);
      expect(ledger.meta('user_id'), account.id);
      expect(ledger.meta('profile'), contains('Boutique A'));
    });

    test('mauvais PIN : erreur, aucun jeton conservé', () async {
      api.addAccount();
      await expectLater(service.login(phone: '+2290167000001', pin: '0000'), throwsA(isA<RejectedException>()));
      expect(await tokens.hasSession, isFalse);
    });

    test('connexion atomique : si le profil est introuvable, la session n\'est pas à moitié établie', () async {
      final account = api.addAccount();
      api.failOnce['profile'] = const NetworkException();

      await expectLater(service.login(phone: account.phone, pin: '1234'), throwsA(isA<NetworkException>()));

      expect(await tokens.hasSession, isFalse);
      expect(ledger.meta('user_id'), isNull);
    });

    test('inscription : crée le compte puis ouvre la session', () async {
      final state = await service.completeSignUp(otpSessionToken: 'otp-+2290167000009', businessName: 'Chez Awa', pin: '4321');
      expect(state.profile.businessName, 'Chez Awa');
      expect(await tokens.hasSession, isTrue);
    });
  });

  group('restauration au lancement (hors ligne)', () {
    test('session ouverte : retrouve le profil en cache sans réseau', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');
      api.calls.clear();

      final state = await service.restore();

      expect(state, isA<SignedIn>());
      expect((state as SignedIn).profile.phone, account.phone);
      expect(api.calls, isEmpty);
    });

    test('rien d\'enregistré : déconnecté', () async {
      expect(await service.restore(), isA<SignedOut>());
    });

    test('jetons perdus mais données conservées : déconnecté avec le numéro à pré-remplir (session expirée)', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');
      await tokens.clear();

      final state = await service.restore() as SignedOut;

      expect(state.phone, account.phone);
      expect(state.reason, SignedOutReason.expired);
    });

    test('jetons sans profil en cache : le récupère, ou revient à déconnecté si impossible', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');
      ledger.deleteMeta('profile');
      expect(await service.restore(), isA<SignedIn>());

      ledger.deleteMeta('profile');
      api.failOnce['profile'] = const NetworkException();
      expect(await service.restore(), isA<SignedOut>());
    });
  });

  test('base réinitialisée puis session retrouvée par le réseau : la base est liée à ce compte (un autre compte l\'efface)', () async {
    final a = api.addAccount();
    final b = api.addAccount(phone: '+2290167000002', business: 'Boutique B');
    await service.login(phone: a.phone, pin: '1234');
    db.clearAllData(); // données locales réinitialisées, jetons conservés
    expect(await service.restore(), isA<SignedIn>());
    expect(ledger.meta('user_id'), a.id);

    repo.addCustomer(name: 'Client de A', phone: '+229 01 67 07 70 27');
    outbox.clear();
    await service.login(phone: b.phone, pin: '1234');
    expect(ledger.customers(), isEmpty, reason: 'les données de A ne doivent jamais passer chez B');
  });

  group('changement de compte sur le même appareil', () {
    test('la même personne qui se reconnecte (session expirée) retrouve ses données', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');
      repo.addCustomer(name: 'Aicha', phone: '+229 01 67 07 70 27');
      await tokens.clear(); // session expirée

      await service.login(phone: account.phone, pin: '1234');

      expect(ledger.customers(), hasLength(1));
      expect(outbox.count(), 1);
    });

    test('un autre commerçant : les données du précédent sont effacées', () async {
      final a = api.addAccount();
      final b = api.addAccount(phone: '+2290167000002', business: 'Boutique B');
      await service.login(phone: a.phone, pin: '1234');
      repo.addCustomer(name: 'Client de A', phone: '+229 01 67 07 70 27');
      outbox.clear(); // tout est déjà synchronisé

      await service.login(phone: b.phone, pin: '1234');

      expect(ledger.customers(), isEmpty);
      expect(ledger.meta('user_id'), b.id);
    });

    test('des saisies non envoyées du précédent compte ne sont JAMAIS perdues sans confirmation', () async {
      final a = api.addAccount();
      final b = api.addAccount(phone: '+2290167000002', business: 'Boutique B');
      await service.login(phone: a.phone, pin: '1234');
      repo.addCustomer(name: 'Saisie non envoyée', phone: '+229 01 67 07 70 27');

      await expectLater(
        service.login(phone: b.phone, pin: '1234'),
        throwsA(isA<UnsyncedDataException>().having((e) => e.count, 'count', 1)),
      );
      expect(ledger.customers(), hasLength(1)); // intactes
      expect(await tokens.hasSession, isFalse);

      await service.login(phone: b.phone, pin: '1234', discardUnsyncedFromOtherAccount: true);
      expect(ledger.customers(), isEmpty);
    });
  });

  group('déconnexion', () {
    test('refusée tant que des saisies ne sont pas envoyées ; rien n\'est touché', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');
      repo.addCustomer(name: 'Aicha', phone: '+229 01 67 07 70 27');

      final result = await service.logout();

      expect(result, isA<LogoutBlocked>().having((r) => r.unsyncedCount, 'count', 1));
      expect(await tokens.hasSession, isTrue);
      expect(ledger.customers(), hasLength(1));
    });

    test('en ligne : révoque la session, efface les jetons ET toutes les données locales', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');
      repo.addCustomer(name: 'Aicha', phone: '+229 01 67 07 70 27');
      outbox.clear();

      final result = await service.logout();

      expect(result, isA<LoggedOut>().having((r) => r.remoteRevoked, 'revoked', true));
      expect(api.calls, contains('logout'));
      expect(await tokens.hasSession, isFalse);
      expect(ledger.customers(), isEmpty);
      expect(ledger.meta('profile'), isNull);
      expect(secrets.values.containsKey(SecretKeys.pendingRevocation), isFalse);
    });

    test('forcée : perd volontairement les saisies non envoyées', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');
      repo.addCustomer(name: 'Aicha', phone: '+229 01 67 07 70 27');

      await service.logout(force: true);

      expect(ledger.customers(), isEmpty);
      expect(outbox.count(), 0);
    });

    test('hors ligne : déconnecte quand même mais mémorise la révocation à effectuer', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');
      final refresh = (await tokens.refreshToken)!;
      api.failOnce['logout'] = const NetworkException();

      final result = await service.logout();

      expect(result, isA<LoggedOut>().having((r) => r.remoteRevoked, 'revoked', false));
      expect(await tokens.hasSession, isFalse);
      expect(secrets.values[SecretKeys.pendingRevocation], refresh);
    });

    test('la révocation en attente aboutit au retour du réseau (rafraîchit puis déconnecte), puis disparaît', () async {
      secrets.values[SecretKeys.pendingRevocation] = 'refresh-oublie';
      revokeAdapter = ScriptedAdapter((r) => r.authorization == 'Bearer a2' ? ScriptedResponse(201, {}) : ScriptedResponse(401, {}));
      service = SessionService(
        api: api,
        tokens: tokens,
        secrets: secrets,
        db: db,
        clientFactory: (isolated) => ApiClient(
          baseUrl: 'http://api.test',
          tokens: isolated,
          dio: Dio()..httpClientAdapter = revokeAdapter,
          refreshDio: Dio()..httpClientAdapter = ScriptedAdapter((r) => ScriptedResponse(201, {'accessToken': 'a2', 'refreshToken': 'r2'})),
        ),
      );

      expect(await service.revokePendingSession(), isTrue);

      expect(secrets.values.containsKey(SecretKeys.pendingRevocation), isFalse);
      expect(revokeAdapter.requests.last.authorization, 'Bearer a2');
    });

    test('révocation toujours impossible (réseau) : conservée pour plus tard ; déjà révoquée (401) : abandonnée', () async {
      secrets.values[SecretKeys.pendingRevocation] = 'refresh-oublie';
      SessionService build(Handler onApi, Handler onRefresh) => SessionService(
            api: api,
            tokens: tokens,
            secrets: secrets,
            db: db,
            clientFactory: (isolated) => ApiClient(
              baseUrl: 'http://api.test',
              tokens: isolated,
              dio: Dio()..httpClientAdapter = ScriptedAdapter(onApi),
              refreshDio: Dio()..httpClientAdapter = ScriptedAdapter(onRefresh),
            ),
          );

      expect(await build((r) => throw timeoutError(), (r) => throw timeoutError()).revokePendingSession(), isFalse);
      expect(secrets.values.containsKey(SecretKeys.pendingRevocation), isTrue);

      expect(await build((r) => ScriptedResponse(401, {}), (r) => ScriptedResponse(401, {})).revokePendingSession(), isTrue);
      expect(secrets.values.containsKey(SecretKeys.pendingRevocation), isFalse);
    });
  });

  group('PIN et profil', () {
    test('changer le PIN : l\'appareil se reconnecte aussitôt avec le nouveau (la session précédente est révoquée)', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');
      final before = await tokens.accessToken;

      await service.changePin(currentPin: '1234', newPin: '5678');

      expect(account.pin, '5678');
      expect(await tokens.accessToken, isNot(before));
      expect(await tokens.hasSession, isTrue);
      expect(api.calls, containsAllInOrder(['changePin', 'login']));
    });

    test('mauvais PIN actuel : rien ne change', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');
      final before = await tokens.accessToken;

      await expectLater(service.changePin(currentPin: '0000', newPin: '5678'), throwsA(isA<RejectedException>()));

      expect(account.pin, '1234');
      expect(await tokens.accessToken, before);
    });

    test('renommer la boutique met à jour le cache hors ligne', () async {
      final account = api.addAccount();
      await service.login(phone: account.phone, pin: '1234');

      await service.updateBusinessName('Nouveau nom');

      expect((await service.restore() as SignedIn).profile.businessName, 'Nouveau nom');
    });
  });

  test('profil mis en cache : plan Premium et date d\'expiration conservés', () async {
    final account = api.addAccount();
    account.plan = Plan.premium;
    await service.login(phone: account.phone, pin: '1234');

    final restored = await service.restore() as SignedIn;
    expect(restored.profile.isPremium, isTrue);
  });
}
