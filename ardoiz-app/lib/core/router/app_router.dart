import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/phone_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/pin_setup_screen.dart';
import '../../features/auth/screens/login_pin_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/customer_detail/screens/customer_detail_screen.dart';
import '../../features/add_debt/screens/add_debt_screen.dart';
import '../../features/payment/screens/payment_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/phone', builder: (context, state) => const PhoneScreen()),
      GoRoute(path: '/otp', builder: (context, state) => const OtpScreen()),
      GoRoute(
        path: '/pin-setup',
        builder: (context, state) => const PinSetupScreen(),
      ),
      GoRoute(
        path: '/login-pin',
        builder: (context, state) => LoginPinScreen(
          phone: state.uri.queryParameters['phone'] ?? '',
        ),
      ),
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
      GoRoute(
        path: '/customers/:id',
        builder: (context, state) => CustomerDetailScreen(
          customerId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/customers/:id/add-debt',
        builder: (context, state) => AddDebtScreen(
          customerId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/debts/:debtId/pay',
        builder: (context, state) => PaymentScreen(
          debtId: state.pathParameters['debtId']!,
          customerId: state.uri.queryParameters['customerId'] ?? '',
          amount: double.tryParse(state.uri.queryParameters['amount'] ?? '') ?? 0,
        ),
      ),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    ],
  );
});
