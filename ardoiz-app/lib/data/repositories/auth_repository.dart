import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants.dart';
import '../../core/jwt_utils.dart';
import '../remote/api_client.dart';

class AuthRepository {
  final _dio = ApiClient.instance.dio;
  final _storage = const FlutterSecureStorage();

  Future<void> requestOtp(String phone) async {
    await _dio.post('/auth/otp/request', data: {'phone': phone});
  }

  /// Retourne le jeton de session OTP et si le numero correspond a un
  /// nouveau commercant (necessite alors une creation de PIN).
  Future<({String otpSessionToken, bool isNewUser})> verifyOtp(
    String phone,
    String code,
  ) async {
    final response = await _dio.post('/auth/otp/verify', data: {
      'phone': phone,
      'code': code,
    });
    return (
      otpSessionToken: response.data['otpSessionToken'] as String,
      isNewUser: response.data['isNewUser'] as bool,
    );
  }

  Future<void> setupPin({
    required String otpSessionToken,
    required String businessName,
    required String pin,
  }) async {
    final response = await _dio.post('/auth/pin/setup', data: {
      'otpSessionToken': otpSessionToken,
      'businessName': businessName,
      'pin': pin,
    });
    await _persistTokens(response.data, businessName: businessName);
  }

  Future<void> login({required String phone, required String pin}) async {
    final response = await _dio.post('/auth/login', data: {
      'phone': phone,
      'pin': pin,
    });
    await _persistTokens(response.data);
  }

  Future<bool> hasActiveSession() async {
    return await _storage.read(key: SecureStorageKeys.accessToken) != null;
  }

  Future<String?> currentUserId() async {
    return _storage.read(key: SecureStorageKeys.userId);
  }

  Future<String?> currentBusinessName() async {
    return _storage.read(key: SecureStorageKeys.businessName);
  }

  Future<void> logout() async {
    await _storage.deleteAll();
  }

  Future<void> _persistTokens(
    Map<String, dynamic> data, {
    String? businessName,
  }) async {
    final accessToken = data['accessToken'] as String;
    await _storage.write(key: SecureStorageKeys.accessToken, value: accessToken);
    await _storage.write(
      key: SecureStorageKeys.refreshToken,
      value: data['refreshToken'] as String,
    );

    final payload = decodeJwtPayload(accessToken);
    final userId = payload['sub'] as String?;
    if (userId != null) {
      await _storage.write(key: SecureStorageKeys.userId, value: userId);
    }
    if (businessName != null) {
      await _storage.write(
        key: SecureStorageKeys.businessName,
        value: businessName,
      );
    }
  }
}
