import 'package:ardoiz/core/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiConfig.validate', () {
    test('accepte https partout, http seulement hors production', () {
      expect(ApiConfig.validate('https://api.carne.app/api/v1', release: true), isNull);
      expect(ApiConfig.validate('https://api.carne.app/api/v1', release: false), isNull);
      expect(ApiConfig.validate('http://10.0.2.2:3000/api/v1', release: false), isNull);
    });

    test('refuse http en production : jetons et données financières jamais en clair', () {
      expect(ApiConfig.validate('http://api.carne.app/api/v1', release: true), contains('HTTPS'));
    });

    test('refuse les adresses invalides ou d\'un autre protocole', () {
      for (final bad in ['', 'api.carne.app', 'ftp://api.carne.app', 'https://', '://x']) {
        expect(ApiConfig.validate(bad, release: false), isNotNull, reason: '"$bad"');
      }
    });
  });
}
