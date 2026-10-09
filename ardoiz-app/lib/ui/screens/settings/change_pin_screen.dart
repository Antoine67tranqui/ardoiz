import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/validators.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).changePin(currentPin: _current.text, newPin: _next.text);
      if (!mounted) return;
      context.pop();
      showSnack(context, 'Code PIN modifié');
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Changer mon code PIN')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                Text(
                  'Après le changement, vos autres appareils devront se reconnecter avec le nouveau code.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                DigitsField(
                  fieldKey: const Key('pin-current'),
                  controller: _current,
                  label: 'Code PIN actuel',
                  length: 4,
                  obscure: true,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  validator: Validators.pin,
                ),
                const SizedBox(height: 16),
                DigitsField(
                  fieldKey: const Key('pin-new'),
                  controller: _next,
                  label: 'Nouveau code PIN',
                  length: 4,
                  obscure: true,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final base = Validators.pin(value);
                    if (base != null) return base;
                    return value == _current.text ? 'Choisissez un code différent de l\'actuel.' : null;
                  },
                ),
                const SizedBox(height: 16),
                DigitsField(
                  fieldKey: const Key('pin-confirm'),
                  controller: _confirm,
                  label: 'Confirmer le nouveau code',
                  length: 4,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _save,
                  validator: (value) => value == _next.text ? null : 'Les deux codes ne sont pas identiques.',
                ),
                if (_error != null) ...<Widget>[const SizedBox(height: 16), FormErrorBanner(_error!)],
                const SizedBox(height: 24),
                BusyButton(label: 'Changer le code', busy: _busy, onPressed: _save),
              ],
            ),
          ),
        ),
      );
}
