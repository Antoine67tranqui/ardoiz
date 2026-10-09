import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../widgets/sync_banner.dart';

/// Coque des trois onglets : Clients, Tableau de bord, Réglages.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const List<String> _tabs = <String>[
    Routes.customers,
    Routes.suppliers,
    Routes.cash,
    Routes.dashboard,
    Routes.settings,
  ];

  int get _index {
    final i = _tabs.indexWhere(location.startsWith);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          const SyncBanner(),
          Expanded(child: child),
        ],
      ),
    ),
    // La barre d'onglets a une hauteur fixe : au-delà de 130 % de taille de texte, les libellés
    // débordent. Le contenu de la page, lui, suit le réglage complet de l'utilisateur.
    bottomNavigationBar: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      ),
      child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => context.go(_tabs[i]),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Fournisseurs',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Caisse',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Bilan',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Réglages',
          ),
        ],
      ),
    ),
  );
}
