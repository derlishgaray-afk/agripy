import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

String _collapseSpaces(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

String _stripAccents(String value) {
  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'Á': 'A',
    'À': 'A',
    'Ä': 'A',
    'Â': 'A',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'É': 'E',
    'È': 'E',
    'Ë': 'E',
    'Ê': 'E',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'Í': 'I',
    'Ì': 'I',
    'Ï': 'I',
    'Î': 'I',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'Ó': 'O',
    'Ò': 'O',
    'Ö': 'O',
    'Ô': 'O',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'Ú': 'U',
    'Ù': 'U',
    'Ü': 'U',
    'Û': 'U',
    'ñ': 'n',
    'Ñ': 'N',
  };
  var output = value;
  replacements.forEach((key, replacement) {
    output = output.replaceAll(key, replacement);
  });
  return output;
}

const List<String> productCatalogUnitOptions = <String>['Kg.', 'Lt.'];

const List<String> productCatalogTypeOptions = <String>[
  'herbicida',
  'fungicida',
  'insecticida',
  'coadyuvante',
  'fertilizante',
  'Otros',
];

const List<String> productCatalogFormulationOptions = <String>[
  'WP',
  'WG',
  'CS',
  'ME',
  'FS',
  'GR',
  'SG',
  'DT',
  'RB',
  'SC',
  'SE',
  'OD',
  'EC',
  'EW',
  'SL',
  'SP',
  'Coadyuvante',
  'Aceite',
  'Otro',
];

const List<String> productCatalogFunctionOptions = <String>[
  'ninguna',
  'corrector_ph',
  'secuestrante_dureza',
  'antideriva',
  'antiespumante',
  'adherente',
  'humectante',
  'penetrante',
  'acondicionador_agua',
  'otro',
];

String normalizeProductCommercialName(String value) {
  return _collapseSpaces(value).toUpperCase();
}

String normalizeProductCommercialNameKey(String value) {
  final compact = _collapseSpaces(value).toLowerCase();
  return _stripAccents(compact);
}

String? normalizeProductActiveIngredient(String? value) {
  final compact = _collapseSpaces(value ?? '');
  if (compact.isEmpty) {
    return null;
  }
  return compact;
}

String normalizeProductUnit(String? value) {
  return normalizeProductUnitWithRules(value, allowEmpty: false);
}

String normalizeProductUnitWithRules(
  String? value, {
  required bool allowEmpty,
}) {
  final raw = _stripAccents(_collapseSpaces(value ?? '')).toLowerCase();
  if (raw.isEmpty) {
    return allowEmpty ? '' : 'Lt.';
  }
  if (raw == 'kg' ||
      raw == 'kg.' ||
      raw == 'kilo' ||
      raw == 'kilos' ||
      raw == 'kilogramo' ||
      raw == 'kilogramos') {
    return 'Kg.';
  }
  if (raw == 'lt' ||
      raw == 'lt.' ||
      raw == 'l' ||
      raw == 'l.' ||
      raw == 'litro' ||
      raw == 'litros') {
    return 'Lt.';
  }
  return allowEmpty ? '' : 'Lt.';
}

const Set<String> _ltUnitFormulations = <String>{
  'EC',
  'SC',
  'SE',
  'OD',
  'EW',
  'SL',
  'CS',
  'ME',
  'FS',
  'Aceite',
  'Coadyuvante',
};

const Set<String> _kgUnitFormulations = <String>{
  'WP',
  'WG',
  'SP',
  'GR',
  'SG',
  'DT',
  'RB',
};

String? inferProductUnitFromFormulation(String? formulation) {
  final normalizedFormulation = normalizeProductFormulation(formulation);
  if (_ltUnitFormulations.contains(normalizedFormulation)) {
    return 'Lt.';
  }
  if (_kgUnitFormulations.contains(normalizedFormulation)) {
    return 'Kg.';
  }
  return null;
}

String? _matchProductType(String? value) {
  final raw = _stripAccents(_collapseSpaces(value ?? '')).toLowerCase();
  if (raw.isEmpty) {
    return null;
  }
  if (raw.contains('herbic')) {
    return 'herbicida';
  }
  if (raw.contains('fungic')) {
    return 'fungicida';
  }
  if (raw.contains('insectic')) {
    return 'insecticida';
  }
  if (raw.contains('coadyuv')) {
    return 'coadyuvante';
  }
  if (raw.contains('fertiliz')) {
    return 'fertilizante';
  }
  return null;
}

