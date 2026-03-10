import 'funcion_priority.dart';

class MixValidationItem {
  const MixValidationItem({
    required this.productName,
    this.formulation,
    this.type,
    this.funcion,
  });

  final String productName;
  final String? formulation;
  final String? type;
  final String? funcion;
}

class MixValidationResult {
  const MixValidationResult({required this.warnings});

  final List<String> warnings;

  bool get hasWarnings => warnings.isNotEmpty;
}

class MixValidationService {
  const MixValidationService();

  static const Set<String> _solidFormulations = <String>{'wp', 'wg', 'sp'};
  static const Set<String> _waterConditioningFunctions = <String>{
    'corrector_ph',
    'secuestrante_dureza',
    'acondicionador_agua',
  };

  MixValidationResult validateMix(List<MixValidationItem> items) {
    final selected = items
        .where((item) => item.productName.trim().isNotEmpty)
        .toList(growable: false);
    if (selected.isEmpty) {
      return const MixValidationResult(warnings: <String>[]);
    }

    var hasSolid = false;
    var hasOil = false;
    var hasWaterConditioner = false;
    var hasAntiDrift = false;
    var hasAntiFoam = false;
    final distinctProducts = <String>{};

    for (final item in selected) {
      distinctProducts.add(item.productName.trim().toLowerCase());
      final formulation = (item.formulation ?? '').trim().toLowerCase();
      if (_solidFormulations.contains(formulation)) {
        hasSolid = true;
      }
      if (formulation == 'aceite') {
        hasOil = true;
      }

      final functionKey = normalizeFuncionKey(item.funcion);
      final type = (item.type ?? '').trim().toLowerCase();
      if (type == 'coadyuvante' &&
          _waterConditioningFunctions.contains(functionKey)) {
        hasWaterConditioner = true;
      }
      if (functionKey == 'antideriva') {
        hasAntiDrift = true;
      }
      if (functionKey == 'antiespumante') {
        hasAntiFoam = true;
      }
    }

    final warnings = <String>[];
    final seen = <String>{};
    void addWarning(String value) {
      final key = value.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) {
        return;
      }
      seen.add(key);
      warnings.add(value);
    }

    if (hasSolid) {
      addWarning(
        'Se recomienda premezclar formulaciones solidas antes de cargar al tanque.',
      );
    }
    if (hasOil) {
      addWarning('Agregar aceites al final de la carga.');
    }
    if (hasWaterConditioner) {
      addWarning(
        'Agregar acondicionadores de agua al inicio de la preparacion del tanque.',
      );
    }
    if (hasAntiDrift) {
      addWarning(
        'Verificar el momento recomendado de incorporacion del antideriva segun indicacion tecnica.',
      );
    }
    if (hasAntiFoam) {
      addWarning(
        'Usar antiespumante segun necesidad operativa y recomendacion del fabricante.',
      );
    }
    if (distinctProducts.length >= 4) {
      addWarning(
        'Se recomienda realizar prueba de jarra antes de preparar la mezcla.',
      );
    }
    if (distinctProducts.length >= 6) {
      addWarning(
        'Mezcla compleja: extremar control de compatibilidad fisica y mantener agitacion constante.',
      );
    }
    if (hasOil && hasSolid) {
      addWarning(
        'La mezcla contiene solidos y aceites. Verificar compatibilidad y respetar estrictamente el orden de carga.',
      );
    }
    if (hasWaterConditioner && hasSolid) {
      addWarning(
        'Agregar primero el acondicionador de agua y luego incorporar formulaciones solidas con agitacion.',
      );
    }

    return MixValidationResult(warnings: List.unmodifiable(warnings));
  }
}
