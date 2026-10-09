import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/legal.dart';
import '../../../data/remote/api_exceptions.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy_widgets.dart';

/// Les conditions ont changé : l'utilisateur doit accepter la nouvelle version
/// avant de continuer à utiliser l'application.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _consent = false;
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    if (_busy) return;
    if (!_consent) {
      setState(() => _error = 'Vous devez accepter pour continuer.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).acceptTerms();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? describeError(e) : 'Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverVersion = ref.watch(sessionProvider).whenSignedIn((p) => p.termsVersion);
    // Le serveur attend une version que cette application ne connaît pas : il faut la mettre à jour.
    final outdated = serverVersion != null && serverVersion != Legal.termsVersion;
    return AuthScaffold(
      showBack: false,
      title: 'Nos conditions ont changé',
      subtitle: 'Prenez un instant pour lire la nouvelle version de nos conditions d\'utilisation et de notre politique de confidentialité.',
      children: <Widget>[
        if (outdated)
          const FormErrorBanner('Cette version de Carné est trop ancienne pour accepter les nouvelles conditions. Mettez l\'application à jour.')
        else ...<Widget>[
          ConsentCheckbox(value: _consent, onChanged: (v) => setState(() => _consent = v)),
          if (_error != null) ...<Widget>[const SizedBox(height: 8), FormErrorBanner(_error!)],
          const SizedBox(height: 16),
          BusyButton(label: 'Accepter et continuer', busy: _busy, onPressed: _accept),
        ],
      ],
    );
  }
}