String? _matchProductTypeFromSupport(String? value) {
  final raw = _stripAccents(_collapseSpaces(value ?? '')).toLowerCase();
  if (raw.isEmpty) {
    return null;
  }

  final blocks = raw.split(RegExp(r'[\/,;\-\+]'));
  for (final block in blocks) {
    final direct = _matchProductType(block);
    if (direct != null) {
      return direct;
    }
    final words = block
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty);
    for (final word in words) {
      final fromWord = _matchProductType(word);
      if (fromWord != null) {
        return fromWord;
      }
    }
  }
  return null;
}

String normalizeProductType(String? value, {String? supportValue}) {
  final primary = _matchProductType(value);
  if (primary != null) {
    return primary;
  }
  final secondary = _matchProductTypeFromSupport(supportValue);
  if (secondary != null) {
    return secondary;
  }
  return 'Otros';
}

String? _mapFormulationToken(String? value) {
  final normalized = _stripAccents(_collapseSpaces(value ?? ''));
  if (normalized.isEmpty) {
    return null;
  }

  final upper = normalized.toUpperCase();
  const formulations = <String>{
    'WP',
    'WG',
    'CS',
    'ME',
    'FS',
    'GR',
    'SG',
    'DT',
    'RB',
    'SC',
    'SE',
    'OD',
    'EC',
    'EW',
    'SL',
    'SP',
  };
  if (formulations.contains(upper)) {
    return upper;
  }

  final lower = normalized.toLowerCase();
  if (lower == 'coadyuvante') {
    return 'Coadyuvante';
  }
  if (lower == 'aceite' || lower == 'oil') {
    return 'Aceite';
  }
  return null;
}

String normalizeProductFormulation(
  String? value, {
  bool preferParenthesizedCode = false,
}) {
  final normalizedInput = _stripAccents(_collapseSpaces(value ?? ''));
  if (normalizedInput.isEmpty) {
    return 'Otro';
  }

  if (preferParenthesizedCode) {
    final match = RegExp(r'\(([^)]+)\)').firstMatch(normalizedInput);
    if (match != null) {
      final fromParenthesis = _mapFormulationToken(match.group(1));
      return fromParenthesis ?? 'Otro';
    }
    final direct = _mapFormulationToken(normalizedInput);
    return direct ?? 'Otro';
  }

  final direct = _mapFormulationToken(normalizedInput);
  if (direct != null) {
    return direct;
  }
  final lower = normalizedInput.toLowerCase();
  if (lower.contains('coadyuv')) {
    return 'Coadyuvante';
  }
  if (lower.contains('aceite') || lower == 'oil') {
    return 'Aceite';
  }
  return 'Otro';
}

String? normalizeProductFunction(String? value, {required String type}) {
  final normalizedType = normalizeProductType(type);
  if (normalizedType != 'coadyuvante') {
    return null;
  }
  final raw = _stripAccents(_collapseSpaces(value ?? '')).toLowerCase();
  if (raw.isEmpty) {
    return null;
  }
  for (final option in productCatalogFunctionOptions) {
    if (option == raw) {
      if (option == 'ninguna') {
        return null;
      }
      return option;
    }
  }
  if (raw.contains('ph')) {
    return 'corrector_ph';
  }
  if (raw.contains('dureza') || raw.contains('secuestr')) {
    return 'secuestrante_dureza';
  }
  if (raw.contains('deriva')) {
    return 'antideriva';
  }
  if (raw.contains('espum')) {
    return 'antiespumante';
  }
  if (raw.contains('adher')) {
    return 'adherente';
  }
  if (raw.contains('humect')) {
    return 'humectante';
  }
  if (raw.contains('penetr')) {
    return 'penetrante';
  }
  if (raw.contains('acondicion')) {
    return 'acondicionador_agua';
  }
  return 'otro';
}

class MasterProductCatalogItem {
  const MasterProductCatalogItem({
    this.id,
    required this.commercialName,
    this.activeIngredient,
    required this.unit,
    required this.type,
    required this.formulation,
    this.funcion,
    this.active = true,
    this.source = 'manual',
    this.createdAt,
    this.updatedAt,
    this.commercialNameKey,
  });

