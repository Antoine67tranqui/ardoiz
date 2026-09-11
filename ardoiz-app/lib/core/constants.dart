class ApiConfig {
  // A remplacer par l'URL de l'API deployee (ex: https://api.ardoiz.com/api/v1)
  static const baseUrl = String.fromEnvironment(
    'ARDOIZ_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );
}

class SecureStorageKeys {
  static const accessToken = 'ardoiz_access_token';
  static const refreshToken = 'ardoiz_refresh_token';
  static const userId = 'ardoiz_user_id';
  static const businessName = 'ardoiz_business_name';
}
