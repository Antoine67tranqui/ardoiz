import 'package:ardoiz/core/contact.dart';
import 'package:ardoiz/core/text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('phoneCallUri', () {
    test('garde le + et réduit le reste aux chiffres', () {
      expect(phoneCallUri('+229 01 67-00 11')?.toString(), 'tel:+2290167 0011'.replaceAll(' ', ''));
      expect(phoneCallUri('(01) 67 00 11')?.toString(), 'tel:01670011');
    });

    test('refuse un numéro trop court', () => expect(phoneCallUri('123'), isNull));
  });

  group('whatsappUri', () {
    test('numéro avec + : lien wa.me sans signe', () {
      expect(whatsappUri('+229 01 67 00 11 22')?.toString(), 'https://wa.me/229016700 1122'.replaceAll(' ', ''));
    });

    test('préfixe 00 équivaut à +', () {
      expect(whatsappUri('00229 0167001122')?.toString(), 'https://wa.me/2290167001122');
    });

    test('numéro local sans indicatif : refusé (le pays ne se devine pas)', () {
      expect(whatsappUri('0167001122'), isNull);
    });

    test('longueur hors norme (8 à 15 chiffres) : refusé', () {
      expect(whatsappUri('+1234567'), isNull);
      expect(whatsappUri('+1234567890123456'), isNull);
    });

    test('message pré-rempli correctement encodé', () {
      final uri = whatsappUri('+2290167001122', text: 'Bonjour & merci')!;
      expect(uri.queryParameters['text'], 'Bonjour & merci');
      expect(uri.toString(), contains('text=Bonjour%20%26%20merci'));
    });
  });

  group('texte', () {
    test('foldForSearch retire accents, ligatures et casse', () {
      expect(foldForSearch('Aïcha ÉLÈVE Œuvre Çà'), 'aicha eleve ouvre ca');
    });

    test('digitsOnly', () => expect(digitsOnly('+229 (01) 67-00'), '2290167 00'.replaceAll(' ', '')));
  });
}
