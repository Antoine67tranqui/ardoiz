/// Texte comparable pour la recherche : minuscules, sans accents (« Aïcha » = « aicha »).
String foldForSearch(String input) {
  const from = 'àáâäãåçèéêëìíîïñòóôöõùúûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString();
}

/// Chiffres seuls (comparaison de numéros de téléphone, lien WhatsApp).
String digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');
