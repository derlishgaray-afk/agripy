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
    required this.nozzleTypes,
    required this.mixOrder,
    required this.warnings,
    required this.notes,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.emissionCount,
    this.lastEmission,
  });

  final String? id;
  final String title;
  final String objective;
  final String crop;
  final String stage;
  final List<DoseLine> doseLines;
  final double waterVolumeLHa;
  final String nozzleTypes;
  final List<String> mixOrder;
  final String warnings;
  final String notes;
  final String status;
  final String createdBy;
  final DateTime createdAt;
  final int emissionCount;
  final RecipeEmissionData? lastEmission;

  Recipe copyWith({
    String? id,
    String? title,
    String? objective,
    String? crop,
    String? stage,
    List<DoseLine>? doseLines,
    double? waterVolumeLHa,
    String? nozzleTypes,
    List<String>? mixOrder,
    String? warnings,
    String? notes,
    String? status,
    String? createdBy,
    DateTime? createdAt,
    int? emissionCount,
    RecipeEmissionData? lastEmission,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      objective: objective ?? this.objective,
      crop: crop ?? this.crop,
      stage: stage ?? this.stage,
      doseLines: doseLines ?? this.doseLines,
      waterVolumeLHa: waterVolumeLHa ?? this.waterVolumeLHa,
      nozzleTypes: nozzleTypes ?? this.nozzleTypes,
      mixOrder: mixOrder ?? this.mixOrder,
      warnings: warnings ?? this.warnings,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      emissionCount: emissionCount ?? this.emissionCount,
      lastEmission: lastEmission ?? this.lastEmission,
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
      'nozzleTypes': nozzleTypes,
      'mixOrder': mixOrder,
      'warnings': warnings,
      'notes': notes,
      'status': status,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'emissionCount': emissionCount,
      'lastEmission': lastEmission?.toMap(),
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
      nozzleTypes: (map['nozzleTypes'] as String? ?? '').trim(),
      mixOrder: List.unmodifiable(mixOrder),
      warnings: (map['warnings'] as String? ?? '').trim(),
      notes: (map['notes'] as String? ?? '').trim(),
      status: (map['status'] as String? ?? 'draft').trim(),
      createdBy: (map['createdBy'] as String? ?? '').trim(),
      createdAt: parseFlexibleDateTime(map['createdAt']) ?? DateTime.now(),
      emissionCount: (map['emissionCount'] as num?)?.toInt() ?? 0,
      lastEmission: map['lastEmission'] is Map<String, dynamic>
          ? RecipeEmissionData.fromMap(
              map['lastEmission'] as Map<String, dynamic>,
            )
          : map['lastEmission'] is Map
          ? RecipeEmissionData.fromMap(
              Map<String, dynamic>.from(map['lastEmission'] as Map),
            )
          : null,
    );
  }
}

class RecipeEmissionData {
  const RecipeEmissionData({
    required this.orderId,
    required this.code,
    required this.farmName,
    required this.plotName,
    required this.areaHa,
    required this.affectedAreaHa,
    required this.tankCapacityLt,
    required this.tankCount,
    required this.issuedAt,
    this.plannedDate,
    required this.engineerName,
    required this.operatorName,
    required this.assignedToUid,
  });

