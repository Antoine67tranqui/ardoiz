import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/legal.dart';

/// Résumé lisible, dans l'application, de ce que Carné fait des données : le
/// consentement doit être éclairé même sans accès au site.
Future<void> showPrivacySummary(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _PrivacySummary(),
    );

class _PrivacySummary extends ConsumerWidget {
  const _PrivacySummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final privacy = Legal.privacyUri();
    final terms = Legal.termsUri();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: <Widget>[
          Text('Vos données et Carné', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const _Point('Ce que nous gardons', 'Votre numéro de téléphone, le nom de votre boutique, une empreinte de votre code PIN (jamais le code lui-même), '
              'vos clients et fournisseurs (nom, téléphone), vos dettes, vos paiements et votre journal de caisse.'),
          const _Point('Où', 'Sur votre téléphone, dans une base chiffrée, et sur nos serveurs pour retrouver vos données si vous changez de téléphone '
              'et pour envoyer les relances.'),
          const _Point('Les SMS', 'Les codes de vérification et les relances sont envoyés par un opérateur de SMS, qui reçoit le numéro du destinataire et le message.'),
          const _Point('Vos clients', 'Leurs noms et numéros sont des données personnelles : vous êtes responsable de les informer et de respecter leur refus '
              '(case « Ce client refuse les relances »).'),
          const _Point('Pas de publicité', 'Nous ne vendons aucune donnée et n\'utilisons aucun outil de suivi publicitaire.'),
          const _Point('Vos droits', 'Dans Réglages : exporter vos données, les corriger, voir l\'activité de votre compte, supprimer votre compte et toutes vos données.'),
          const SizedBox(height: 12),
          if (terms != null)
            OutlinedButton(onPressed: () => ref.read(urlOpenerProvider).open(terms), child: const Text('Lire les conditions d\'utilisation')),
          if (privacy != null) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => ref.read(urlOpenerProvider).open(privacy), child: const Text('Lire la politique de confidentialité complète')),
          ],
          const SizedBox(height: 8),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.title, this.text);

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}

/// Case de consentement explicite (jamais cochée d'avance), avec accès au résumé.
class ConsentCheckbox extends StatelessWidget {
  const ConsentCheckbox({super.key, required this.value, required this.onChanged, this.errorText});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CheckboxListTile(
          key: const Key('consent'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          title: const Text('J\'ai lu et j\'accepte les conditions d\'utilisation et la politique de confidentialité.'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => showPrivacySummary(context), child: const Text('Voir ce que Carné fait de mes données')),
        ),
        if (errorText != null)
          Semantics(
            liveRegion: true,
            child: Text(errorText!, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}
