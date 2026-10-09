import 'package:dio/dio.dart';

import '../../core/money.dart';
import '../../domain/dashboard.dart';
import '../../domain/treasury.dart';
import 'api_client.dart';
import 'api_exceptions.dart';

enum Plan { free, premium }

class Profile {
  const Profile({
    required this.id,
    required this.phone,
    required this.businessName,
    required this.plan,
    this.planExpiresAt,
    this.termsAccepted = true,
    this.termsVersion,
  });

  final String id;
  final String phone;
  final String businessName;
  final Plan plan;
  final DateTime? planExpiresAt;

  /// Faux quand une nouvelle version des conditions attend l'acceptation de l'utilisateur.
  final bool termsAccepted;

  /// Version des conditions en vigueur sur le serveur.
  final String? termsVersion;

  bool get isPremium => plan == Plan.premium;

  /// Premium encore valide à [now] (l'expiration est vérifiée aussi hors ligne :
  /// le profil en cache ne doit pas rester Premium indéfiniment).
  bool isPremiumAt(DateTime now) => plan == Plan.premium && (planExpiresAt == null || planExpiresAt!.isAfter(now));
}

class SubscriptionStatus {
  const SubscriptionStatus({
    required this.plan,
    required this.customerCount,
    required this.monthlyPrice,
    this.planExpiresAt,
    this.customerLimit,
    this.paymentsAvailable = true,
  });

  final Plan plan;
  final DateTime? planExpiresAt;
  final int customerCount;

  /// Null = clients illimités (Premium).
  final int? customerLimit;
  final Money monthlyPrice;

  /// Faux tant que le paiement Mobile Money n'est pas ouvert sur ce serveur.
  final bool paymentsAvailable;
}

class UpgradeResult {
  const UpgradeResult({required this.activated, required this.simulated, required this.message, this.reference});

  final bool activated;
  final bool simulated;
  final String message;
  final String? reference;
}

/// Un événement du journal d'activité du compte.
class ActivityEvent {
  const ActivityEvent({required this.action, required this.at});

  final String action;
  final DateTime at;

  /// Libellé lisible (les codes d'action du serveur ne sont jamais affichés tels quels).
  String get label => switch (action) {
        'ACCOUNT_CREATED' => 'Compte créé',
        'LOGIN' => 'Connexion',
        'PIN_LOCKED' => 'Compte verrouillé après plusieurs codes PIN erronés',
        'PIN_CHANGED' => 'Code PIN modifié',
        'LOGOUT' => 'Déconnexion',
        'CONSENT_ACCEPTED' => 'Conditions et confidentialité acceptées',
        'DATA_EXPORT' => 'Export de vos données',
        'CUSTOMER_EXPORT' => 'Export des données d\'un client ou fournisseur',
        _ => 'Activité du compte',
      };
}

class OtpRequestResult {
  const OtpRequestResult({this.devCode});

  /// Renseigné uniquement par un serveur de développement sans fournisseur SMS.
  final String? devCode;
}

class OtpVerification {
  const OtpVerification({required this.otpSessionToken, required this.isNewUser});

  final String otpSessionToken;
  final bool isNewUser;
}

class SessionTokens {
  const SessionTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

enum ReminderChannel {
  sms('SMS', 'SMS'),
  whatsapp('WHATSAPP', 'WhatsApp');

  const ReminderChannel(this.wire, this.label);
  final String wire;
  final String label;

  static ReminderChannel fromWire(String value) =>
      ReminderChannel.values.firstWhere((c) => c.wire == value, orElse: () => ReminderChannel.sms);
}

enum ReminderTone {
  gentle('GENTLE', 'Courtois'),
  neutral('NEUTRAL', 'Neutre'),
  firm('FIRM', 'Ferme');

  const ReminderTone(this.wire, this.label);
  final String wire;
  final String label;

  static ReminderTone fromWire(String value) =>
      ReminderTone.values.firstWhere((t) => t.wire == value, orElse: () => ReminderTone.neutral);
}

class ReminderRule {
  const ReminderRule({
    required this.id,
    required this.offsetDays,
    required this.channel,
    required this.tone,
    required this.enabled,
  });

  final String id;

  /// Négatif : rappel avant l'échéance ; positif : relance de retard.
  final int offsetDays;
  final ReminderChannel channel;
  final ReminderTone tone;
  final bool enabled;
}

class ReminderResult {
  const ReminderResult({required this.channel, required this.sent});

  final ReminderChannel channel;

  /// Faux si l'envoi a échoué (fournisseur indisponible) : à réessayer.
  final bool sent;
}

class MomoRequestResult {
  const MomoRequestResult({required this.reference, required this.simulated, required this.message});

