import 'package:flutter_test/flutter_test.dart';
import 'package:ardoiz/domain/models/debt_status.dart';

void main() {
  group('debtStatusFromString', () {
    test('convertit PAID en DebtStatus.paid', () {
      expect(debtStatusFromString('PAID'), DebtStatus.paid);
    });

    test('convertit PARTIAL en DebtStatus.partial', () {
      expect(debtStatusFromString('PARTIAL'), DebtStatus.partial);
    });

    test('convertit toute autre valeur en DebtStatus.pending', () {
      expect(debtStatusFromString('PENDING'), DebtStatus.pending);
      expect(debtStatusFromString('inconnu'), DebtStatus.pending);
    });
  });

  group('debtStatusToString', () {
    test('est l\'inverse exact de debtStatusFromString pour les valeurs connues', () {
      for (final status in DebtStatus.values) {
        final serialized = debtStatusToString(status);
        expect(debtStatusFromString(serialized), status);
      }
    });
  });
}
