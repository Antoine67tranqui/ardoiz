import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Requête reçue par le faux serveur HTTP.
class RecordedRequest {
  RecordedRequest(this.method, this.path, this.headers, this.body);

  final String method;
  final String path;
  final Map<String, Object?> headers;
  final Object? body;

  String? get authorization => headers['Authorization'] as String?;
}

typedef Handler = FutureOr<ScriptedResponse> Function(RecordedRequest request);

class ScriptedResponse {
  ScriptedResponse(this.status, [this.body]);

  final int status;
  final Object? body;
}

/// Adaptateur Dio pilotable : répond selon un scénario, enregistre les appels.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.handler);

  final Handler handler;
  final List<RecordedRequest> requests = <RecordedRequest>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final recorded = RecordedRequest(options.method, options.path, Map<String, Object?>.of(options.headers), options.data);
    requests.add(recorded);
    final response = await handler(recorded);
    final bytes = utf8.encode(jsonEncode(response.body));
    return ResponseBody.fromBytes(
      bytes,
      response.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioException timeoutError() => DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.connectionTimeout,
    );
