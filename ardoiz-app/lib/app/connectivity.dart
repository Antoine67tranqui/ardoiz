import 'package:connectivity_plus/connectivity_plus.dart';

/// Disponibilité du réseau (abstraction pour les tests). « En ligne » signifie
/// qu'une interface réseau est active ; seule une vraie requête prouve que le
/// serveur répond, d'où la gestion des échecs réseau dans le moteur.
abstract interface class ConnectivityService {
  Future<bool> get isOnline;

  /// Émet à chaque changement de disponibilité.
  Stream<bool> get onChanged;
}

class PluginConnectivityService implements ConnectivityService {
  PluginConnectivityService([Connectivity? connectivity]) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _online(List<ConnectivityResult> results) => results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> get isOnline async => _online(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onChanged => _connectivity.onConnectivityChanged.map(_online).distinct();
}
