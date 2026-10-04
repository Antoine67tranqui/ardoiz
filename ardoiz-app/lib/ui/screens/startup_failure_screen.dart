import 'package:flutter/material.dart';

import '../../app/bootstrap.dart';
import '../../core/brand.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/common.dart';

/// Application minimale affichée quand le démarrage échoue : explique et propose
/// la seule action possible.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.failure, required this.onReset, required this.onRetry});

  final BootstrapFailed failure;
  final Future<void> Function() onReset;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: Brand.name,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: StartupFailureScreen(failure: failure, onReset: onReset, onRetry: onRetry),
      );
}

class StartupFailureScreen extends StatefulWidget {
  const StartupFailureScreen({super.key, required this.failure, required this.onReset, required this.onRetry});

  final BootstrapFailed failure;
  final Future<void> Function() onReset;
  final Future<void> Function() onRetry;

  @override
  State<StartupFailureScreen> createState() => _StartupFailureScreenState();
}

class _StartupFailureScreenState extends State<StartupFailureScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final ok = await confirm(
      context,
      title: 'Réinitialiser les données de ce téléphone ?',
      message: 'Vos clients et dettes déjà envoyés au serveur reviendront à votre connexion. '
          'Les modifications faites hors ligne et jamais envoyées seront perdues.',
      confirmLabel: 'Réinitialiser',
      destructive: true,
    );
    if (ok && mounted) await _run(widget.onReset);
  }

  @override
  Widget build(BuildContext context) {
    final (String title, String advice) = switch (widget.failure.problem) {
      BootstrapProblem.configuration => (
          'Configuration incorrecte',
          'Cette version de l\'application n\'est pas configurée correctement. Installez la dernière version ou contactez le support.',
        ),
      BootstrapProblem.encryptionUnavailable => (
          'Chiffrement indisponible',
          'Carné refuse de stocker vos données financières sans chiffrement. Installez la dernière version ou contactez le support.',
        ),
      BootstrapProblem.keyMismatch => (
          'Données locales illisibles',
          'La clé de sécurité de ce téléphone ne permet plus de lire vos données (téléphone restauré ou clé perdue). '
              'Vous pouvez repartir d\'une base vide : vos données seront récupérées depuis le serveur.',
        ),
      BootstrapProblem.database => (
          'Impossible d\'ouvrir vos données',
          'La base locale n\'a pas pu être ouverte. Réessayez, ou repartez d\'une base vide : vos données seront récupérées depuis le serveur.',
        ),
    };
    return AuthScaffold(
      showBack: false,
      title: title,
      subtitle: advice,
      children: <Widget>[
        FormErrorBanner(widget.failure.message),
        const SizedBox(height: 24),
        BusyButton(label: 'Réessayer', busy: _busy, onPressed: () => _run(widget.onRetry)),
        if (widget.failure.canResetLocalData) ...<Widget>[
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error, minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _reset,
            child: const Text('Repartir d\'une base vide'),
          ),
        ],
      ],
    );
  }
}
