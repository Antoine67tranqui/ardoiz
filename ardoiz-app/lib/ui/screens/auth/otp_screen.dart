import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/signup_flow.dart';
import '../../../core/validators.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

/// Étape 2 : code à 6 chiffres reçu par SMS. Le serveur impose un délai de
/// 60 s entre deux envois : le bouton « Renvoyer » suit le même compte à rebours.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const int _cooldownSeconds = 60;

  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  Timer? _timer;
  int _secondsLeft = _cooldownSeconds;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsLeft = _secondsLeft - 1);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final phone = ref.read(signupFlowProvider).phone;
    if (phone == null || _busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(backendApiProvider).verifyOtp(phone, _code.text);
      ref.read(signupFlowProvider.notifier).verified(otpSessionToken: result.otpSessionToken, isNewUser: result.isNewUser);
      if (mounted) unawaited(context.push(Routes.signupPin));
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final phone = ref.read(signupFlowProvider).phone;
    if (phone == null) return;
    setState(() => _error = null);
    try {
      final result = await ref.read(backendApiProvider).requestOtp(phone);
      ref.read(signupFlowProvider.notifier).resent(devCode: result.devCode);
      _code.clear();
      _startCountdown();
      if (mounted) showSnack(context, 'Un nouveau code vient d\'être envoyé.');
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(signupFlowProvider);
    final theme = Theme.of(context);
    return AuthScaffold(
      title: 'Code de vérification',
      subtitle: 'Saisissez le code à 6 chiffres envoyé au ${flow.phone ?? 'votre numéro'}.',
      children: <Widget>[
        if (flow.devCode != null) ...<Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Serveur de test : aucun SMS réel n\'est envoyé. Votre code est ${flow.devCode}.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DigitsField(
                fieldKey: const Key('otp'),
                controller: _code,
                label: 'Code reçu par SMS',
                length: 6,
                autofocus: true,
                autofillHints: const <String>[AutofillHints.oneTimeCode],
                validator: Validators.otp,
                textInputAction: TextInputAction.done,
                onSubmitted: _verify,
              ),
              if (_error != null) ...<Widget>[const SizedBox(height: 16), FormErrorBanner(_error!)],
              const SizedBox(height: 24),
              BusyButton(label: 'Vérifier', busy: _busy, onPressed: _verify),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _secondsLeft > 0 || _busy ? null : _resend,
                child: Text(_secondsLeft > 0 ? 'Renvoyer le code dans $_secondsLeft s' : 'Renvoyer le code'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
