import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/signup_flow.dart';
import '../../../core/validators.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

/// Étape 1 : numéro de téléphone, le serveur envoie un code par SMS.
/// Sert aussi à réinitialiser un PIN oublié (même parcours).
class SignupPhoneScreen extends ConsumerStatefulWidget {
  const SignupPhoneScreen({super.key, this.phone});

  final String? phone;

  @override
  ConsumerState<SignupPhoneScreen> createState() => _SignupPhoneScreenState();
}

class _SignupPhoneScreenState extends ConsumerState<SignupPhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone = TextEditingController(text: widget.phone ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final phone = Validators.normalizeAccountPhone(_phone.text);
    try {
      final result = await ref.read(backendApiProvider).requestOtp(phone);
      ref.read(signupFlowProvider.notifier).codeSent(phone: phone, devCode: result.devCode);
      if (mounted) unawaited(context.push(Routes.signupCode));
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: 'Votre numéro de téléphone',
        subtitle: 'Nous vous envoyons un code par SMS pour vérifier votre numéro. '
            'Si vous avez oublié votre PIN, ce code vous permet d\'en choisir un nouveau.',
        children: <Widget>[
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextFormField(
                  key: const Key('phone'),
                  controller: _phone,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.telephoneNumber],
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s().-]'))],
                  decoration: const InputDecoration(labelText: 'Numéro de téléphone', hintText: '+229 01 67 07 70 27'),
                  validator: Validators.accountPhone,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...<Widget>[const SizedBox(height: 16), FormErrorBanner(_error!)],
                const SizedBox(height: 24),
                BusyButton(label: 'Recevoir le code', busy: _busy, onPressed: _submit),
              ],
            ),
          ),
        ],
      );
}
