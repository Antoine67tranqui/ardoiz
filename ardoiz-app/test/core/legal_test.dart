import 'dart:io';

import 'package:ardoiz/core/config.dart';
import 'package:ardoiz/core/legal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la version des conditions de l\'application est celle du serveur (sinon plus aucune inscription possible)', () {
    final file = File('../ardoiz-backend/src/common/legal.ts');
    if (!file.existsSync()) {
      markTestSkipped('backend absent de cette copie du dépôt');
      return;
    }
    final server = RegExp(r"CURRENT_TERMS_VERSION = '([^']+)'").firstMatch(file.readAsStringSync())!.group(1);
    expect(Legal.termsVersion, server);
  });

  test('adresses des documents publics : dérivées du site, absentes si non configuré', () {
    expect(Legal.privacyUri('https://carne.example/')?.toString(), 'https://carne.example/confidentialite.html');
    expect(Legal.termsUri('https://carne.example')?.toString(), 'https://carne.example/conditions.html');
    expect(Legal.mentionsUri('https://carne.example/')?.toString(), 'https://carne.example/mentions-legales.html');
    expect(Legal.privacyUri(''), isNull);
  });

  group('adresse du site', () {
    test('obligatoire et en https pour une version de production, facultative en développement', () {
      expect(ApiConfig.validateWebsite('', release: true), isNotNull);
      expect(ApiConfig.validateWebsite('', release: false), isNull);
      expect(ApiConfig.validateWebsite('http://carne.example', release: true), isNotNull);
      expect(ApiConfig.validateWebsite('https://carne.example', release: true), isNull);
      expect(ApiConfig.validateWebsite('pas une adresse', release: false), isNotNull);
    });
  });
}
