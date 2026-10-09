import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/formatters.dart';
import '../../../core/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/customer_filter.dart';
import '../../../domain/models.dart';
import '../../widgets/common.dart';

/// Liste des clients : total à encaisser, recherche, filtre « en retard », tri.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key, this.kind = PartyKind.client});

  /// Clients (ce qu'on me doit) ou fournisseurs (ce que je dois).
  final PartyKind kind;

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _overdueOnly = false;
  CustomerSort _sort = CustomerSort.name;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(partiesProvider(widget.kind));
    final supplier = widget.kind == PartyKind.supplier;
    return Scaffold(
      appBar: AppBar(
        title: Text(supplier ? 'Fournisseurs' : 'Clients'),
        actions: <Widget>[
          PopupMenuButton<CustomerSort>(
            tooltip: 'Trier les clients',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => <PopupMenuEntry<CustomerSort>>[
              for (final sort in CustomerSort.values)
                CheckedPopupMenuItem<CustomerSort>(value: sort, checked: sort == _sort, child: Text(sort.label)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(supplier ? Routes.supplierNew : Routes.customerNew),
        icon: Icon(supplier ? Icons.local_shipping_outlined : Icons.person_add_alt_1),
        label: Text(supplier ? 'Nouveau fournisseur' : 'Nouveau client'),
      ),
      body: customers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Impossible de lire vos clients',
          message: describeError(error),
        ),
        data: _buildList,
      ),
    );
  }

  Widget _buildList(List<CustomerView> all) {
    if (all.isEmpty) return _FirstCustomerState(kind: widget.kind);

    final shown = filterCustomers(all, query: _query, overdueOnly: _overdueOnly, sort: _sort);
    final overdueCount = all.where((c) => c.hasOverdue).length;
    final total = Money.sum(all.map((c) => c.outstanding));

    return RefreshIndicator(
      onRefresh: () => ref.read(syncControlProvider).syncNow(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          _TotalCard(total: total, customerCount: all.length, kind: widget.kind),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.kind == PartyKind.supplier ? 'Rechercher un fournisseur' : 'Rechercher un nom ou un numéro',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: Text('En retard ($overdueCount)'),
              avatar: const Icon(Icons.warning_amber_rounded, size: 18),
              selected: _overdueOnly,
              onSelected: (value) => setState(() => _overdueOnly = value),
            ),
          ),
          const SizedBox(height: 4),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: EmptyState(
                icon: Icons.search_off,
                title: widget.kind == PartyKind.supplier ? 'Aucun fournisseur trouvé' : 'Aucun client trouvé',
                message: _overdueOnly && _query.isEmpty
                    ? (widget.kind == PartyKind.supplier ? 'Aucune dette fournisseur n\'est en retard.' : 'Aucun client n\'a de dette en retard. Bonne nouvelle !')
                    : 'Essayez un autre nom ou un autre numéro.',
              ),
            )
          else
            for (final view in shown) CustomerTile(view, onTap: () => context.push(Routes.customer(view.customer.id))),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total, required this.customerCount, required this.kind});

  final Money total;
  final int customerCount;
  final PartyKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final supplier = kind == PartyKind.supplier;
    final noun = supplier ? 'fournisseur' : 'client';
    final title = supplier ? 'Total à payer' : 'Total à encaisser';
    return Semantics(
      container: true,
      label: '$title : ${formatMoney(total)}, $customerCount $noun${customerCount > 1 ? 's' : ''}',
      child: ExcludeSemantics(
        child: Card(
          color: scheme.primary,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.85))),
                const SizedBox(height: 4),
                MoneyText(
                  total,
                  color: scheme.onPrimary,
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '$customerCount $noun${customerCount > 1 ? 's' : ''}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerTile extends StatelessWidget {
  const CustomerTile(this.view, {super.key, required this.onTap});

  final CustomerView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.statusColors;
    final upToDate = view.isUpToDate;
    final balanceColor = view.hasOverdue ? colors.overdue : (upToDate ? colors.paid : theme.colorScheme.onSurface);
    final subtitle = view.hasOverdue
        ? 'En retard de ${view.maxOverdueDays} j'
        : (upToDate ? 'À jour' : formatPhone(view.customer.phone));
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: <Widget>[
              AppAvatar(view.customer.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            view.customer.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (view.pendingSync) ...<Widget>[const SizedBox(width: 6), const PendingSyncIcon()],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        if (view.hasOverdue) ...<Widget>[
                          Icon(Icons.warning_amber_rounded, size: 16, color: colors.overdue),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(color: view.hasOverdue ? colors.overdue : null),
                          ),
                        ),
                        if (view.creditLimitExceeded) ...<Widget>[
                          const SizedBox(width: 8),
                          Icon(Icons.block, size: 16, color: colors.overdue, semanticLabel: 'Plafond dépassé'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AmountBox(
                view.outstanding,
                color: balanceColor,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirstCustomerState extends StatelessWidget {
  const _FirstCustomerState({required this.kind});

  final PartyKind kind;

  @override
  Widget build(BuildContext context) {
    if (kind == PartyKind.supplier) {
      return EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'Aucun fournisseur',
        message: 'Notez ici ce que vous devez à vos fournisseurs (achats à crédit) pour ne rien oublier de payer. '
            'Tout fonctionne sans connexion.',
        action: BusyButton(
          label: 'Ajouter mon premier fournisseur',
          icon: Icons.local_shipping_outlined,
          onPressed: () => context.push(Routes.supplierNew),
        ),
      );
    }
    return EmptyState(
      icon: Icons.menu_book_outlined,
      title: 'Votre carnet est vide',
      message: 'Ajoutez votre premier client, puis notez ce qu\'il vous doit. '
          'Tout fonctionne sans connexion et se synchronise dès que le réseau revient.',
      action: BusyButton(
        label: 'Ajouter mon premier client',
        icon: Icons.person_add_alt_1,
        onPressed: () => context.push(Routes.customerNew),
      ),
    );
  }
}
