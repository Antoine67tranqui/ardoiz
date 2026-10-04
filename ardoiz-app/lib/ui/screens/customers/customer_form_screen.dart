import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/session_service.dart';
import '../../../core/money.dart';
import '../../../core/validators.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

/// Création (customerId == null) ou modification d'un client.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, this.customerId});

  final String? customerId;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _limit = TextEditingController();
  bool _loaded = false;
  String? _error;

  bool get _editing => widget.customerId != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _limit.dispose();
    super.dispose();
  }

  void _load() {
    if (_loaded || !_editing) return;
    final view = ref.read(customerByIdProvider(widget.customerId!));
    if (view == null) return;
    _loaded = true;
    _name.text = view.customer.name;
    _phone.text = view.customer.phone;
    final limit = view.customer.creditLimit;
    _limit.text = limit == null ? '' : _plain(limit);
  }

  static String _plain(Money value) => value.cents % 100 == 0 ? '${value.cents ~/ 100}' : (value.cents / 100).toString().replaceAll('.', ',');

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(repositoryProvider);
    final limitText = _limit.text.trim();
    final limit = limitText.isEmpty ? null : Money.tryParse(limitText);
    try {
      if (_editing) {
        repo.updateCustomer(
          widget.customerId!,
          name: _name.text,
          phone: _phone.text,
          creditLimit: limit,
          clearCreditLimit: limitText.isEmpty,
        );
        context.pop();
      } else {
        final created = repo.addCustomer(name: _name.text, phone: _phone.text, creditLimit: limit);
        context.pushReplacement(Routes.customer(created.id));
      }
    } on Object catch (e) {
      setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider).value;
    final session = ref.watch(sessionProvider);
    final isPremium = session is SignedIn && session.profile.isPremium;

    if (_editing) {
      if (customers == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
      if (ref.watch(customerByIdProvider(widget.customerId!)) == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const EmptyState(icon: Icons.person_off_outlined, title: 'Client introuvable', message: 'Ce client a été supprimé.'),
        );
      }
      _load();
    } else if (!isPremium && (customers?.length ?? 0) >= freePlanCustomerLimit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nouveau client')),
        body: EmptyState(
          icon: Icons.workspace_premium_outlined,
          title: 'Limite du plan gratuit atteinte',
          message: 'Le plan gratuit permet $freePlanCustomerLimit clients. Passez à Premium pour en ajouter autant que vous voulez.',
          action: BusyButton(label: 'Découvrir Premium', onPressed: () => context.push(Routes.subscription)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Modifier le client' : 'Nouveau client')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              TextFormField(
                controller: _name,
                autofocus: !_editing,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.name],
                inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(100)],
                decoration: const InputDecoration(labelText: 'Nom du client'),
                validator: Validators.customerName,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                  helperText: 'Avec l\'indicatif (+229...) pour utiliser WhatsApp',
                  helperMaxLines: 2,
                ),
                validator: Validators.customerPhone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _limit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Plafond de crédit (facultatif)',
                  suffixText: 'FCFA',
                  helperText: 'Vous êtes alerté quand ce client dépasse ce montant.',
                  helperMaxLines: 2,
                ),
                validator: Validators.creditLimit,
                onFieldSubmitted: (_) => _save(),
              ),
              if (_error != null) ...<Widget>[const SizedBox(height: 16), FormErrorBanner(_error!)],
              const SizedBox(height: 24),
              BusyButton(label: _editing ? 'Enregistrer' : 'Ajouter le client', icon: Icons.check, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
