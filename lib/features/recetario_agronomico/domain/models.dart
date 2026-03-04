import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? parseFlexibleDateTime(dynamic value) {
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

Timestamp? toTimestampOrNull(DateTime? value) {
  if (value == null) {
    return null;
  }
  return Timestamp.fromDate(value);
}

double parseFlexibleDouble(dynamic value, {double fallback = 0}) {
  if (value is int) {
    return value.toDouble();
  }
  if (value is double) {
    return value;
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.')) ?? fallback;
  }
  return fallback;
}

class DoseLine {
  const DoseLine({
    required this.productName,
    this.activeIngredient,
    required this.dose,
    required this.unit,
    required this.functionName,
  });

  final String productName;
  final String? activeIngredient;
  final double dose;
  final String unit;
  final String functionName;

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'activeIngredient': activeIngredient,
      'dose': dose,
      'unit': unit,
      'function': functionName,
    };
  }

  factory DoseLine.fromMap(Map<String, dynamic> map) {
    return DoseLine(
      productName: (map['productName'] as String? ?? '').trim(),
      activeIngredient:
          (map['activeIngredient'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['activeIngredient'] as String?)?.trim(),
      dose: parseFlexibleDouble(map['dose']),
      unit: (map['unit'] as String? ?? '').trim(),
      functionName: (map['function'] as String? ?? '').trim(),
    );
  }
}

class Recipe {
  const Recipe({
    this.id,
    required this.title,
    required this.objective,
    required this.crop,
    required this.stage,
    required this.doseLines,
    required this.waterVolumeLHa,
    required this.mixOrder,
    required this.warnings,
    required this.notes,
    required this.status,
    required this.createdBy,
    required this.createdAt,
  });

  final String? id;
  final String title;
  final String objective;
  final String crop;
  final String stage;
  final List<DoseLine> doseLines;
  final double waterVolumeLHa;
  final List<String> mixOrder;
  final String warnings;
  final String notes;
  final String status;
  final String createdBy;
  final DateTime createdAt;

  Recipe copyWith({
    String? id,
    String? title,
    String? objective,
    String? crop,
    String? stage,
    List<DoseLine>? doseLines,
    double? waterVolumeLHa,
    List<String>? mixOrder,
    String? warnings,
    String? notes,
    String? status,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      objective: objective ?? this.objective,
      crop: crop ?? this.crop,
      stage: stage ?? this.stage,
      doseLines: doseLines ?? this.doseLines,
      waterVolumeLHa: waterVolumeLHa ?? this.waterVolumeLHa,
      mixOrder: mixOrder ?? this.mixOrder,
      warnings: warnings ?? this.warnings,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'objective': objective,
      'crop': crop,
      'stage': stage,
      'doseLines': doseLines.map((line) => line.toMap()).toList(),
      'waterVolumeLHa': waterVolumeLHa,
      'mixOrder': mixOrder,
      'warnings': warnings,
      'notes': notes,
      'status': status,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Recipe.fromMap(Map<String, dynamic> map, {String? id}) {
    final linesRaw = map['doseLines'];
    final orderRaw = map['mixOrder'];

    final lines = <DoseLine>[];
    if (linesRaw is List) {
      for (final line in linesRaw) {
        if (line is Map<String, dynamic>) {
          lines.add(DoseLine.fromMap(line));
        } else if (line is Map) {
          lines.add(DoseLine.fromMap(Map<String, dynamic>.from(line)));
        }
      }
    }

    final mixOrder = <String>[];
    if (orderRaw is List) {
      for (final step in orderRaw) {
        if (step is String && step.trim().isNotEmpty) {
          mixOrder.add(step.trim());
        }
      }
    }

    return Recipe(
      id: id,
      title: (map['title'] as String? ?? '').trim(),
      objective: (map['objective'] as String? ?? '').trim(),
      crop: (map['crop'] as String? ?? '').trim(),
      stage: (map['stage'] as String? ?? '').trim(),
      doseLines: List.unmodifiable(lines),
      waterVolumeLHa: parseFlexibleDouble(map['waterVolumeLHa']),
      mixOrder: List.unmodifiable(mixOrder),
      warnings: (map['warnings'] as String? ?? '').trim(),
      notes: (map['notes'] as String? ?? '').trim(),
      status: (map['status'] as String? ?? 'draft').trim(),
      createdBy: (map['createdBy'] as String? ?? '').trim(),
      createdAt: parseFlexibleDateTime(map['createdAt']) ?? DateTime.now(),
    );
  }
}

class ExecutionData {
  const ExecutionData({
    required this.done,
    this.doneAt,
    this.operatorUid,
    this.operatorNotes,
  });

  final bool done;
  final DateTime? doneAt;
  final String? operatorUid;
  final String? operatorNotes;

  Map<String, dynamic> toMap() {
    return {
      'done': done,
      'doneAt': toTimestampOrNull(doneAt),
      'operatorUid': operatorUid,
      'operatorNotes': operatorNotes,
    };
  }

  factory ExecutionData.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const ExecutionData(done: false);
    }
    return ExecutionData(
      done: map['done'] == true,
      doneAt: parseFlexibleDateTime(map['doneAt']),
      operatorUid: map['operatorUid'] as String?,
      operatorNotes: map['operatorNotes'] as String?,
    );
  }
}

class ApplicationOrder {
  const ApplicationOrder({
    this.id,
    required this.recipeId,
    required this.code,
    required this.farmName,
    required this.plotName,
    required this.areaHa,
    required this.issuedAt,
    this.plannedDate,
    required this.engineerName,
    required this.assignedToUid,
    required this.status,
    required this.execution,
  });

  final String? id;
  final String recipeId;
  final String code;
  final String farmName;
  final String plotName;
  final double areaHa;
  final DateTime issuedAt;
  final DateTime? plannedDate;
  final String engineerName;
  final String assignedToUid;
  final String status;
  final ExecutionData execution;

  Map<String, dynamic> toMap() {
    return {
      'recipeId': recipeId,
      'code': code,
      'farmName': farmName,
      'plotName': plotName,
      'areaHa': areaHa,
      'issuedAt': Timestamp.fromDate(issuedAt),
      'plannedDate': toTimestampOrNull(plannedDate),
      'engineerName': engineerName,
      'assignedToUid': assignedToUid,
      'status': status,
      'execution': execution.toMap(),
    };
  }

  factory ApplicationOrder.fromMap(Map<String, dynamic> map, {String? id}) {
    return ApplicationOrder(
      id: id,
      recipeId: (map['recipeId'] as String? ?? '').trim(),
      code: (map['code'] as String? ?? '').trim(),
      farmName: (map['farmName'] as String? ?? '').trim(),
      plotName: (map['plotName'] as String? ?? '').trim(),
      areaHa: parseFlexibleDouble(map['areaHa']),
      issuedAt: parseFlexibleDateTime(map['issuedAt']) ?? DateTime.now(),
      plannedDate: parseFlexibleDateTime(map['plannedDate']),
      engineerName: (map['engineerName'] as String? ?? '').trim(),
      assignedToUid: (map['assignedToUid'] as String? ?? '').trim(),
      status: (map['status'] as String? ?? 'pending').trim(),
      execution: ExecutionData.fromMap(
        map['execution'] is Map<String, dynamic>
            ? map['execution'] as Map<String, dynamic>
            : map['execution'] is Map
            ? Map<String, dynamic>.from(map['execution'] as Map)
            : null,
      ),
    );
  }
}
