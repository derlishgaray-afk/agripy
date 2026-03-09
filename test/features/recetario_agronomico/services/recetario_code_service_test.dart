import 'package:agripy/features/recetario_agronomico/services/recetario_code_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecetarioCodeService.formatRecetarioCode', () {
    test('formatea con pad a 6 digitos', () {
      expect(
        RecetarioCodeService.formatRecetarioCode(2026, 1),
        'R-2026-000001',
      );
      expect(
        RecetarioCodeService.formatRecetarioCode(2026, 124),
        'R-2026-000124',
      );
      expect(
        RecetarioCodeService.formatRecetarioCode(2026, 999999),
        'R-2026-999999',
      );
    });
  });
}
