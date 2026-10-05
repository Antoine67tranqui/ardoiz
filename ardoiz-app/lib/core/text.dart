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

/// Nom utilisable dans un nom de fichier : minuscules sans accents, tirets, 40 caractères au plus.
String foldForFileName(String input) {
  final folded = foldForSearch(input).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  final cut = folded.length > 40 ? folded.substring(0, 40) : folded;
  return cut.isEmpty ? 'sans-nom' : cut;
}