  final String orderId;
  final String code;
  final String farmName;
  final String plotName;
  final double areaHa;
  final double affectedAreaHa;
  final double tankCapacityLt;
  final double tankCount;
  final DateTime issuedAt;
  final DateTime? plannedDate;
  final String engineerName;
  final String operatorName;
  final String assignedToUid;

  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'code': code,
      'farmName': farmName,
      'plotName': plotName,
      'areaHa': areaHa,
      'affectedAreaHa': affectedAreaHa,
      'tankCapacityLt': tankCapacityLt,
      'tankCount': tankCount,
      'issuedAt': toTimestampOrNull(issuedAt),
      'plannedDate': toTimestampOrNull(plannedDate),
      'engineerName': engineerName,
      'operatorName': operatorName,
      'assignedToUid': assignedToUid,
    };
  }

  factory RecipeEmissionData.fromMap(Map<String, dynamic> map) {
    return RecipeEmissionData(
      orderId: (map['orderId'] as String? ?? '').trim(),
      code: (map['code'] as String? ?? '').trim(),
      farmName: (map['farmName'] as String? ?? '').trim(),
      plotName: (map['plotName'] as String? ?? '').trim(),
      areaHa: parseFlexibleDouble(map['areaHa']),
      affectedAreaHa: parseFlexibleDouble(
        map['affectedAreaHa'],
        fallback: parseFlexibleDouble(map['areaHa']),
      ),
      tankCapacityLt: parseFlexibleDouble(map['tankCapacityLt']),
      tankCount: parseFlexibleDouble(map['tankCount']),
      issuedAt: parseFlexibleDateTime(map['issuedAt']) ?? DateTime.now(),
      plannedDate: parseFlexibleDateTime(map['plannedDate']),
      engineerName: (map['engineerName'] as String? ?? '').trim(),
      operatorName: (map['operatorName'] as String? ?? '').trim(),
      assignedToUid: (map['assignedToUid'] as String? ?? '').trim(),
    );
  }

  factory RecipeEmissionData.fromOrder(ApplicationOrder order) {
    return RecipeEmissionData(
      orderId: order.id ?? '',
      code: order.code,
      farmName: order.farmName,
      plotName: order.plotName,
      areaHa: order.areaHa,
      affectedAreaHa: order.affectedAreaHa,
      tankCapacityLt: order.tankCapacityLt,
      tankCount: order.tankCount,
      issuedAt: order.issuedAt,
      plannedDate: order.plannedDate,
      engineerName: order.engineerName,
      operatorName: order.operatorName,
      assignedToUid: order.assignedToUid,
    );
  }
}

class TankApplicationEntry {
  const TankApplicationEntry({
    required this.tankCount,
    required this.tankCapacityLt,
    required this.appliedVolumeLt,
    required this.appliedTankEquivalent,
    required this.appliedAt,
    required this.operatorUid,
    required this.plotName,
  });

  final double tankCount;
  final double tankCapacityLt;
  final double appliedVolumeLt;
  final double appliedTankEquivalent;
  final DateTime appliedAt;
  final String operatorUid;
  final String plotName;

  Map<String, dynamic> toMap() {
    return {
      'tankCount': tankCount,
      'tankCapacityLt': tankCapacityLt,
      'appliedVolumeLt': appliedVolumeLt,
      'appliedTankEquivalent': appliedTankEquivalent,
      'appliedAt': Timestamp.fromDate(appliedAt),
      'operatorUid': operatorUid,
      'plotName': plotName,
    };
  }

  factory TankApplicationEntry.fromMap(Map<String, dynamic> map) {
    return TankApplicationEntry(
      tankCount: parseFlexibleDouble(map['tankCount']),
      tankCapacityLt: parseFlexibleDouble(map['tankCapacityLt']),
      appliedVolumeLt: parseFlexibleDouble(map['appliedVolumeLt']),
      appliedTankEquivalent: parseFlexibleDouble(map['appliedTankEquivalent']),
      appliedAt: parseFlexibleDateTime(map['appliedAt']) ?? DateTime.now(),
      operatorUid: (map['operatorUid'] as String? ?? '').trim(),
      plotName: (map['plotName'] as String? ?? '').trim(),
    );
  }
}

class ExecutionData {
  const ExecutionData({
    required this.done,
    this.doneAt,
    this.operatorUid,
    this.operatorNotes,
    this.appliedTankCount = 0,
    this.appliedVolumeLt = 0,
    this.tankApplications = const [],
  });

  final bool done;
  final DateTime? doneAt;
  final String? operatorUid;
  final String? operatorNotes;
  final double appliedTankCount;
  final double appliedVolumeLt;
  final List<TankApplicationEntry> tankApplications;

  ExecutionData copyWith({
    bool? done,
    DateTime? doneAt,
    String? operatorUid,
    String? operatorNotes,
    double? appliedTankCount,
    double? appliedVolumeLt,
    List<TankApplicationEntry>? tankApplications,
  }) {
    return ExecutionData(
      done: done ?? this.done,
      doneAt: doneAt ?? this.doneAt,
      operatorUid: operatorUid ?? this.operatorUid,
      operatorNotes: operatorNotes ?? this.operatorNotes,
      appliedTankCount: appliedTankCount ?? this.appliedTankCount,
      appliedVolumeLt: appliedVolumeLt ?? this.appliedVolumeLt,
      tankApplications: tankApplications ?? this.tankApplications,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'done': done,
      'doneAt': toTimestampOrNull(doneAt),
      'operatorUid': operatorUid,
      'operatorNotes': operatorNotes,
      'appliedTankCount': appliedTankCount,
      'appliedVolumeLt': appliedVolumeLt,
      'tankApplications': tankApplications
          .map((entry) => entry.toMap())
          .toList(growable: false),
    };
  }

