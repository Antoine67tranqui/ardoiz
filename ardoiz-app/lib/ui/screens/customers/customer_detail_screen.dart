import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/contact.dart';
import '../../../core/formatters.dart';
import '../../../core/text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models.dart';
import '../../widgets/common.dart';

/// Fiche d'un client : coordonnées, solde, dettes (en cours puis soldées).
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(customersProvider).hasValue;
    final view = ref.watch(customerByIdProvider(customerId));
    if (view == null) {
      return Scaffold(
        appBar: AppBar(),
        body: loaded
            ? const EmptyState(icon: Icons.person_off_outlined, title: 'Client introuvable', message: 'Ce client a été supprimé.')
            : const Center(child: CircularProgressIndicator()),
      );
    }

    final open = view.debts.where((d) => d.status != DebtStatus.paid).toList();
    final settled = view.debts.where((d) => d.status == DebtStatus.paid).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(view.customer.name, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          PopupMenuButton<_Action>(
            tooltip: 'Plus d\'actions',
            onSelected: (action) => _onAction(context, ref, view, action),
            itemBuilder: (context) => <PopupMenuEntry<_Action>>[
              PopupMenuItem<_Action>(value: _Action.edit, child: Text(view.customer.isSupplier ? 'Modifier le fournisseur' : 'Modifier le client')),
              const PopupMenuItem<_Action>(value: _Action.export, child: Text('Exporter les données de cette personne')),
              PopupMenuItem<_Action>(value: _Action.delete, child: Text(view.customer.isSupplier ? 'Supprimer le fournisseur' : 'Supprimer le client')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.debtNew(customerId)),
        icon: const Icon(Icons.add),
        label: Text(view.customer.isSupplier ? 'Nouvel achat à crédit' : 'Nouvelle dette'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          _Header(view),
          const SizedBox(height: 12),
          _BalanceCard(view),
          if (open.isEmpty && settled.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Aucune dette',
                message: view.customer.isSupplier
                    ? 'Notez ce que vous devez à ce fournisseur avec « Nouvel achat à crédit ».'
                    : 'Notez ce que ce client vous doit avec « Nouvelle dette ».',
              ),
            ),
          if (open.isNotEmpty) ...<Widget>[
            const SectionTitle('En cours'),
            for (final debt in open) _DebtTile(debt),
          ],
          if (settled.isNotEmpty) ...<Widget>[
            const SectionTitle('Soldées'),
            for (final debt in settled) _DebtTile(debt),
          ],
        ],
      ),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, CustomerView view, _Action action) async {
    switch (action) {
      case _Action.edit:
        await context.push(Routes.customerEdit(view.customer.id));
      case _Action.export:
        try {
          final fileName = 'carne-${view.customer.isSupplier ? 'fournisseur' : 'client'}-${foldForFileName(view.customer.name)}.json';
          final file = await ref.read(backendApiProvider).exportPartyData(view.customer.id, fileName: fileName);
          await ref.read(fileSharerProvider).share(fileName: file.fileName, bytes: file.bytes, mimeType: 'application/json');
        } on Object catch (e) {
          if (context.mounted) showSnack(context, view.pendingSync ? 'Cette fiche n\'est pas encore synchronisée : réessayez dans un instant.' : describeError(e));
        }
      case _Action.delete:
        final debtCount = view.debts.length;
        final ok = await confirm(
          context,
          title: 'Supprimer ${view.customer.name} ?',
          message: debtCount == 0
              ? 'Ce client sera supprimé.'
              : 'Ce client, ses $debtCount dette${debtCount > 1 ? 's' : ''} et tous leurs remboursements seront supprimés. Cette action est définitive.',
          confirmLabel: 'Supprimer',
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        ref.read(repositoryProvider).deleteCustomer(view.customer.id);
        context.pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Client supprimé')));
    }
  }
}

enum _Action { edit, export, delete }

class _Header extends ConsumerWidget {
  const _Header(this.view);

  final CustomerView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final phone = view.customer.phone;
    return Row(
      children: <Widget>[
        AppAvatar(view.customer.name, radius: 30),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(view.customer.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(formatPhone(phone), style: theme.textTheme.bodyMedium),
              Text(
                '${view.customer.isSupplier ? 'Fournisseur' : 'Client'} depuis le ${formatDate(view.customer.createdAt)}',
                style: theme.textTheme.bodySmall,
              ),
              if (view.customer.reminderOptOut)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: <Widget>[
                    Icon(Icons.notifications_off_outlined, size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 4),
                    Flexible(child: Text('Refuse les relances', style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600))),
                  ]),
                ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Appeler ${view.customer.name}',
          icon: const Icon(Icons.call),
          onPressed: () => _open(context, ref, phoneCallUri(phone), 'Impossible de composer ce numéro.'),
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          tooltip: 'Écrire sur WhatsApp à ${view.customer.name}',
          icon: const Icon(Icons.chat),
          onPressed: () => _open(
            context,
            ref,
            whatsappUri(phone),
            'Pour utiliser WhatsApp, ajoutez l\'indicatif du pays au numéro (par ex. +229).',
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, Uri? uri, String unavailable) async {
    if (uri == null) {
      showSnack(context, unavailable);
      return;
    }
    final opened = await ref.read(urlOpenerProvider).open(uri);
    if (!opened && context.mounted) showSnack(context, 'Aucune application ne peut ouvrir ce lien.');
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard(this.view);

  final CustomerView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.statusColors;
    final limit = view.customer.creditLimit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(view.customer.isSupplier ? 'Reste à payer' : 'Solde dû', style: theme.textTheme.labelLarge),
            MoneyText(
              view.outstanding,
              color: view.isUpToDate ? colors.paid : null,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (view.hasOverdue) ...<Widget>[
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Icon(Icons.warning_amber_rounded, size: 18, color: colors.overdue),
                const SizedBox(width: 6),
                Text('Retard de ${view.maxOverdueDays} jour${view.maxOverdueDays > 1 ? 's' : ''}', style: TextStyle(color: colors.overdue, fontWeight: FontWeight.w600)),
              ]),
            ],
            if (limit != null) ...<Widget>[
              const SizedBox(height: 8),
              Row(children: <Widget>[
                if (view.creditLimitExceeded) ...<Widget>[Icon(Icons.block, size: 18, color: colors.overdue), const SizedBox(width: 6)],
                Flexible(
                  child: Text(
                    view.creditLimitExceeded
                        ? 'Plafond de ${formatMoney(limit)} dépassé'
                        : 'Plafond de crédit : ${formatMoney(limit)}',
                    style: TextStyle(color: view.creditLimitExceeded ? colors.overdue : null, fontWeight: view.creditLimitExceeded ? FontWeight.w600 : null),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile(this.view);

  final DebtView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final debt = view.debt;
    final title = (debt.reason ?? '').isEmpty ? debt.category : debt.reason!;
    final settled = view.status == DebtStatus.paid;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(Routes.debt(debt.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium)),
                  if (view.pendingSync) ...<Widget>[const SizedBox(width: 6), const PendingSyncIcon()],
                  const SizedBox(width: 8),
                  AmountBox(settled ? debt.amount : view.remaining, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                settled
                    ? 'Montant initial · ${formatDate(debt.createdAt)}'
                    : 'Reste à payer sur ${formatMoney(debt.amount)} · ${formatDate(debt.createdAt)}',
                style: theme.textTheme.bodySmall,
              ),
              if (debt.dueDate != null && !settled) Text('Échéance : ${formatDate(debt.dueDate!)}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              DebtStatusBadge(view),
            ],
          ),
        ),
      ),
    );
  }
}
