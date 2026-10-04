import 'text.dart';

/// Lien d'appel : le « + » initial est conservé, tout le reste est réduit aux chiffres.
Uri? phoneCallUri(String phone) {
  final digits = digitsOnly(phone);
  if (digits.length < 6) return null;
  return Uri(scheme: 'tel', path: phone.trim().startsWith('+') ? '+$digits' : digits);
}

/// Lien WhatsApp. WhatsApp exige un numéro international : sans indicatif
/// (« + » ou « 00 » initial) on ne devine pas le pays, on renvoie null.
Uri? whatsappUri(String phone, {String? text}) {
  final trimmed = phone.trim();
  final digits = digitsOnly(trimmed);
  final String international;
  if (trimmed.startsWith('+')) {
    international = digits;
  } else if (digits.startsWith('00')) {
    international = digits.substring(2);
  } else {
    return null;
  }
  if (international.length < 8 || international.length > 15) return null;
  // Encodage strict (%20, pas « + » réservé aux formulaires) : sans ambiguïté pour le destinataire.
  return Uri(
    scheme: 'https',
    host: 'wa.me',
    path: '/$international',
    query: text == null ? null : 'text=${Uri.encodeComponent(text)}',
  );
}

/// SMS écrit depuis le téléphone (application de messagerie), message pré-rempli.
Uri? smsUri(String phone, {String? text}) {
  final call = phoneCallUri(phone);
  if (call == null) return null;
  return Uri(
    scheme: 'sms',
    path: call.path,
    query: text == null ? null : 'body=${Uri.encodeComponent(text)}',
  );
}