  factory ExecutionData.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const ExecutionData(done: false);
    }
    final applicationsRaw = map['tankApplications'];
    final applications = <TankApplicationEntry>[];
    if (applicationsRaw is List) {
      for (final item in applicationsRaw) {
        if (item is Map<String, dynamic>) {
          applications.add(TankApplicationEntry.fromMap(item));
        } else if (item is Map) {
          applications.add(
            TankApplicationEntry.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return ExecutionData(
      done: map['done'] == true,
      doneAt: parseFlexibleDateTime(map['doneAt']),
      operatorUid: map['operatorUid'] as String?,
      operatorNotes: map['operatorNotes'] as String?,
      appliedTankCount: parseFlexibleDouble(map['appliedTankCount']),
      appliedVolumeLt: parseFlexibleDouble(map['appliedVolumeLt']),
      tankApplications: List.unmodifiable(applications),
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
    required this.affectedAreaHa,
    required this.tankCapacityLt,
    required this.tankCount,
    required this.issuedAt,
    this.plannedDate,
    required this.engineerName,
    required this.operatorName,
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
  final double affectedAreaHa;
  final double tankCapacityLt;
  final double tankCount;
  final DateTime issuedAt;
  final DateTime? plannedDate;
  final String engineerName;
  final String operatorName;
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
      'affectedAreaHa': affectedAreaHa,
      'tankCapacityLt': tankCapacityLt,
      'tankCount': tankCount,
      'issuedAt': Timestamp.fromDate(issuedAt),
      'plannedDate': toTimestampOrNull(plannedDate),
      'engineerName': engineerName,
      'operatorName': operatorName,
      'assignedToUid': assignedToUid,
      'status': status,
      'execution': execution.toMap(),
    };
  }

  factory ApplicationOrder.fromMap(Map<String, dynamic> map, {String? id}) {
    final tankCapacityLt = parseFlexibleDouble(map['tankCapacityLt']);
    final tankCount = parseFlexibleDouble(map['tankCount']);
    final status = (map['status'] as String? ?? 'pending').trim();
    var execution = ExecutionData.fromMap(
      map['execution'] is Map<String, dynamic>
          ? map['execution'] as Map<String, dynamic>
          : map['execution'] is Map
          ? Map<String, dynamic>.from(map['execution'] as Map)
          : null,
    );
    final normalizedStatus = status.toLowerCase();
    final isCompleted = normalizedStatus == 'completed' || execution.done;
    if (isCompleted && execution.appliedTankCount <= 0 && tankCount > 0) {
      final fallbackAppliedVolume = execution.appliedVolumeLt > 0
          ? execution.appliedVolumeLt
          : (tankCapacityLt > 0 ? tankCapacityLt * tankCount : 0.0);
      execution = execution.copyWith(
        done: true,
        appliedTankCount: tankCount,
        appliedVolumeLt: fallbackAppliedVolume,
      );
    }

    return ApplicationOrder(
      id: id,
      recipeId: (map['recipeId'] as String? ?? '').trim(),
      code: (map['code'] as String? ?? '').trim(),
      farmName: (map['farmName'] as String? ?? '').trim(),
      plotName: (map['plotName'] as String? ?? '').trim(),
      areaHa: parseFlexibleDouble(map['areaHa']),
      affectedAreaHa: parseFlexibleDouble(
        map['affectedAreaHa'],
        fallback: parseFlexibleDouble(map['areaHa']),
      ),
      tankCapacityLt: tankCapacityLt,
      tankCount: tankCount,
      issuedAt: parseFlexibleDateTime(map['issuedAt']) ?? DateTime.now(),
      plannedDate: parseFlexibleDateTime(map['plannedDate']),
      engineerName: (map['engineerName'] as String? ?? '').trim(),
      operatorName: (map['operatorName'] as String? ?? '').trim(),
      assignedToUid: (map['assignedToUid'] as String? ?? '').trim(),
      status: status,
      execution: execution,
    );
  }
}