  final String reference;
  final bool simulated;
  final String message;
}

/// Fichier téléchargé (export CSV).
class DownloadedFile {
  const DownloadedFile({required this.fileName, required this.bytes});

  final String fileName;
  final List<int> bytes;
}

/// Contrat de l'API du backend (hors synchronisation des données, qui passe par
/// `LedgerTransport`). Implémenté par [HttpBackendApi] ; simulé dans les tests.
abstract interface class BackendApi {
  Future<OtpRequestResult> requestOtp(String phone);
  Future<OtpVerification> verifyOtp(String phone, String code);
  Future<SessionTokens> setupPin({
    required String otpSessionToken,
    required String businessName,
    required String pin,
    required String termsVersion,
  });
  Future<SessionTokens> login({required String phone, required String pin});
  Future<void> logout();
  Future<void> changePin({required String currentPin, required String newPin});

  /// Supprime définitivement le compte et toutes ses données (confirmé par le PIN).
  Future<void> deleteAccount({required String pin});
  Future<Profile> profile();
  Future<Profile> updateBusinessName(String businessName);

  /// Accepte la version en vigueur des conditions (re-consentement).
  Future<void> acceptTerms(String termsVersion);

  /// Journal d'activité du compte (100 derniers événements).
  Future<List<ActivityEvent>> activity();

  /// Droit d'accès et de portabilité : copie JSON de toutes les données du compte.
  Future<DownloadedFile> exportMyData();

  /// Données d'un seul client ou fournisseur (demande d'accès de cette personne).
  Future<DownloadedFile> exportPartyData(String customerId, {required String fileName});

  /// Synthèse de caisse du serveur (sert à vérifier le calcul local).
  Future<TreasurySummary> cashSummary({required DateTime from, required DateTime to});
  Future<SubscriptionStatus> subscriptionStatus();
  Future<UpgradeResult> upgrade();
  Future<DashboardSummary> dashboard();
  Future<ReminderResult> sendReminder(String debtId, ReminderChannel channel);
  Future<List<ReminderRule>> reminderRules();
  Future<ReminderRule> saveReminderRule({
    required int offsetDays,
    required ReminderChannel channel,
    required ReminderTone tone,
    required bool enabled,
  });
  Future<void> deleteReminderRule(String id);
  Future<MomoRequestResult> requestMobileMoneyPayment(String debtId);
  Future<DownloadedFile> exportHistory();
}

/// Implémentation HTTP de [BackendApi].
class HttpBackendApi implements BackendApi {
  const HttpBackendApi(this._client);

  final ApiClient _client;

  // ---- Authentification ----

  @override
  Future<OtpRequestResult> requestOtp(String phone) async {
    final json = await _map(_client.send('POST', '/auth/otp/request', body: <String, Object?>{'phone': phone}));
    return OtpRequestResult(devCode: json['devCode'] as String?);
  }

  @override
  Future<OtpVerification> verifyOtp(String phone, String code) async {
    final json = await _map(_client.send('POST', '/auth/otp/verify', body: <String, Object?>{'phone': phone, 'code': code}));
    return _parse(() => OtpVerification(
          otpSessionToken: json['otpSessionToken']! as String,
          isNewUser: json['isNewUser']! as bool,
        ));
  }

  @override
  Future<SessionTokens> setupPin({
    required String otpSessionToken,
    required String businessName,
    required String pin,
    required String termsVersion,
  }) async {
    final json = await _map(_client.send('POST', '/auth/pin/setup', body: <String, Object?>{
      'otpSessionToken': otpSessionToken,
      'businessName': businessName,
      'pin': pin,
      'termsVersion': termsVersion,
    }));
    return _tokens(json);
  }

  @override
  Future<SessionTokens> login({required String phone, required String pin}) async {
    final json = await _map(_client.send('POST', '/auth/login', body: <String, Object?>{'phone': phone, 'pin': pin}));
    return _tokens(json);
  }

  @override
  Future<void> logout() => _client.send('POST', '/auth/logout');

  @override
  Future<void> deleteAccount({required String pin}) =>
      _client.send('POST', '/auth/account/delete', body: <String, Object?>{'pin': pin});

  @override
  Future<void> changePin({required String currentPin, required String newPin}) =>
      _client.send('POST', '/auth/pin/change', body: <String, Object?>{'currentPin': currentPin, 'newPin': newPin});

  @override
  Future<Profile> profile() async => _profile(await _map(_client.send('GET', '/auth/me')));

  @override
  Future<Profile> updateBusinessName(String businessName) async =>
      _profile(await _map(_client.send('PATCH', '/auth/me', body: <String, Object?>{'businessName': businessName})));

  // ---- Vie privée et données ----

