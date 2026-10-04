import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/session_service.dart';
import '../../../core/contact.dart';
import '../../../core/formatters.dart';
import '../../../core/reminder_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/remote/backend_api.dart';
import '../../../domain/models.dart';
import '../../widgets/common.dart';
import 'payment_sheet.dart';

/// Détail d'une dette : avancement, paiements, relance, demande Mobile Money.
class DebtDetailScreen extends ConsumerStatefulWidget {
  const DebtDetailScreen({super.key, required this.debtId});

  final String debtId;

  @override
  ConsumerState<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends ConsumerState<DebtDetailScreen> {
  /// Action réseau en cours (empêche le double envoi d'une relance ou d'une demande).
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(customersProvider).hasValue;
    final view = ref.watch(debtByIdProvider(widget.debtId));
    if (view == null) {
      return Scaffold(
        appBar: AppBar(),
        body: loaded
            ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Dette introuvable', message: 'Cette dette a été supprimée.')
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final customer = ref.watch(customerByIdProvider(view.debt.customerId));
    final theme = Theme.of(context);
    final colors = context.statusColors;
    final debt = view.debt;
    final settled = view.status == DebtStatus.paid;
    final progress = debt.amount.cents == 0 ? 0.0 : (view.paid.cents / debt.amount.cents).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dette'),
        actions: <Widget>[
          PopupMenuButton<_Action>(
            tooltip: 'Plus d\'actions',
            onSelected: (action) => _onAction(view, action),
            itemBuilder: (context) => const <PopupMenuEntry<_Action>>[
              PopupMenuItem<_Action>(value: _Action.edit, child: Text('Modifier la dette')),
              PopupMenuItem<_Action>(value: _Action.delete, child: Text('Supprimer la dette')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncControlProvider).syncNow(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            if (customer != null)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push(Routes.customer(customer.customer.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: <Widget>[
                    AppAvatar(customer.customer.name, radius: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(customer.customer.name, style: theme.textTheme.titleMedium)),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(children: <Widget>[
                      Expanded(child: DebtStatusBadge(view)),
                      if (view.pendingSync) const PendingSyncIcon(size: 20),
                    ]),
                    const SizedBox(height: 12),
                    Text(settled ? 'Montant payé' : 'Reste à payer', style: theme.textTheme.labelLarge),
                    MoneyText(
                      settled ? debt.amount : view.remaining,
                      color: settled ? colors.paid : null,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: 'Remboursé à ${(progress * 100).round()} pour cent',
                      child: ExcludeSemantics(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(value: progress, minHeight: 10, color: colors.paid),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('${formatMoney(view.paid)} payés sur ${formatMoney(debt.amount)}', style: theme.textTheme.bodyMedium),
                    const Divider(height: 28),
                    _Fact(icon: Icons.sell_outlined, label: 'Catégorie', value: debt.category),
                    if ((debt.reason ?? '').isNotEmpty) _Fact(icon: Icons.notes, label: 'Motif', value: debt.reason!),
                    _Fact(icon: Icons.calendar_today_outlined, label: 'Créée le', value: formatDate(debt.createdAt)),
                    if (debt.dueDate != null)
                      _Fact(
                        icon: Icons.event,
                        label: 'Échéance',
                        value: '${formatDate(debt.dueDate!)} (${formatRelativeDays(debt.dueDate!, ref.read(clockProvider)())})',
                        valueColor: view.isOverdue ? colors.overdue : null,
                      ),
                  ],
                ),
              ),
            ),
            if (!settled) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : () => _addPayment(view),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Enregistrer un paiement'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _remind(view, customer),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Relancer le client'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _requestMomo(view),
                icon: const Icon(Icons.phone_android),
                label: const Text('Demander un paiement Mobile Money'),
              ),
              if (view.pendingSync)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Cette dette n\'est pas encore envoyée au serveur : la relance par Carné et Mobile Money seront disponibles après la synchronisation.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            const SectionTitle('Paiements reçus'),
            if (view.payments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('Aucun paiement pour le moment.', style: theme.textTheme.bodyMedium),
              )
            else
              for (final payment in (List<Payment>.of(view.payments)..sort((a, b) => b.paidAt.compareTo(a.paidAt))))
                _PaymentTile(payment, onDelete: () => _deletePayment(payment)),
          ],
        ),
      ),
    );
  }

  // ---- Actions ----

  Future<void> _onAction(DebtView view, _Action action) async {
    switch (action) {
      case _Action.edit:
        await context.push(Routes.debtEdit(view.debt.id));
      case _Action.delete:
        final n = view.payments.length;
        final ok = await confirm(
          context,
          title: 'Supprimer cette dette ?',
          message: n == 0
              ? 'La dette de ${formatMoney(view.debt.amount)} sera supprimée.'
              : 'La dette de ${formatMoney(view.debt.amount)} et ses $n paiement${n > 1 ? 's' : ''} seront supprimés. Cette action est définitive.',
          confirmLabel: 'Supprimer',
          destructive: true,
        );
        if (!ok || !mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        ref.read(repositoryProvider).deleteDebt(view.debt.id);
        context.pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Dette supprimée')));
    }
  }

  Future<void> _addPayment(DebtView view) async {
    final saved = await showPaymentSheet(context, view);
    if (!saved || !mounted) return;
    final after = ref.read(debtByIdProvider(view.debt.id));
    showSnack(context, after != null && after.status == DebtStatus.paid ? 'Dette soldée, bravo !' : 'Paiement enregistré');
  }

  Future<void> _deletePayment(Payment payment) async {
    final ok = await confirm(
      context,
      title: 'Supprimer ce paiement ?',
      message: 'Le paiement de ${formatMoney(payment.amount)} sera retiré et le solde de la dette augmentera d\'autant.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok || !mounted) return;
    ref.read(repositoryProvider).deletePayment(payment.id);
    showSnack(context, 'Paiement supprimé');
  }

  Future<void> _remind(DebtView view, CustomerView? customer) async {
    if (customer == null) return;
    final session = ref.read(sessionProvider);
    final businessName = session is SignedIn ? session.profile.businessName : 'votre commerçant';
    final message = reminderMessage(
      customerName: customer.customer.name,
      businessName: businessName,
      remaining: view.remaining,
    );
    final phone = customer.customer.phone;
    final choice = await showModalBottomSheet<_ReminderChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Relancer ${customer.customer.name}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('SMS envoyé par Carné'),
              subtitle: Text(view.pendingSync ? 'Disponible après la synchronisation de cette dette' : 'Nécessite une connexion'),
              enabled: !view.pendingSync,
              onTap: () => Navigator.of(context).pop(_ReminderChoice.serverSms),
            ),
            ListTile(
              leading: const Icon(Icons.message_outlined),
              title: const Text('SMS depuis mon téléphone'),
              subtitle: const Text('Ouvre votre messagerie avec le message prêt'),
              onTap: () => Navigator.of(context).pop(_ReminderChoice.deviceSms),
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('WhatsApp'),
              subtitle: const Text('Ouvre WhatsApp avec le message prêt'),
              onTap: () => Navigator.of(context).pop(_ReminderChoice.whatsapp),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _ReminderChoice.serverSms:
        await _guarded(() async {
          final result = await ref.read(backendApiProvider).sendReminder(view.debt.id, ReminderChannel.sms);
          if (mounted) {
            showSnack(context, result.sent ? 'SMS de relance envoyé' : 'L\'envoi du SMS a échoué. Réessayez plus tard ou utilisez votre téléphone.');
          }
        });
      case _ReminderChoice.deviceSms:
        await _openLink(smsUri(phone, text: message), 'Numéro de téléphone invalide.');
      case _ReminderChoice.whatsapp:
        await _openLink(whatsappUri(phone, text: message), 'Pour utiliser WhatsApp, ajoutez l\'indicatif du pays au numéro du client (par ex. +229).');
    }
  }

  Future<void> _openLink(Uri? uri, String unavailable) async {
    if (uri == null) {
      showSnack(context, unavailable);
      return;
    }
    final opened = await ref.read(urlOpenerProvider).open(uri);
    if (!opened && mounted) showSnack(context, 'Aucune application ne peut ouvrir ce lien.');
  }

  Future<void> _requestMomo(DebtView view) async {
    if (view.pendingSync) {
      showSnack(context, 'Cette dette n\'est pas encore synchronisée. Réessayez dans un instant.');
      return;
    }
    final ok = await confirm(
      context,
      title: 'Demander un paiement Mobile Money ?',
      message: 'Le client recevra une demande de paiement de ${formatMoney(view.remaining)} sur son téléphone.',
      confirmLabel: 'Envoyer la demande',
    );
    if (!ok || !mounted) return;
    await _guarded(() async {
      final result = await ref.read(backendApiProvider).requestMobileMoneyPayment(view.debt.id);
      if (mounted) showSnack(context, result.message);
    });
  }

  /// Exécute une action réseau en bloquant les doubles appuis et en traduisant les erreurs.
  Future<void> _guarded(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

enum _Action { edit, delete }

enum _ReminderChoice { serverSms, deviceSms, whatsapp }

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value, this.valueColor});

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18),
            const SizedBox(width: 10),
            // Un seul texte (libellé + valeur) : il passe à la ligne au lieu de déborder.
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: '$label : '),
                    TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w600, color: valueColor)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile(this.payment, {required this.onDelete});

  final Payment payment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(payment.method == PaymentMethod.momo ? Icons.phone_android : Icons.payments_outlined),
          title: MoneyText(payment.amount, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text('${payment.method.label} · ${formatDate(payment.paidAt)}'),
          trailing: IconButton(
            tooltip: 'Supprimer ce paiement',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ),
      );
}
