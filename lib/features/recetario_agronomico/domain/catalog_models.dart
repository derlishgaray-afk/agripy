import 'models.dart';

class FieldLot {
  const FieldLot({
    required this.name,
    required this.areaHa,
  });

  final String name;
  final double areaHa;

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'areaHa': areaHa,
    };
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
  });

  final String? id;
  final String commercialName;
  final String? activeIngredient;
  final String unit;
  final String type;

  SupplyRegistryItem copyWith({
    String? id,
    String? commercialName,
    String? activeIngredient,
    String? unit,
    String? type,
  }) {
    return SupplyRegistryItem(
      id: id ?? this.id,
      commercialName: commercialName ?? this.commercialName,
      activeIngredient: activeIngredient ?? this.activeIngredient,
      unit: unit ?? this.unit,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'commercialName': commercialName,
      'activeIngredient': activeIngredient,
      'unit': unit,
      'type': type,
    };
  }

  factory SupplyRegistryItem.fromMap(Map<String, dynamic> map, {String? id}) {
    final active = (map['activeIngredient'] as String?)?.trim();
    return SupplyRegistryItem(
      id: id,
      commercialName: (map['commercialName'] as String? ?? '').trim(),
      activeIngredient: active == null || active.isEmpty ? null : active,
      unit: (map['unit'] as String? ?? '').trim(),
      type: (map['type'] as String? ?? '').trim(),
    );
  }
}

class OperatorRegistryItem {
  const OperatorRegistryItem({
    this.id,
    required this.name,
  });

  final String? id;
  final String name;

  OperatorRegistryItem copyWith({
    String? id,
    String? name,
  }) {
    return OperatorRegistryItem(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
    };
  }

  factory OperatorRegistryItem.fromMap(Map<String, dynamic> map, {String? id}) {
    return OperatorRegistryItem(
      id: id,
      name: (map['name'] as String? ?? '').trim(),
    );
  }
}