  @override
  Future<void> acceptTerms(String termsVersion) =>
      _client.send('POST', '/auth/consent', body: <String, Object?>{'termsVersion': termsVersion});

  @override
  Future<List<ActivityEvent>> activity() async {
    final list = await _list(_client.send('GET', '/auth/activity'));
    return _parse(() => list
        .map((e) => e! as Map<String, Object?>)
        .map((e) => ActivityEvent(action: e['action']! as String, at: DateTime.parse(e['createdAt']! as String)))
        .toList());
  }

  @override
  Future<DownloadedFile> exportMyData() async {
    final data = await _client.send('GET', '/auth/export', responseType: ResponseType.bytes);
    if (data is! List<int>) throw const ServerException(200, 'Réponse d\'export invalide.');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return DownloadedFile(fileName: 'carne-mes-donnees-$today.json', bytes: data);
  }

  @override
  Future<DownloadedFile> exportPartyData(String customerId, {required String fileName}) async {
    final data = await _client.send('GET', '/auth/export/customers/$customerId', responseType: ResponseType.bytes);
    if (data is! List<int>) throw const ServerException(200, 'Réponse d\'export invalide.');
    return DownloadedFile(fileName: fileName, bytes: data);
  }

  @override
  Future<TreasurySummary> cashSummary({required DateTime from, required DateTime to}) async {
    final json = await _map(_client.send('GET', '/cash/summary', query: <String, Object?>{
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    }));
    return _parse(() => TreasurySummary(
          sales: Money.fromJson(json['sales']! as num),
          collected: Money.fromJson(json['collected']! as num),
          expenses: Money.fromJson(json['expenses']! as num),
          paidToSuppliers: Money.fromJson(json['paidToSuppliers']! as num),
          creditGranted: Money.fromJson(json['creditGranted']! as num),
          creditReceived: Money.fromJson(json['creditReceived']! as num),
          expensesByCategory: (json['expensesByCategory']! as List<Object?>)
              .map((e) => e! as Map<String, Object?>)
              .map((e) => ExpenseCategoryTotal(category: e['category']! as String, total: Money.fromJson(e['total']! as num)))
              .toList(),
        ));
  }

  // ---- Abonnement ----

  @override
  Future<SubscriptionStatus> subscriptionStatus() async {
    final json = await _map(_client.send('GET', '/subscription/status'));
    return _parse(() => SubscriptionStatus(
          plan: json['plan'] == 'PREMIUM' ? Plan.premium : Plan.free,
          planExpiresAt: _date(json['planExpiresAt']),
          customerCount: json['customerCount']! as int,
          customerLimit: json['customerLimit'] as int?,
          monthlyPrice: Money.fromJson(json['monthlyPriceFcfa']! as num),
          paymentsAvailable: json['paymentsAvailable'] as bool? ?? true,
        ));
  }

  @override
  Future<UpgradeResult> upgrade() async {
    final json = await _map(_client.send('POST', '/subscription/upgrade'));
    return _parse(() => UpgradeResult(
          activated: json['activated']! as bool,
          simulated: json['simulated']! as bool,
          message: json['message']! as String,
          reference: json['reference'] as String?,
        ));
  }

  // ---- Tableau de bord (Premium) ----

  @override
  Future<DashboardSummary> dashboard() async {
    final json = await _map(_client.send('GET', '/dashboard/summary'));
    return _parse(() => DashboardSummary(
          totalOutstanding: Money.fromJson(json['totalOutstanding']! as num),
          totalCustomers: json['totalCustomers']! as int,
          customersWithDebt: json['customersWithDebt']! as int,
          recoveryRate: (json['recoveryRate'] as num?)?.toDouble(),
          totalPayable: Money.fromJson((json['totalPayable'] as num?) ?? 0),
          payableOverdue: Money.fromJson((json['payableOverdue'] as num?) ?? 0),
          suppliersWithDebt: (json['suppliersWithDebt'] as int?) ?? 0,
          byCategory: (json['byCategory']! as List<Object?>)
              .map((e) => e! as Map<String, Object?>)
              .map((e) => CategoryBreakdown(
                    category: e['category']! as String,
                    outstanding: Money.fromJson(e['totalOutstanding']! as num),
                    count: e['count']! as int,
                  ))
              .toList(),
          overdue: (json['overdueDebts']! as List<Object?>)
              .map((e) => e! as Map<String, Object?>)
              .map((e) => OverdueItem(
                    debtId: e['debtId']! as String,
                    customerId: e['customerId']! as String,
                    customerName: e['customerName']! as String,
                    outstanding: Money.fromJson(e['outstanding']! as num),
                    daysOverdue: e['daysOverdue']! as int,
                    category: e['category']! as String,
                  ))
              .toList(),
          atRisk: (json['atRiskCustomers']! as List<Object?>)
              .map((e) => e! as Map<String, Object?>)
              .map((e) => AtRiskCustomer(
                    customerId: e['customerId']! as String,
                    customerName: e['customerName']! as String,
                    overdueCount: e['overdueDebtCount']! as int,
                    overdueAmount: Money.fromJson(e['totalOverdueAmount']! as num),
                    maxDaysOverdue: e['maxDaysOverdue']! as int,
                  ))
              .toList(),
          trend: (json['monthlyTrend']! as List<Object?>)
              .map((e) => e! as Map<String, Object?>)
              .map((e) => TrendPoint(
                    month: e['month']! as String,
                    granted: Money.fromJson(e['amountGranted']! as num),
                    recovered: Money.fromJson(e['amountRecovered']! as num),
                  ))
              .toList(),
        ));
  }

