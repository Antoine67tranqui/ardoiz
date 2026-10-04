import 'package:dio/dio.dart';

import '../../core/money.dart';
import '../../domain/dashboard.dart';
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
  });

  final String id;
  final String phone;
  final String businessName;
  final Plan plan;
  final DateTime? planExpiresAt;

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
  });

  final Plan plan;
  final DateTime? planExpiresAt;
  final int customerCount;

  /// Null = clients illimités (Premium).
  final int? customerLimit;
  final Money monthlyPrice;
}

class UpgradeResult {
  const UpgradeResult({required this.activated, required this.simulated, required this.message, this.reference});

  final bool activated;
  final bool simulated;
  final String message;
  final String? reference;
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
  });
  Future<SessionTokens> login({required String phone, required String pin});
  Future<void> logout();
  Future<void> changePin({required String currentPin, required String newPin});
  Future<Profile> profile();
  Future<Profile> updateBusinessName(String businessName);
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
  }) async {
    final json = await _map(_client.send('POST', '/auth/pin/setup', body: <String, Object?>{
      'otpSessionToken': otpSessionToken,
      'businessName': businessName,
      'pin': pin,
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
  Future<void> changePin({required String currentPin, required String newPin}) =>
      _client.send('POST', '/auth/pin/change', body: <String, Object?>{'currentPin': currentPin, 'newPin': newPin});

  @override
  Future<Profile> profile() async => _profile(await _map(_client.send('GET', '/auth/me')));

  @override
  Future<Profile> updateBusinessName(String businessName) async =>
      _profile(await _map(_client.send('PATCH', '/auth/me', body: <String, Object?>{'businessName': businessName})));

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
