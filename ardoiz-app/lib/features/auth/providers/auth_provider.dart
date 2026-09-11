import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/auth_repository.dart';

final authRepositoryProvider = Provider((ref) => AuthRepository());

final sessionProvider = FutureProvider<bool>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.hasActiveSession();
});

final currentUserIdProvider = FutureProvider<String?>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.currentUserId();
});

final currentBusinessNameProvider = FutureProvider<String?>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.currentBusinessName();
});

/// Etat transitoire du flux d'inscription : conserve le numero de
/// telephone et le jeton de session OTP entre les ecrans du parcours.
class OnboardingState {
  final String? phone;
  final String? otpSessionToken;

  const OnboardingState({this.phone, this.otpSessionToken});

  OnboardingState copyWith({String? phone, String? otpSessionToken}) =>
      OnboardingState(
        phone: phone ?? this.phone,
        otpSessionToken: otpSessionToken ?? this.otpSessionToken,
      );
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier() : super(const OnboardingState());

  void setPhone(String phone) => state = state.copyWith(phone: phone);

  void setOtpSessionToken(String token) =>
      state = state.copyWith(otpSessionToken: token);
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>(
  (ref) => OnboardingNotifier(),
);
