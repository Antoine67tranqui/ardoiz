import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/remote/api_exceptions.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../domain/models.dart';

/// Message d'erreur lisible par un commerçant, jamais un nom de classe ni une trace.
String describeError(Object error) {
  if (error is DomainException) return error.message;
  if (error is NetworkException) return 'Pas de connexion au serveur. Vérifiez votre réseau et réessayez.';
  if (error is UnauthorizedException) return error.message;
  if (error is ServerException) {
    return error.isFeatureUnavailable ? error.message : 'Le serveur est momentanément indisponible. Réessayez dans un instant.';
  }
  if (error is RejectedException) return error.message;
  if (error is ApiException) return error.message;
  return 'Une erreur inattendue est survenue. Réessayez.';
}

void showSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Demande une confirmation ; renvoie vrai si l'utilisateur confirme.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: destructive ? Theme.of(context).colorScheme.error : null,
            foregroundColor: destructive ? Theme.of(context).colorScheme.onError : null,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Montant en FCFA, chiffres de largeur fixe.
class MoneyText extends StatelessWidget {
  const MoneyText(this.amount, {super.key, this.style, this.color});

  final Money amount;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyLarge;
    return Text(
      formatMoney(amount),
      style: base?.copyWith(color: color, fontFeatures: AppTheme.tabularFigures),
    );
  }
}

/// Montant placé dans une ligne : il garde sa lisibilité en se réduisant au lieu
/// de déborder (grands montants, texte agrandi), et ne prend jamais plus de
/// [maxFraction] de la largeur de l'écran.
class AmountBox extends StatelessWidget {
  const AmountBox(this.amount, {super.key, this.style, this.color, this.maxFraction = 0.45});

  final Money amount;
  final TextStyle? style;
  final Color? color;
  final double maxFraction;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * maxFraction),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: MoneyText(amount, style: style, color: color),
        ),
      );
}

class AppAvatar extends StatelessWidget {
  const AppAvatar(this.name, {super.key, this.radius = 22});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primary.withValues(alpha: 0.12),
        foregroundColor: scheme.primary,
        child: Text(initials(name), style: TextStyle(fontWeight: FontWeight.w700, fontSize: radius * 0.8)),
      ),
    );
  }
}

/// État d'une dette : toujours un texte ET une icône (jamais la couleur seule).
class DebtStatusBadge extends StatelessWidget {
  const DebtStatusBadge(this.debt, {super.key});

  final DebtView debt;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final (IconData icon, String label, Color color) = switch (debt.status) {
      _ when debt.isOverdue => (Icons.warning_amber_rounded, 'En retard de ${debt.overdueDays} j', colors.overdue),
      DebtStatus.paid => (Icons.check_circle_outline, 'Soldée', colors.paid),
      DebtStatus.partial => (Icons.timelapse, 'Partielle', colors.partial),
      DebtStatus.pending => (Icons.schedule, 'À payer', colors.pending),
    };
    return Semantics(
      label: 'Statut : $label',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Flexible(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indique qu'une saisie n'est pas encore envoyée au serveur.
class PendingSyncIcon extends StatelessWidget {
  const PendingSyncIcon({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'En attente d\'envoi',
        child: Icon(Icons.cloud_upload_outlined, size: size, color: context.statusColors.pending),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: theme.colorScheme.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            if (action != null) ...<Widget>[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

/// Bouton principal qui affiche une progression et ignore les doubles appuis.
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );
    return Semantics(
      button: true,
      label: busy ? '$label, en cours' : label,
      child: FilledButton(onPressed: busy ? null : onPressed, child: child),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                header: true,
                child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            ?trailing,
          ],
        ),
      );
}
