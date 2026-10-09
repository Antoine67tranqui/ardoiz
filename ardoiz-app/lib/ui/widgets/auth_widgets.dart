import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/brand.dart';

/// Logo Carné : un carnet à anneaux avec une coche, sur fond vert. Même dessin
/// que `brand/logo-mark.svg` (mêmes coordonnées, base 1024).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(size: Size.square(size), painter: const CarneLogoPainter()),
      );
}

/// Logo de l'éditeur, posé sur une carte blanche : ses lettres bleu nuit restent lisibles en thème sombre.
class PublisherLogo extends StatelessWidget {
  const PublisherLogo({super.key, this.width = 96});

  final double width;

  static const String asset = 'assets/images/civora-logo.png';
  static const String label = 'Logo CIVORA Conseil et Solutions';

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(width * 0.12)),
        child: Padding(
          padding: EdgeInsets.all(width * 0.06),
          child: Image.asset(asset, width: width, semanticLabel: label, filterQuality: FilterQuality.medium),
        ),
      );
}

class CarneLogoPainter extends CustomPainter {
  const CarneLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 1024, size.height / 1024);
    final fill = Paint()..style = PaintingStyle.fill;

    RRect rrect(double x, double y, double w, double h, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

    canvas.drawRRect(rrect(0, 0, 1024, 1024, 230), fill..color = Brand.forest);
    canvas.drawRRect(rrect(262, 196, 500, 632, 56), fill..color = Brand.paper);
    canvas.drawRRect(rrect(262, 196, 104, 632, 56), fill..color = Brand.gold);
    canvas.drawRect(const Rect.fromLTWH(318, 196, 48, 632), fill);
    fill.color = Brand.forest;
    for (final y in <double>[330, 512, 694]) {
      canvas.drawCircle(Offset(314, y), 26, fill);
    }
    final check = Path()
      ..moveTo(452, 470)
      ..lineTo(548, 566)
      ..lineTo(690, 392);
    canvas.drawPath(
      check,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 56
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Brand.forest,
    );
    fill.color = Brand.logoLine;
    canvas.drawRRect(rrect(452, 650, 238, 26, 13), fill);
    canvas.drawRRect(rrect(452, 716, 160, 26, 13), fill);
  }

  @override
  bool shouldRepaint(CarneLogoPainter oldDelegate) => false;
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
