import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'token_store.dart';

/// Routes publiques : jamais de jeton, jamais de rafraîchissement sur 401.
const Set<String> _publicPaths = <String>{
  '/auth/otp/request',
  '/auth/otp/verify',
  '/auth/pin/setup',
  '/auth/login',
  '/auth/refresh',
};

/// Client HTTP unique de l'app : ajoute le jeton, le renouvelle de façon
/// transparente sur 401 (un seul rafraîchissement à la fois, une seule
/// relance par requête : pas de boucle), et traduit toute erreur en
/// [ApiException].
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this._tokens,
    this.onSessionExpired,
    Dio? dio,
    Dio? refreshDio,
    Duration timeout = const Duration(seconds: 15),
  })  : dio = dio ?? Dio(),
        _refreshDio = refreshDio ?? Dio() {
    this.dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = timeout
      ..sendTimeout = timeout
      ..receiveTimeout = timeout
      // On traite nous-mêmes tous les codes HTTP.
      ..validateStatus = (_) => true;
    _refreshDio.options
      ..baseUrl = baseUrl
      ..connectTimeout = timeout
      ..receiveTimeout = timeout
      ..validateStatus = (_) => true;
  }

  final String baseUrl;
  final Dio dio;
  final Dio _refreshDio;
  final TokenStore _tokens;

  /// Appelé quand le serveur refuse définitivement la session (jeton de
  /// rafraîchissement invalide ou révoqué).
  final void Function()? onSessionExpired;

  Future<void>? _refreshing;

  /// Envoie une requête et renvoie le corps JSON décodé ; lève [ApiException].
  Future<Object?> send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    ResponseType responseType = ResponseType.json,
  }) async {
    final response = await _execute(method, path, body: body, query: query, responseType: responseType, retried: false);
    return response.data;
  }

  Future<Response<Object?>> _execute(
    String method,
    String path, {
    required bool retried,
    Object? body,
    Map<String, Object?>? query,
    ResponseType responseType = ResponseType.json,
  }) async {
    final isPublic = _publicPaths.contains(path);
    final token = isPublic ? null : await _tokens.accessToken;
    final Response<Object?> response;
    try {
      response = await dio.request<Object?>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          responseType: responseType,
          headers: <String, Object?>{if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
    } on DioException catch (error) {
      throw _network(error);
    } on SocketException catch (error) {
      throw NetworkException(error.message);
    }

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return response;

    if (status == 401 && !isPublic && !retried) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        return _execute(method, path, body: body, query: query, responseType: responseType, retried: true);
      }
      throw const UnauthorizedException();
    }
    // 401 persistant sur une route protégée : la session est bien invalide.
    if (status == 401 && !isPublic) throw const UnauthorizedException();
    // 401 sur une route publique : identifiants refusés (mauvais PIN, compte
    // verrouillé), avec le message du serveur. Ce n'est pas une session expirée.
    throw _fromResponse(status, response.data);
  }

  /// Un seul rafraîchissement à la fois : des requêtes simultanées en 401
  /// partagent le même appel (sinon elles se disputeraient les jetons).
  Future<bool> _refreshOnce() async {
    final pending = _refreshing;
    if (pending != null) {
      await pending;
      return await _tokens.accessToken != null;
    }
    final completer = Completer<void>();
    _refreshing = completer.future;
    try {
      return await _refresh();
    } finally {
      completer.complete();
      _refreshing = null;
    }
  }

  Future<bool> _refresh() async {
    final refreshToken = await _tokens.refreshToken;
    if (refreshToken == null) {
      onSessionExpired?.call();
      return false;
    }
    try {
      final response = await _refreshDio.post<Object?>('/auth/refresh', data: <String, Object?>{'refreshToken': refreshToken});
      final status = response.statusCode ?? 0;
      final data = response.data;
      if (status >= 200 && status < 300 && data is Map && data['accessToken'] is String && data['refreshToken'] is String) {
        await _tokens.save(accessToken: data['accessToken']! as String, refreshToken: data['refreshToken']! as String);
        return true;
      }
      if (status == 401 || status == 400) {
        // Jeton révoqué (déconnexion, changement de PIN) ou invalide.
        await _tokens.clear();
        onSessionExpired?.call();
      }
      return false;
    } on DioException {
      // Réseau indisponible : la session reste valable, on réessaiera.
      return false;
    }
  }

  static NetworkException _network(DioException error) => switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          const NetworkException('Le serveur met trop de temps à répondre.'),
        _ => const NetworkException(),
      };

  static ApiException _fromResponse(int status, Object? body) {
    String message = 'Erreur inattendue ($status).';
    String? code;
    if (body is Map) {
      final raw = body['message'];
      if (raw is String) {
        message = raw;
      } else if (raw is Map) {
        code = raw['code'] as String?;
        final inner = raw['message'];
        if (inner is String) {
          message = inner;
        } else if (inner is List) {
          message = inner.join(' ');
        }
      }
    }
    if (status >= 500 || status == 429 || status == 408 || status == 425) {
      return ServerException(status, message);
    }
    return RejectedException(status, message, code: code);
  }
}
