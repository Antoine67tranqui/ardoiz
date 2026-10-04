import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/brand.dart';
import '../../widgets/auth_widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AuthScaffold(
      showBack: false,
      title: 'Bienvenue sur ${Brand.name}',
      subtitle: Brand.tagline,
      children: <Widget>[
        const _Benefit(Icons.menu_book_outlined, 'Notez les dettes de vos clients en quelques secondes.'),
        const _Benefit(Icons.wifi_off_outlined, 'Fonctionne sans internet : tout est enregistré sur votre téléphone.'),
        const _Benefit(Icons.notifications_active_outlined, 'Relancez vos clients par SMS ou WhatsApp, sans les froisser.'),
        const SizedBox(height: 28),
        FilledButton(onPressed: () => context.push(Routes.signup), child: const Text('Créer mon compte')),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => context.push(Routes.login), child: const Text('J\'ai déjà un compte')),
        const SizedBox(height: 20),
        Text(
          'Vos données sont chiffrées sur ce téléphone.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ExcludeSemantics(child: Icon(icon, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(width: 14),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      );
}
