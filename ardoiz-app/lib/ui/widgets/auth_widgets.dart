import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/brand.dart';

/// Pastille de marque (logo provisoire : un carnet).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Brand.forest,
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Icon(Icons.menu_book_rounded, color: Colors.white, size: size * 0.56),
        ),
      );
}

/// Coque commune des écrans d'accès : défilement, largeur bornée, marque.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, this.subtitle, required this.children, this.showBack = true});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: showBack ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 56)),
                  const SizedBox(height: 24),
                  Semantics(header: true, child: Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(subtitle!, style: theme.textTheme.bodyLarge),
                  ],
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Message d'erreur de formulaire, annoncé par les lecteurs d'écran.
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline, color: scheme.error, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}

/// Champ de saisie numérique (PIN : masqué, code SMS : visible).
class DigitsField extends StatelessWidget {
  const DigitsField({
    super.key,
    required this.controller,
    required this.label,
    required this.length,
    required this.validator,
    this.obscure = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final int length;
  final String? Function(String?) validator;
  final bool obscure;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;
  final bool autofocus;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => TextFormField(
        key: fieldKey,
        controller: controller,
        autofocus: autofocus,
        obscureText: obscure,
        keyboardType: TextInputType.number,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(length),
        ],
        style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w600),
        decoration: InputDecoration(labelText: label, counterText: ''),
        validator: validator,
        onFieldSubmitted: (_) => onSubmitted?.call(),
      );
}
