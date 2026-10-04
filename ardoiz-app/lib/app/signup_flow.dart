import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Données transmises entre les écrans d'inscription (numéro, code, session OTP).
class SignupFlow {
  const SignupFlow({this.phone, this.devCode, this.otpSessionToken, this.isNewUser = true});

  final String? phone;

  /// Code renvoyé par un serveur de développement (jamais en production).
  final String? devCode;
  final String? otpSessionToken;
  final bool isNewUser;

  bool get hasPhone => phone != null;
  bool get isVerified => otpSessionToken != null;
}

class SignupFlowNotifier extends Notifier<SignupFlow> {
  @override
  SignupFlow build() => const SignupFlow();

  void codeSent({required String phone, String? devCode}) => state = SignupFlow(phone: phone, devCode: devCode);

  void resent({String? devCode}) => state = SignupFlow(phone: state.phone, devCode: devCode);

  void verified({required String otpSessionToken, required bool isNewUser}) =>
      state = SignupFlow(phone: state.phone, otpSessionToken: otpSessionToken, isNewUser: isNewUser);

  void reset() => state = const SignupFlow();
}

final NotifierProvider<SignupFlowNotifier, SignupFlow> signupFlowProvider =
    NotifierProvider<SignupFlowNotifier, SignupFlow>(SignupFlowNotifier.new);
