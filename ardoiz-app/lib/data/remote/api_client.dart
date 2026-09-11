import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants.dart';

/// Client HTTP unique de l'app : injecte automatiquement le token JWT et
/// tente un rafraichissement transparent en cas de 401.
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: SecureStorageKeys.accessToken);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final refreshed = await _tryRefreshToken();
          if (refreshed) {
            final clone = await _retry(error.requestOptions);
            return handler.resolve(clone);
          }
        }
        handler.next(error);
      },
    ));
  }

  static final ApiClient instance = ApiClient._internal();
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  Dio get dio => _dio;

  Future<bool> _tryRefreshToken() async {
    final refreshToken = await _storage.read(key: SecureStorageKeys.refreshToken);
    if (refreshToken == null) return false;

    try {
      final response = await Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
          .post('/auth/refresh', data: {'refreshToken': refreshToken});
      await _storage.write(
        key: SecureStorageKeys.accessToken,
        value: response.data['accessToken'] as String,
      );
      await _storage.write(
        key: SecureStorageKeys.refreshToken,
        value: response.data['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) async {
    final token = await _storage.read(key: SecureStorageKeys.accessToken);
    final options = Options(method: requestOptions.method, headers: {
      ...requestOptions.headers,
      'Authorization': 'Bearer $token',
    });
    return _dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }
}
