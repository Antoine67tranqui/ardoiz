import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/session_service.dart';
import '../../../app/signup_flow.dart';
import '../../../core/validators.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy_widgets.dart';

/// Étape 3 : nom de la boutique et code PIN (création, ou réinitialisation après
/// un PIN oublié : le serveur révoque alors les sessions ouvertes sur d'autres appareils).
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _business = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _consent = false;
  bool _consentError = false;
  String? _error;

  @override
  void dispose() {
    _business.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit({bool discardUnsynced = false}) async {
    final token = ref.read(signupFlowProvider).otpSessionToken;
    if (token == null || _busy) return;
    final valid = _formKey.currentState?.validate() ?? false;
    // Consentement explicite : sans lui, aucun compte n'est créé.
    if (!_consent) setState(() => _consentError = true);
    if (!valid || !_consent) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).completeSignUp(
            otpSessionToken: token,
            businessName: _business.text.trim(),
            pin: _pin.text,
            discardUnsynced: discardUnsynced,
          );
      ref.read(signupFlowProvider.notifier).reset();
    } on UnsyncedDataException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final proceed = await confirm(
        context,
        title: 'Données non envoyées',
        message: '${e.count} modification(s) d\'un autre compte, jamais envoyée(s), seront perdue(s) si vous continuez.',
        confirmLabel: 'Continuer et perdre',
        destructive: true,
      );
      if (proceed && mounted) await _submit(discardUnsynced: true);
      return;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e));
      // Session OTP expirée ou déjà utilisée : il faut recommencer la vérification.
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(signupFlowProvider);
    if (!flow.isVerified) {
      // Arrivée sans vérification (retour arrière, reprise après arrêt de l'app).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(Routes.signup);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return AuthScaffold(
      title: flow.isNewUser ? 'Créez votre compte' : 'Choisissez un nouveau PIN',
      subtitle: flow.isNewUser
          ? 'Dernière étape : le nom de votre boutique et un code PIN que vous seul connaissez.'
          : 'Votre numéro est vérifié. Choisissez un nouveau code PIN : les autres appareils devront se reconnecter.',
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                key: const Key('business'),
                controller: _business,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nom de votre boutique', hintText: 'Boutique Fatou'),
                validator: Validators.businessName,
              ),
              const SizedBox(height: 16),
              DigitsField(
                fieldKey: const Key('pin'),
                controller: _pin,
                label: 'Code PIN (4 chiffres)',
                length: 4,
                obscure: true,
                validator: Validators.pin,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              DigitsField(
                fieldKey: const Key('confirm'),
                controller: _confirm,
                label: 'Confirmez le code PIN',
                length: 4,
                obscure: true,
                validator: (value) => value != _pin.text ? 'Les deux codes PIN ne correspondent pas.' : Validators.pin(value),
                textInputAction: TextInputAction.done,
                onSubmitted: _submit,
              ),
              const SizedBox(height: 8),
              ConsentCheckbox(
                value: _consent,
                onChanged: (v) => setState(() {
                  _consent = v;
                  if (v) _consentError = false;
                }),
                errorText: _consentError ? 'Vous devez accepter pour continuer.' : null,
              ),
              if (_error != null) ...<Widget>[const SizedBox(height: 16), FormErrorBanner(_error!)],
              const SizedBox(height: 24),
              BusyButton(label: flow.isNewUser ? 'Créer mon compte' : 'Enregistrer le nouveau PIN', busy: _busy, onPressed: _submit),
            ],
          ),
        ),
      ],
    );
  }
}
