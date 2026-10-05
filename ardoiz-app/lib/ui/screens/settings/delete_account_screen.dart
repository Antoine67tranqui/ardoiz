import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/validators.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

/// Suppression définitive du compte : explique ce qui disparaît et exige le PIN
/// ainsi qu'une confirmation explicite.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pin = TextEditingController();
  bool _understood = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy || !_understood || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Succès : la session se ferme et le routeur ramène à l'accueil.
      await ref.read(sessionProvider.notifier).deleteAccount(pin: _pin.text);
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Supprimer mon compte')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Text('Cette action est définitive.', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const _Bullet('Votre compte, vos clients, leurs dettes et tous les remboursements sont effacés de nos serveurs.'),
              const _Bullet('Les données de ce téléphone sont effacées, y compris les modifications pas encore envoyées.'),
              const _Bullet('Nous ne pourrons pas les récupérer. Pensez à exporter votre historique avant (Réglages, Exporter l\'historique).'),
              const SizedBox(height: 20),
              DigitsField(
                fieldKey: const Key('delete-pin'),
                controller: _pin,
                label: 'Votre code PIN',
                length: 4,
                obscure: true,
                textInputAction: TextInputAction.done,
                onSubmitted: _delete,
                validator: Validators.pin,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _understood,
                onChanged: _busy ? null : (value) => setState(() => _understood = value ?? false),
                title: const Text('Je comprends que mes données seront supprimées définitivement.'),
              ),
              if (_error != null) ...<Widget>[const SizedBox(height: 8), FormErrorBanner(_error!)],
              const SizedBox(height: 16),
              Semantics(
                button: true,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: _busy || !_understood ? null : _delete,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Supprimer définitivement mon compte'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 8)),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      );
}
