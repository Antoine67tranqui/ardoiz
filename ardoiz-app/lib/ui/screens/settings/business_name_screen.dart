import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/session_service.dart';
import '../../../core/validators.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

class BusinessNameScreen extends ConsumerStatefulWidget {
  const BusinessNameScreen({super.key});

  @override
  ConsumerState<BusinessNameScreen> createState() => _BusinessNameScreenState();
}

class _BusinessNameScreenState extends ConsumerState<BusinessNameScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    _name = TextEditingController(text: session is SignedIn ? session.profile.businessName : '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).updateBusinessName(_name.text.trim());
      if (!mounted) return;
      context.pop();
      showSnack(context, 'Nom de la boutique modifié');
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nom de la boutique')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                Text('Ce nom apparaît dans les messages de relance envoyés à vos clients.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Nom de la boutique'),
                  validator: Validators.businessName,
                  onFieldSubmitted: (_) => _save(),
                ),
                if (_error != null) ...<Widget>[const SizedBox(height: 16), FormErrorBanner(_error!)],
                const SizedBox(height: 24),
                BusyButton(label: 'Enregistrer', busy: _busy, onPressed: _save),
              ],
            ),
          ),
        ),
      );
}
