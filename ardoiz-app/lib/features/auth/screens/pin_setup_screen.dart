import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final _businessNameController = TextEditingController();
  final _pinController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final otpSessionToken = ref.read(onboardingProvider).otpSessionToken;
    if (otpSessionToken == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.setupPin(
        otpSessionToken: otpSessionToken,
        businessName: _businessNameController.text.trim(),
        pin: _pinController.text.trim(),
      );
      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      setState(() => _error = 'Impossible de creer le compte. Reessayez.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Creer votre compte')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nom de votre boutique', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _businessNameController,
              decoration: const InputDecoration(hintText: 'Ex: Boutique Fatou'),
            ),
            const SizedBox(height: 24),
            Text('Creez votre code PIN (4 chiffres)', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, letterSpacing: 8),
              decoration: const InputDecoration(counterText: ''),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Creer mon compte'),
            ),
          ],
        ),
      ),
    );
  }
}
