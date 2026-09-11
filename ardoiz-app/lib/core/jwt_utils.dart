import 'dart:convert';

/// Decodage local (non verifie) du payload d'un JWT, utilise uniquement
/// pour recuperer l'identifiant utilisateur cote client. La verification
/// de signature/expiration reste entierement du ressort du backend.
Map<String, dynamic> decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return {};
  final normalized = base64Url.normalize(parts[1]);
  final payload = utf8.decode(base64Url.decode(normalized));
  return jsonDecode(payload) as Map<String, dynamic>;
}
