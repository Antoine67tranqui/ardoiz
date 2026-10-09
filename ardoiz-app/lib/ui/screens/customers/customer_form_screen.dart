import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/formatters.dart';
import '../../../core/money.dart';
import '../../../core/validators.dart';
import '../../../domain/models.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/common.dart';

/// Création (customerId == null) ou modification d'un client ou d'un fournisseur.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({
    super.key,
    this.customerId,
    this.kind = PartyKind.client,
  });

  final String? customerId;

  /// Type à la création (en modification, c'est celui de la fiche : il ne change jamais).
  final PartyKind kind;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _limit = TextEditingController();
  bool _loaded = false;
  bool _optOut = false;
  PartyKind? _editedKind;
  String? _error;

  bool get _editing => widget.customerId != null;
  PartyKind get _kind => _editedKind ?? widget.kind;
  bool get _supplier => _kind == PartyKind.supplier;

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
    _editedKind = view.customer.kind;
    _optOut = view.customer.reminderOptOut;
    _name.text = view.customer.name;
    _phone.text = view.customer.phone;
    final limit = view.customer.creditLimit;
    _limit.text = limit == null ? '' : formatMoneyInput(limit);
  }

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
          reminderOptOut: _supplier ? null : _optOut,
        );
        context.pop();
      } else {
        final created = repo.addCustomer(
          name: _name.text,
          phone: _phone.text,
          creditLimit: _supplier ? null : limit,
          kind: widget.kind,
          reminderOptOut: _supplier ? false : _optOut,
        );
        context.pushReplacement(Routes.customer(created.id));
      }
    } on Object catch (e) {
      setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider).value;
    final isPremium = ref.watch(isPremiumProvider);

    if (_editing) {
      if (customers == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      if (ref.watch(customerByIdProvider(widget.customerId!)) == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const EmptyState(
            icon: Icons.person_off_outlined,
            title: 'Client introuvable',
            message: 'Ce client a été supprimé.',
          ),
        );
      }
      _load();
    } else if (!isPremium &&
        (customers?.where((c) => c.customer.kind == widget.kind).length ?? 0) >=
            freePlanCustomerLimit) {
      final noun = widget.kind == PartyKind.supplier
          ? 'fournisseurs'
          : 'clients';
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.kind == PartyKind.supplier
                ? 'Nouveau fournisseur'
                : 'Nouveau client',
          ),
        ),
        body: EmptyState(
          icon: Icons.workspace_premium_outlined,
          title: 'Limite du plan gratuit atteinte',
          message:
              'Le plan gratuit permet $freePlanCustomerLimit $noun. Passez à Premium pour en ajouter autant que vous voulez.',
          action: BusyButton(
            label: 'Découvrir Premium',
            onPressed: () => context.push(Routes.subscription),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing
              ? (_supplier ? 'Modifier le fournisseur' : 'Modifier le client')
              : (_supplier ? 'Nouveau fournisseur' : 'Nouveau client'),
        ),
      ),
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
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(100),
                ],
                decoration: InputDecoration(
                  labelText: _supplier ? 'Nom du fournisseur' : 'Nom du client',
                ),
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
                  helperText:
                      'Avec l\'indicatif (+229...) pour utiliser WhatsApp',
                  helperMaxLines: 2,
                ),
                validator: Validators.customerPhone,
              ),
              if (!_supplier) ...<Widget>[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _limit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Plafond de crédit (facultatif)',
                    suffixText: 'FCFA',
                    helperText:
                        'Vous êtes alerté quand ce client dépasse ce montant.',
                    helperMaxLines: 2,
                  ),
                  validator: Validators.creditLimit,
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _optOut,
                  onChanged: (value) => setState(() => _optOut = value),
                  title: const Text('Ce client refuse les relances'),
                  subtitle: const Text(
                    'Aucune relance ne lui sera envoyée par Carné (droit d\'opposition).',
                  ),
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 16),
                FormErrorBanner(_error!),
              ],
              const SizedBox(height: 24),
              BusyButton(
                label: _editing
                    ? 'Enregistrer'
                    : (_supplier
                          ? 'Ajouter le fournisseur'
                          : 'Ajouter le client'),
                icon: Icons.check,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
