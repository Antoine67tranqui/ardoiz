import 'dart:async';

import 'package:ardoiz/data/local/secret_store.dart';
import 'package:ardoiz/data/remote/api_client.dart';
import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/remote/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  late InMemorySecretStore secrets;
  late TokenStore tokens;
  late ScriptedAdapter api;
  late ScriptedAdapter refreshApi;
  late ApiClient client;
  late int expiredCount;

  Future<void> signedIn({String access = 'access-1', String refresh = 'refresh-1'}) =>
      tokens.save(accessToken: access, refreshToken: refresh);

  void build({required Handler onApi, Handler? onRefresh}) {
    api = ScriptedAdapter(onApi);
    refreshApi = ScriptedAdapter(onRefresh ?? (_) => ScriptedResponse(500, {}));
    client = ApiClient(
      baseUrl: 'http://api.test/v1',
      tokens: tokens,
      dio: Dio()..httpClientAdapter = api,
      refreshDio: Dio()..httpClientAdapter = refreshApi,
      onSessionExpired: () => expiredCount++,
    );
  }

  setUp(() {
    secrets = InMemorySecretStore();
    tokens = TokenStore(secrets);
    expiredCount = 0;
  });

  group('requêtes', () {
    test('ajoute le jeton d\'accès aux routes protégées, jamais aux routes publiques', () async {
      await signedIn();
      build(onApi: (r) => ScriptedResponse(200, {'ok': true}));

      await client.send('GET', '/customers');
      await client.send('POST', '/auth/login', body: {'phone': 'x'});

      expect(api.requests[0].authorization, 'Bearer access-1');
      expect(api.requests[1].authorization, isNull);
    });

    test('renvoie le corps décodé pour une réponse 2xx', () async {
      build(onApi: (r) => ScriptedResponse(201, {'id': 'abc'}));
      expect(await client.send('POST', '/customers', body: {'name': 'A'}), {'id': 'abc'});
      expect(api.requests.single.body, {'name': 'A'});
    });
  });

  group('classement des erreurs', () {
    test('délai dépassé / réseau coupé : NetworkException', () async {
      build(onApi: (r) => throw timeoutError());
      expect(client.send('GET', '/customers'), throwsA(isA<NetworkException>()));
    });

    test('503 avec code FEATURE_UNAVAILABLE : le message du serveur est conservé et le code exposé', () async {
      await signedIn();
      build(
        onApi: (r) => ScriptedResponse(503, {
          'message': {'code': 'FEATURE_UNAVAILABLE', 'message': 'Le paiement Mobile Money n\'est pas encore disponible.'},
        }),
      );
      await expectLater(
        client.send('POST', '/payments/momo-request', body: {'debtId': 'd'}),
        throwsA(isA<ServerException>()
            .having((e) => e.isFeatureUnavailable, 'indisponible', isTrue)
            .having((e) => e.message, 'message', 'Le paiement Mobile Money n\'est pas encore disponible.')),
      );
    });

    test('5xx, 429, 408 : ServerException (à réessayer)', () async {
      for (final status in [500, 502, 503, 429, 408]) {
        build(onApi: (r) => ScriptedResponse(status, {'message': 'oups'}));
        await expectLater(
          client.send('GET', '/customers'),
          throwsA(isA<ServerException>().having((e) => e.statusCode, 'status', status)),
          reason: '$status',
        );
      }
    });

    test('4xx : RejectedException avec le code métier et le message du backend', () async {
      build(onApi: (r) => ScriptedResponse(403, {
            'statusCode': 403,
            'message': {'code': 'FREE_PLAN_LIMIT_REACHED', 'message': 'Le plan gratuit est limité.'},
          }));
      await expectLater(
        client.send('POST', '/customers', body: {}),
        throwsA(isA<RejectedException>()
            .having((e) => e.statusCode, 'status', 403)
            .having((e) => e.code, 'code', 'FREE_PLAN_LIMIT_REACHED')
            .having((e) => e.message, 'message', 'Le plan gratuit est limité.')),
      );
    });

    test('erreurs de validation : messages concaténés ; message texte simple ; corps inattendu', () async {
      build(onApi: (r) => ScriptedResponse(400, {'message': {'message': ['Nom trop court', 'Téléphone invalide'], 'error': 'Bad Request'}}));
      await expectLater(client.send('POST', '/customers'), throwsA(isA<RejectedException>().having((e) => e.message, 'm', 'Nom trop court Téléphone invalide')));

      build(onApi: (r) => ScriptedResponse(400, {'message': 'Code OTP invalide'}));
      await expectLater(client.send('POST', '/auth/otp/verify'), throwsA(isA<RejectedException>().having((e) => e.message, 'm', 'Code OTP invalide')));

      build(onApi: (r) => ScriptedResponse(404, '<html>Not found</html>'));
      await expectLater(client.send('GET', '/x'), throwsA(isA<RejectedException>().having((e) => e.isNotFound, 'notFound', true)));
    });

    test('401 sur une route publique (mauvais PIN, compte verrouillé) : refus avec le message du serveur, sans rafraîchissement', () async {
      await signedIn();
      build(onApi: (r) => ScriptedResponse(401, {'statusCode': 401, 'message': 'Trop de tentatives echouees. Reessayez dans 14 minute(s).'}));

      await expectLater(
        client.send('POST', '/auth/login', body: {}),
        throwsA(isA<RejectedException>()
            .having((e) => e.statusCode, 'status', 401)
            .having((e) => e.message, 'message', contains('Trop de tentatives'))),
      );
      expect(refreshApi.requests, isEmpty);
      expect(expiredCount, 0);
    });
  });

  group('renouvellement du jeton', () {
    test('un 401 déclenche un rafraîchissement puis rejoue la requête UNE fois avec le nouveau jeton', () async {
      await signedIn();
      build(
        onApi: (r) => r.authorization == 'Bearer access-2' ? ScriptedResponse(200, {'ok': true}) : ScriptedResponse(401, {}),
        onRefresh: (r) => ScriptedResponse(201, {'accessToken': 'access-2', 'refreshToken': 'refresh-2'}),
      );

      expect(await client.send('GET', '/customers'), {'ok': true});

      expect(api.requests.map((r) => r.authorization), ['Bearer access-1', 'Bearer access-2']);
      expect(refreshApi.requests.single.body, {'refreshToken': 'refresh-1'});
      expect(await tokens.accessToken, 'access-2');
      expect(await tokens.refreshToken, 'refresh-2');
      expect(secrets.values[SecretKeys.refreshToken], 'refresh-2');
    });

    test('pas de boucle infinie : si la requête rejouée renvoie encore 401, l\'erreur remonte', () async {
      await signedIn();
      build(
        onApi: (r) => ScriptedResponse(401, {}),
        onRefresh: (r) => ScriptedResponse(201, {'accessToken': 'access-2', 'refreshToken': 'refresh-2'}),
      );

      await expectLater(client.send('GET', '/customers'), throwsA(isA<UnauthorizedException>()));
      expect(api.requests, hasLength(2));
      expect(refreshApi.requests, hasLength(1));
    });

    test('des requêtes simultanées en 401 partagent UN SEUL rafraîchissement', () async {
      await signedIn();
      final refreshGate = Completer<void>();
      build(
        onApi: (r) => r.authorization == 'Bearer access-2' ? ScriptedResponse(200, {'ok': true}) : ScriptedResponse(401, {}),
        onRefresh: (r) async {
          await refreshGate.future;
          return ScriptedResponse(201, {'accessToken': 'access-2', 'refreshToken': 'refresh-2'});
        },
      );

      final calls = Future.wait([client.send('GET', '/a'), client.send('GET', '/b'), client.send('GET', '/c')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      refreshGate.complete();

      expect(await calls, everyElement({'ok': true}));
      expect(refreshApi.requests, hasLength(1));
    });

    test('jeton de rafraîchissement refusé (révoqué) : session expirée, jetons effacés, signal émis', () async {
      await signedIn();
      build(
        onApi: (r) => ScriptedResponse(401, {}),
        onRefresh: (r) => ScriptedResponse(401, {'message': 'Jeton de rafraichissement invalide'}),
      );

      await expectLater(client.send('GET', '/customers'), throwsA(isA<UnauthorizedException>()));

      expect(expiredCount, 1);
      expect(await tokens.hasSession, isFalse);
      expect(secrets.values.containsKey(SecretKeys.accessToken), isFalse);
    });

    test('rafraîchissement impossible faute de réseau : la session est CONSERVÉE (pas de déconnexion)', () async {
      await signedIn();
      build(
        onApi: (r) => ScriptedResponse(401, {}),
        onRefresh: (r) => throw timeoutError(),
      );

      await expectLater(client.send('GET', '/customers'), throwsA(isA<UnauthorizedException>()));

      expect(expiredCount, 0);
      expect(await tokens.hasSession, isTrue);
    });

    test('un rafraîchissement en erreur serveur (5xx) ne déconnecte pas non plus', () async {
      await signedIn();
      build(onApi: (r) => ScriptedResponse(401, {}), onRefresh: (r) => ScriptedResponse(503, {}));

      await expectLater(client.send('GET', '/customers'), throwsA(isA<UnauthorizedException>()));
      expect(expiredCount, 0);
      expect(await tokens.hasSession, isTrue);
    });

    test('sans aucun jeton de rafraîchissement : session expirée', () async {
      build(onApi: (r) => ScriptedResponse(401, {}));

      await expectLater(client.send('GET', '/customers'), throwsA(isA<UnauthorizedException>()));
      expect(expiredCount, 1);
    });
  });
}
