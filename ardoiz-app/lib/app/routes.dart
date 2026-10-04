/// Adresses de tous les écrans (un seul endroit : pas de chaînes dispersées).
class Routes {
  const Routes._();

  // Accès
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String signupCode = '/signup/code';
  static const String signupPin = '/signup/pin';

  // Onglets
  static const String customers = '/home/customers';
  static const String dashboard = '/home/dashboard';
  static const String settings = '/home/settings';

  // Clients et dettes
  static const String customerNew = '/customers/new';
  static String customer(String id) => '/customers/$id';
  static String customerEdit(String id) => '/customers/$id/edit';
  static String debtNew(String customerId) => '/customers/$customerId/debts/new';
  static String debt(String id) => '/debts/$id';
  static String debtEdit(String id) => '/debts/$id/edit';

  // Réglages
  static const String subscription = '/settings/subscription';
  static const String reminderRules = '/settings/reminders';
  static const String changePin = '/settings/pin';
  static const String businessName = '/settings/business';
  static const String syncIssues = '/settings/sync';

  static const Set<String> publicPaths = <String>{welcome, login, signup, signupCode, signupPin};
}
