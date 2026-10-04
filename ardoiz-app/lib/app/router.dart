import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/screens/auth/login_screen.dart';
import '../ui/screens/auth/otp_screen.dart';
import '../ui/screens/auth/pin_setup_screen.dart';
import '../ui/screens/auth/signup_phone_screen.dart';
import '../ui/screens/auth/welcome_screen.dart';
import '../ui/screens/customers/customer_detail_screen.dart';
import '../ui/screens/customers/customer_form_screen.dart';
import '../ui/screens/customers/customers_screen.dart';
import '../ui/screens/dashboard/dashboard_screen.dart';
import '../ui/screens/debts/debt_detail_screen.dart';
import '../ui/screens/debts/debt_form_screen.dart';
import '../ui/screens/home_shell.dart';
import '../ui/screens/settings/business_name_screen.dart';
import '../ui/screens/settings/change_pin_screen.dart';
import '../ui/screens/settings/reminder_rules_screen.dart';
import '../ui/screens/settings/settings_screen.dart';
import '../ui/screens/settings/subscription_screen.dart';
import '../ui/screens/settings/sync_issues_screen.dart';
import '../ui/widgets/common.dart';
import 'providers.dart';
import 'routes.dart';
import 'session_service.dart';

/// Où envoyer l'utilisateur selon sa session (null : il est au bon endroit).
String? redirectFor(SessionState session, String location) {
  final isPublic = Routes.publicPaths.contains(location);
  switch (session) {
    case SignedIn():
      return isPublic || location == '/' ? Routes.customers : null;
    case SignedOut(:final reason, :final phone):
      if (isPublic) return null;
      // Session expirée : retour direct à la saisie du PIN, numéro déjà rempli.
      return reason == SignedOutReason.expired && phone != null ? Routes.login : Routes.welcome;
  }
}

/// Routeur de l'application. Chaque changement de session réévalue les redirections.
GoRouter buildRouter(Ref ref, {String? initialLocation}) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<SessionState>(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: initialLocation ?? '/',
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(ref.read(sessionProvider), state.uri.path),
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: EmptyState(
        icon: Icons.explore_off_outlined,
        title: 'Page introuvable',
        message: 'Cette page n\'existe pas.',
        action: BusyButton(label: 'Retour à l\'accueil', onPressed: () => context.go(Routes.customers)),
      ),
    ),
    routes: <RouteBase>[
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.signup, builder: (_, _) => const SignupPhoneScreen()),
      GoRoute(path: Routes.signupCode, builder: (_, _) => const OtpScreen()),
      GoRoute(path: Routes.signupPin, builder: (_, _) => const PinSetupScreen()),
      ShellRoute(
        builder: (context, state, child) => HomeShell(location: state.uri.path, child: child),
        routes: <RouteBase>[
          GoRoute(path: Routes.customers, pageBuilder: (_, _) => const NoTransitionPage<void>(child: CustomersScreen())),
          GoRoute(path: Routes.dashboard, pageBuilder: (_, _) => const NoTransitionPage<void>(child: DashboardScreen())),
          GoRoute(path: Routes.settings, pageBuilder: (_, _) => const NoTransitionPage<void>(child: SettingsScreen())),
        ],
      ),
      // « new » avant « :id » : sinon « new » serait lu comme un identifiant.
      GoRoute(path: Routes.customerNew, builder: (_, _) => const CustomerFormScreen()),
      GoRoute(path: '/customers/:id', builder: (_, s) => CustomerDetailScreen(customerId: s.pathParameters['id']!)),
      GoRoute(path: '/customers/:id/edit', builder: (_, s) => CustomerFormScreen(customerId: s.pathParameters['id'])),
      GoRoute(path: '/customers/:id/debts/new', builder: (_, s) => DebtFormScreen(customerId: s.pathParameters['id'])),
      GoRoute(path: '/debts/:id', builder: (_, s) => DebtDetailScreen(debtId: s.pathParameters['id']!)),
      GoRoute(path: '/debts/:id/edit', builder: (_, s) => DebtFormScreen(debtId: s.pathParameters['id'])),
      GoRoute(path: Routes.subscription, builder: (_, _) => const SubscriptionScreen()),
      GoRoute(path: Routes.reminderRules, builder: (_, _) => const ReminderRulesScreen()),
      GoRoute(path: Routes.changePin, builder: (_, _) => const ChangePinScreen()),
      GoRoute(path: Routes.businessName, builder: (_, _) => const BusinessNameScreen()),
      GoRoute(path: Routes.syncIssues, builder: (_, _) => const SyncIssuesScreen()),
    ],
  );
}

final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter(ref);
  ref.onDispose(router.dispose);
  return router;
});
