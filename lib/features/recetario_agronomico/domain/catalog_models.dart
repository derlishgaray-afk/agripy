import 'models.dart';

String _normalizeSupplyCommercialName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
}

const String _defaultSupplyFunction = 'ninguna';
const Set<String> _allowedSupplyFunctions = <String>{
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
};

String _normalizeSupplyFunction(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  if (_allowedSupplyFunctions.contains(normalized)) {
    return normalized;
  }
  return _defaultSupplyFunction;
}

class FieldLot {
  const FieldLot({required this.name, required this.areaHa});

  final String name;
  final double areaHa;

  Map<String, dynamic> toMap() {
    return {'name': name, 'areaHa': areaHa};
  }

  factory FieldLot.fromMap(Map<String, dynamic> map) {
    return FieldLot(
      name: (map['name'] as String? ?? '').trim(),
      areaHa: parseFlexibleDouble(map['areaHa']),
    );
  }
}

class FieldRegistryItem {
  const FieldRegistryItem({
    this.id,
    required this.name,
    required this.totalAreaHa,
    required this.lots,
  });

  final String? id;
  final String name;
  final double totalAreaHa;
  final List<FieldLot> lots;

  FieldRegistryItem copyWith({
    String? id,
    String? name,
    double? totalAreaHa,
    List<FieldLot>? lots,
  }) {
    return FieldRegistryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      totalAreaHa: totalAreaHa ?? this.totalAreaHa,
      lots: lots ?? this.lots,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'totalAreaHa': totalAreaHa,
      'lots': lots.map((lot) => lot.toMap()).toList(growable: false),
    };
  }

  factory FieldRegistryItem.fromMap(Map<String, dynamic> map, {String? id}) {
    final lotsRaw = map['lots'];
    final lots = <FieldLot>[];
    if (lotsRaw is List) {
      for (final item in lotsRaw) {
        if (item is Map<String, dynamic>) {
          lots.add(FieldLot.fromMap(item));
        } else if (item is Map) {
          lots.add(FieldLot.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }
    return FieldRegistryItem(
      id: id,
      name: (map['name'] as String? ?? '').trim(),
      totalAreaHa: parseFlexibleDouble(map['totalAreaHa']),
      lots: List.unmodifiable(lots),
    );
  }
}

class SupplyRegistryItem {
  const SupplyRegistryItem({
    this.id,
    required this.commercialName,
    this.activeIngredient,
    required this.unit,
    required this.type,
    required this.formulation,
    this.funcion = _defaultSupplyFunction,
  });

  final String? id;
  final String commercialName;
  final String? activeIngredient;
  final String unit;
  final String type;
  final String formulation;
  final String funcion;

  SupplyRegistryItem copyWith({
    String? id,
    String? commercialName,
    String? activeIngredient,
    String? unit,
    String? type,
    String? formulation,
    String? funcion,
  }) {
    return SupplyRegistryItem(
      id: id ?? this.id,
      commercialName: commercialName ?? this.commercialName,
      activeIngredient: activeIngredient ?? this.activeIngredient,
      unit: unit ?? this.unit,
      type: type ?? this.type,
      formulation: formulation ?? this.formulation,
      funcion: funcion ?? this.funcion,
    );
  }

  Map<String, dynamic> toMap() {
    final normalizedFunction = _normalizeSupplyFunction(funcion);
    return {
      'commercialName': _normalizeSupplyCommercialName(commercialName),
      'activeIngredient': activeIngredient,
      'unit': unit,
      'type': type,
      'formulation': formulation,
      if (normalizedFunction != _defaultSupplyFunction)
        'funcion': normalizedFunction,
    };
  }

  factory SupplyRegistryItem.fromMap(Map<String, dynamic> map, {String? id}) {
    final active = (map['activeIngredient'] as String?)?.trim();
    return SupplyRegistryItem(
      id: id,
      commercialName: _normalizeSupplyCommercialName(
        (map['commercialName'] as String? ?? ''),
      ),
      activeIngredient: active == null || active.isEmpty ? null : active,
      unit: (map['unit'] as String? ?? '').trim(),
      type: (map['type'] as String? ?? '').trim(),
      formulation: (map['formulation'] as String? ?? 'Otro').trim(),
      funcion: _normalizeSupplyFunction(map['funcion'] as String?),
    );
  }
}

class OperatorRegistryItem {
  const OperatorRegistryItem({
    this.id,
    required this.name,
    this.isAuto = false,
    this.linkedUserUid,
  });

  final String? id;
  final String name;
  final bool isAuto;
  final String? linkedUserUid;

  OperatorRegistryItem copyWith({
    String? id,
    String? name,
    bool? isAuto,
    String? linkedUserUid,
  }) {
    return OperatorRegistryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      isAuto: isAuto ?? this.isAuto,
      linkedUserUid: linkedUserUid ?? this.linkedUserUid,
    );
  }

  Map<String, dynamic> toMap() {
    return {'name': name};
  }

  factory OperatorRegistryItem.fromMap(Map<String, dynamic> map, {String? id}) {
    return OperatorRegistryItem(
      id: id,
      name: (map['name'] as String? ?? '').trim(),
      isAuto: false,
      linkedUserUid: null,
    );
  }

  factory OperatorRegistryItem.fromTenantUser(
    String uid,
    Map<String, dynamic> map,
  ) {
    final displayName = (map['displayName'] as String? ?? '').trim();
    final email = (map['email'] as String? ?? '').trim();
    final resolvedName = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email : uid);
    return OperatorRegistryItem(
      id: 'user:$uid',
      name: resolvedName,
      isAuto: true,
      linkedUserUid: uid,
    );
  }
}