  // ---- Relances ----

  @override
  Future<ReminderResult> sendReminder(String debtId, ReminderChannel channel) async {
    final json = await _map(_client.send('POST', '/debts/$debtId/reminders', body: <String, Object?>{'channel': channel.wire}));
    return _parse(() => ReminderResult(
          channel: ReminderChannel.fromWire(json['channel']! as String),
          sent: json['status'] == 'SENT',
        ));
  }

  @override
  Future<List<ReminderRule>> reminderRules() async {
    final list = await _list(_client.send('GET', '/reminders/rules'));
    return _parse(() => list.map((e) => _rule(e! as Map<String, Object?>)).toList());
  }

  @override
  Future<ReminderRule> saveReminderRule({
    required int offsetDays,
    required ReminderChannel channel,
    required ReminderTone tone,
    required bool enabled,
  }) async {
    final json = await _map(_client.send('POST', '/reminders/rules', body: <String, Object?>{
      'offsetDays': offsetDays,
      'channel': channel.wire,
      'tone': tone.wire,
      'enabled': enabled,
    }));
    return _parse(() => _rule(json));
  }

  @override
  Future<void> deleteReminderRule(String id) => _client.send('DELETE', '/reminders/rules/$id');

  // ---- Mobile Money ----

  @override
  Future<MomoRequestResult> requestMobileMoneyPayment(String debtId) async {
    final json = await _map(_client.send('POST', '/payments/momo-request', body: <String, Object?>{'debtId': debtId}));
    return _parse(() => MomoRequestResult(
          reference: json['reference']! as String,
          simulated: json['simulated']! as bool,
          message: json['message']! as String,
        ));
  }

  // ---- Export ----

  @override
  Future<DownloadedFile> exportHistory() async {
    final data = await _client.send('GET', '/export/history', responseType: ResponseType.bytes);
    if (data is! List<int>) throw const ServerException(200, 'Réponse d\'export invalide.');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return DownloadedFile(fileName: 'carne-historique-$today.csv', bytes: data);
  }

  // ---- Interne ----

  static Future<Map<String, Object?>> _map(Future<Object?> request) async {
    final body = await request;
    if (body is Map) return body.cast<String, Object?>();
    throw const ServerException(200, 'Réponse du serveur invalide.');
  }

  static Future<List<Object?>> _list(Future<Object?> request) async {
    final body = await request;
    if (body is List) return body.cast<Object?>();
    throw const ServerException(200, 'Réponse du serveur invalide.');
  }

  static T _parse<T>(T Function() build) {
    try {
      return build();
    } on TypeError {
      throw const ServerException(200, 'Réponse du serveur invalide.');
    } on FormatException {
      throw const ServerException(200, 'Réponse du serveur invalide.');
    }
  }

  static SessionTokens _tokens(Map<String, Object?> json) =>
      _parse(() => SessionTokens(accessToken: json['accessToken']! as String, refreshToken: json['refreshToken']! as String));

  static Profile _profile(Map<String, Object?> json) => _parse(() => Profile(
        id: json['id']! as String,
        phone: json['phone']! as String,
        businessName: json['businessName']! as String,
        plan: json['plan'] == 'PREMIUM' ? Plan.premium : Plan.free,
        planExpiresAt: _date(json['planExpiresAt']),
        termsAccepted: json['termsAccepted'] as bool? ?? true,
        termsVersion: json['termsVersion'] as String?,
      ));

  static ReminderRule _rule(Map<String, Object?> json) => ReminderRule(
        id: json['id']! as String,
        offsetDays: json['offsetDays']! as int,
        channel: ReminderChannel.fromWire(json['channel']! as String),
        tone: ReminderTone.fromWire(json['tone']! as String),
        enabled: json['enabled']! as bool,
      );

  static DateTime? _date(Object? value) => value == null ? null : DateTime.parse(value as String);
}
