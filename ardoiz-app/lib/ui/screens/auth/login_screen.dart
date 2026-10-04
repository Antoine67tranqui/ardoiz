import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/session_service.dart';
import '../../../core/validators.dart';
import '../../../data/remote/api_exceptions.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.phone});

  /// Numéro à pré-remplir (session expirée, PIN oublié).
  final String? phone;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final signedOut = ref.read(sessionProvider);
    _phone = TextEditingController(text: widget.phone ?? (signedOut is SignedOut ? signedOut.phone : null) ?? '');
  }

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit({bool discardUnsynced = false}) async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(
            phone: Validators.normalizeAccountPhone(_phone.text),
            pin: _pin.text,
            discardUnsynced: discardUnsynced,
          );
    } on UnsyncedDataException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final proceed = await confirm(
        context,
        title: 'Données non envoyées',
        message: '${e.count} modification${e.count > 1 ? 's' : ''} du compte précédent n\'${e.count > 1 ? 'ont' : 'a'} jamais été envoyée${e.count > 1 ? 's' : ''} '
            'et seront perdue${e.count > 1 ? 's' : ''} si vous continuez avec ce compte.',
        confirmLabel: 'Continuer et perdre',
        destructive: true,
      );
      if (proceed && mounted) await _submit(discardUnsynced: true);
      return;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = _message(e));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  static String _message(Object error) {
    if (error is RejectedException && error.statusCode == 401) {
      // Le serveur détaille un compte verrouillé ; un simple échec reste générique.
      return error.message.contains('tentatives') ? error.message : 'Numéro ou code PIN incorrect.';
    }
    return describeError(error);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final expired = session is SignedOut && session.reason == SignedOutReason.expired;
    return AuthScaffold(
      title: 'Connexion',
      subtitle: expired ? 'Votre session a expiré. Saisissez votre PIN pour continuer : vos données sont conservées.' : 'Saisissez votre numéro et votre code PIN.',
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                key: const Key('phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.telephoneNumber],
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s().-]'))],
                decoration: const InputDecoration(labelText: 'Numéro de téléphone', hintText: '+229 01 67 07 70 27'),
                validator: Validators.accountPhone,
              ),
              const SizedBox(height: 16),
              DigitsField(
                fieldKey: const Key('pin'),
                controller: _pin,
                label: 'Code PIN (4 chiffres)',
                length: 4,
                obscure: true,
                autofillHints: const <String>[AutofillHints.password],
                validator: Validators.pin,
                textInputAction: TextInputAction.done,
                onSubmitted: _submit,
              ),
              if (_error != null) ...<Widget>[const SizedBox(height: 16), FormErrorBanner(_error!)],
              const SizedBox(height: 24),
              BusyButton(label: 'Se connecter', busy: _busy, onPressed: _submit),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => context.push('${Routes.signup}?phone=${Uri.encodeQueryComponent(_phone.text)}'),
                child: const Text('Code PIN oublié ?'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
