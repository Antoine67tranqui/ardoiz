import 'package:ardoiz/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('additionne exactement : 0,10 + 0,70 = 0,80 (impossible en flottant)', () {
      const a = Money.fromCents(10);
      const b = Money.fromCents(70);
      expect(a + b, const Money.fromCents(80));
      expect(0.1 + 0.7 == 0.8, isFalse); // le piège évité
    });

    test('fromJson arrondit sans dérive : 1250.5, 0.07, 19.99', () {
      expect(Money.fromJson(1250.5).cents, 125050);
      expect(Money.fromJson(0.07).cents, 7);
      expect(Money.fromJson(19.99).cents, 1999);
      expect(Money.fromJson(5000).cents, 500000);
    });

    test('toJson renvoie un entier quand c\'est possible, sinon 2 décimales exactes', () {
      expect(const Money.fromCents(500000).toJson(), 5000);
      expect(const Money.fromCents(125050).toJson(), 1250.5);
      expect(Money.fromJson(19.99).toJson(), 19.99);
    });

    group('tryParse (saisie utilisateur)', () {
      test('accepte les formats courants', () {
        expect(Money.tryParse('2500'), const Money.fromCents(250000));
        expect(Money.tryParse('1 250'), const Money.fromCents(125000));
        expect(Money.tryParse('1 250,50'), const Money.fromCents(125050));
        expect(Money.tryParse('1250.5'), const Money.fromCents(125050));
        expect(Money.tryParse('0,5'), const Money.fromCents(50));
        expect(Money.tryParse('  300  '), const Money.fromCents(30000));
      });

      test('refuse le reste', () {
        for (final bad in ['', ' ', 'abc', '-5', '1,234', '1.2.3', '12a', '1,', ',5', '--', '1 2 a']) {
          expect(Money.tryParse(bad), isNull, reason: 'devrait refuser "$bad"');
        }
      });

      test('borne au maximum accepté par le serveur', () {
        expect(Money.tryParse('9999999999'), Money.max);
        expect(Money.tryParse('9999999999,99'), isNull);
        expect(Money.tryParse('10000000000'), isNull);
        expect(Money.tryParse('99999999999999999999'), isNull);
      });
    });

    test('compare, somme, borne à zéro', () {
      expect(const Money.fromCents(5) < const Money.fromCents(6), isTrue);
      expect(const Money.fromCents(6) >= const Money.fromCents(6), isTrue);
      expect(Money.sum(const [Money.fromCents(1), Money.fromCents(2)]), const Money.fromCents(3));
      expect(Money.sum(const []), Money.zero);
      expect((Money.zero - const Money.fromCents(5)).clampedAtZero, Money.zero);
      expect(const Money.fromCents(5).clampedAtZero, const Money.fromCents(5));
      expect(Money.zero.isZero, isTrue);
      expect(const Money.fromCents(1).isPositive, isTrue);
      expect({Money.fromCents(int.parse('1')), Money.fromCents(int.parse('1'))}, hasLength(1));
    });
  });
}