  final String? id;
  final String commercialName;
  final String? activeIngredient;
  final String unit;
  final String type;
  final String formulation;
  final String? funcion;
  final bool active;
  final String source;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? commercialNameKey;

  MasterProductCatalogItem normalized({bool allowEmptyUnit = false}) {
    final normalizedCommercialName = normalizeProductCommercialName(
      commercialName,
    );
    final normalizedType = normalizeProductType(type);
    final normalizedFunction = normalizeProductFunction(
      funcion,
      type: normalizedType,
    );
    return MasterProductCatalogItem(
      id: id,
      commercialName: normalizedCommercialName,
      activeIngredient: normalizeProductActiveIngredient(activeIngredient),
      unit: normalizeProductUnitWithRules(unit, allowEmpty: allowEmptyUnit),
      type: normalizedType,
      formulation: normalizeProductFormulation(formulation),
      funcion: normalizedFunction,
      active: active,
      source: _collapseSpaces(source.isEmpty ? 'manual' : source),
      createdAt: createdAt,
      updatedAt: updatedAt,
      commercialNameKey:
          commercialNameKey ??
          normalizeProductCommercialNameKey(commercialName),
    );
  }

  MasterProductCatalogItem copyWith({
    String? id,
    String? commercialName,
    String? activeIngredient,
    String? unit,
    String? type,
    String? formulation,
    String? funcion,
    bool? active,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? commercialNameKey,
  }) {
    return MasterProductCatalogItem(
      id: id ?? this.id,
      commercialName: commercialName ?? this.commercialName,
      activeIngredient: activeIngredient ?? this.activeIngredient,
      unit: unit ?? this.unit,
      type: type ?? this.type,
      formulation: formulation ?? this.formulation,
      funcion: funcion ?? this.funcion,
      active: active ?? this.active,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      commercialNameKey: commercialNameKey ?? this.commercialNameKey,
    );
  }

  Map<String, dynamic> toMap({bool allowEmptyUnit = false}) {
    final normalizedItem = normalized(allowEmptyUnit: allowEmptyUnit);
    return <String, dynamic>{
      'commercialName': normalizedItem.commercialName,
      'activeIngredient': normalizedItem.activeIngredient,
      'unit': normalizedItem.unit,
      'type': normalizedItem.type,
      'formulation': normalizedItem.formulation,
      'funcion': normalizedItem.funcion,
      'active': normalizedItem.active,
      'source': normalizedItem.source,
      'commercialNameKey': normalizedItem.commercialNameKey,
      'createdAt': normalizedItem.createdAt == null
          ? null
          : Timestamp.fromDate(normalizedItem.createdAt!),
      'updatedAt': normalizedItem.updatedAt == null
          ? null
          : Timestamp.fromDate(normalizedItem.updatedAt!),
    };
  }

  factory MasterProductCatalogItem.fromMap(
    Map<String, dynamic> map, {
    String? id,
  }) {
    final commercialName =
        (map['commercialName'] as String? ??
                map['nombreComercial'] as String? ??
                '')
            .trim();
    final activeIngredient =
        (map['activeIngredient'] as String? ??
                map['principioActivo'] as String? ??
                '')
            .trim();
    final unit = (map['unit'] as String? ?? map['unidad'] as String? ?? '')
        .trim();
    final type = (map['type'] as String? ?? map['tipo'] as String? ?? '')
        .trim();
    final formulation =
        (map['formulation'] as String? ?? map['formulacion'] as String? ?? '')
            .trim();
    final funcion =
        (map['funcion'] as String? ?? map['function'] as String? ?? '').trim();
    return MasterProductCatalogItem(
      id: id,
      commercialName: commercialName,
      activeIngredient: activeIngredient.isEmpty ? null : activeIngredient,
      unit: unit,
      type: type,
      formulation: formulation,
      funcion: funcion.isEmpty ? null : funcion,
      active: map['active'] is bool ? map['active'] as bool : true,
      source: (map['source'] as String? ?? map['fuente'] as String? ?? 'manual')
          .trim(),
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
      commercialNameKey: (map['commercialNameKey'] as String?)?.trim(),
    ).normalized(allowEmptyUnit: true);
  }
}
