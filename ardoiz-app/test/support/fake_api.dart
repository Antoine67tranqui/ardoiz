import 'package:ardoiz/data/remote/api_exceptions.dart';
import 'package:ardoiz/data/remote/backend_api.dart';

class FakeAccount {
  FakeAccount({required this.id, required this.phone, required this.pin, required this.businessName, this.plan = Plan.free});

  final String id;
  final String phone;
  String pin;
  String businessName;
  Plan plan;
}

/// Faux backend d'authentification pour les tests (une seule session à la fois).
/// Les méthodes hors authentification lèvent [UnimplementedError] : les tests
/// d'écrans utilisent des doublures ciblées (mocktail).
class FakeBackendApi implements BackendApi {
  final Map<String, FakeAccount> accounts = <String, FakeAccount>{};
  final List<String> calls = <String>[];

  /// Panne programmable : la prochaine opération nommée échoue avec cette erreur.
  final Map<String, ApiException> failOnce = <String, ApiException>{};

  String? signedInPhone;
  int _tokenCounter = 0;
  static const String validOtp = '123456';

  void _enter(String name) {
    calls.add(name);
    final error = failOnce.remove(name);
    if (error != null) throw error;
  }

  FakeAccount addAccount({String phone = '+2290167000001', String pin = '1234', String business = 'Boutique A'}) {
    final account = FakeAccount(id: 'user-${accounts.length + 1}', phone: phone, pin: pin, businessName: business);
    accounts[phone] = account;
    return account;
  }

  SessionTokens _issue(FakeAccount account) {
    signedInPhone = account.phone;
    _tokenCounter++;
    return SessionTokens(accessToken: 'access-${account.id}-$_tokenCounter', refreshToken: 'refresh-${account.id}-$_tokenCounter');
  }

  @override
  Future<OtpRequestResult> requestOtp(String phone) async {
    _enter('requestOtp');
    return const OtpRequestResult(devCode: validOtp);
  }

  @override
  Future<OtpVerification> verifyOtp(String phone, String code) async {
    _enter('verifyOtp');
    if (code != validOtp) throw const RejectedException(400, 'Code OTP invalide');
    return OtpVerification(otpSessionToken: 'otp-$phone', isNewUser: !accounts.containsKey(phone));
  }

  @override
  Future<SessionTokens> setupPin({required String otpSessionToken, required String businessName, required String pin}) async {
    _enter('setupPin');
    final phone = otpSessionToken.replaceFirst('otp-', '');
    final account = accounts[phone] ?? addAccount(phone: phone, pin: pin, business: businessName);
    account
      ..pin = pin
      ..businessName = businessName;
    return _issue(account);
  }

  @override
  Future<SessionTokens> login({required String phone, required String pin}) async {
    _enter('login');
    final account = accounts[phone];
    if (account == null || account.pin != pin) throw const RejectedException(401, 'Identifiants invalides');
    return _issue(account);
  }

  @override
  Future<void> logout() async {
    _enter('logout');
    signedInPhone = null;
  }

  @override
  Future<void> deleteAccount({required String pin}) async {
    _enter('deleteAccount');
    final account = accounts[signedInPhone];
    if (account == null) throw const UnauthorizedException();
    if (account.pin != pin) throw const RejectedException(400, 'PIN actuel incorrect');
    accounts.remove(account.phone);
    signedInPhone = null;
  }

  @override
  Future<void> changePin({required String currentPin, required String newPin}) async {
    _enter('changePin');
    final account = accounts[signedInPhone]!;
    if (account.pin != currentPin) throw const RejectedException(400, 'PIN actuel incorrect');
    account.pin = newPin;
    signedInPhone = null; // toutes les sessions sont révoquées
  }

  @override
  Future<Profile> profile() async {
    _enter('profile');
    final account = accounts[signedInPhone] ?? (throw const UnauthorizedException());
    return Profile(id: account.id, phone: account.phone, businessName: account.businessName, plan: account.plan);
  }

  @override
  Future<Profile> updateBusinessName(String businessName) async {
    _enter('updateBusinessName');
    accounts[signedInPhone]!.businessName = businessName;
    return profile();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName} non simulé');
}
