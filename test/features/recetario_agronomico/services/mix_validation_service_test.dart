import 'package:agripy/features/recetario_agronomico/services/mix_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MixValidationService', () {
    const service = MixValidationService();

    test('considera GR/SG/DT/RB como formulaciones solidas', () {
      final result = service.validateMix(const <MixValidationItem>[
        MixValidationItem(productName: 'P1', formulation: 'GR'),
        MixValidationItem(productName: 'P2', formulation: 'SG'),
        MixValidationItem(productName: 'P3', formulation: 'DT'),
        MixValidationItem(productName: 'P4', formulation: 'RB'),
      ]);

      expect(
        result.warnings.any(
          (warning) => warning.toLowerCase().contains('formulaciones solidas'),
        ),
        isTrue,
      );
    });

    test('no marca CS/ME/FS como solidas', () {
      final result = service.validateMix(const <MixValidationItem>[
        MixValidationItem(productName: 'P1', formulation: 'CS'),
        MixValidationItem(productName: 'P2', formulation: 'ME'),
        MixValidationItem(productName: 'P3', formulation: 'FS'),
      ]);

      expect(
        result.warnings.any(
          (warning) => warning.toLowerCase().contains('formulaciones solidas'),
        ),
        isFalse,
      );
    });
  });
}
