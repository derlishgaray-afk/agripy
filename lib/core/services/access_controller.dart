import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/modules.dart';
import 'tenant_path.dart';

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

enum TenantBlockReason { suspended, trialExpired }

class TenantBlockedException implements Exception {
  const TenantBlockedException({
    required this.reason,
    required this.tenantId,
    required this.tenantName,
    required this.tenantStatus,
    required this.tenantPlan,
    this.trialEndsAt,
  });

  final TenantBlockReason reason;
  final String tenantId;
  final String tenantName;
  final String tenantStatus;
  final String tenantPlan;
  final DateTime? trialEndsAt;

  String get userMessage {
    switch (reason) {
      case TenantBlockReason.suspended:
        return 'La empresa esta suspendida temporalmente.';
      case TenantBlockReason.trialExpired:
        return 'El periodo de prueba de la empresa ya vencio.';
    }
  }

  @override
  String toString() => userMessage;
}

enum TenantRole { admin, engineer, operator }

TenantRole tenantRoleFromString(String value) {
  switch (value.trim().toLowerCase()) {
    case 'admin':
      return TenantRole.admin;
    case 'engineer':
      return TenantRole.engineer;
    case 'operator':
      return TenantRole.operator;
    default:
      throw StateError('Rol inválido: $value');
  }
}

class TenantUserAccess {
  const TenantUserAccess({
    required this.role,
    required this.activeModules,
    required this.status,
    required this.displayName,
  });

  final TenantRole role;
  final List<String> activeModules;
  final String status;
  final String displayName;

  bool get isActive => status.trim().toLowerCase() == 'active';

  bool hasModule(String moduleKey) {
    return activeModules.contains(moduleKey);
  }

  bool get canEditRecetario =>
      role == TenantRole.admin || role == TenantRole.engineer;

  bool get hasRecetarioAgronomico => hasModule(AppModules.recetarioAgronomico);

  factory TenantUserAccess.fromMap(Map<String, dynamic> map) {
    final activeModulesRaw = map['activeModules'];
    final roleRaw = map['role'];
    final statusRaw = map['status'];
    final displayNameRaw = map['displayName'];

    if (roleRaw is! String || statusRaw is! String) {
      throw StateError('Documento de acceso inválido.');
    }

    final modules = <String>[];
    if (activeModulesRaw is List) {
      for (final item in activeModulesRaw) {
        if (item is String && item.trim().isNotEmpty) {
          modules.add(item.trim());
        }
      }
    }

    return TenantUserAccess(
      role: tenantRoleFromString(roleRaw),
      activeModules: List.unmodifiable(modules),
      status: statusRaw,
      displayName: displayNameRaw is String && displayNameRaw.trim().isNotEmpty
          ? displayNameRaw.trim()
          : 'Usuario',
    );
  }
}

class AccessController {
  AccessController(this._firestore);

  final FirebaseFirestore _firestore;

  Future<Map<String, dynamic>> loadTenant(String tenantId) async {
    final tenantSnapshot = await TenantPath.tenantRef(
      _firestore,
      tenantId,
    ).get();
    final tenantData = tenantSnapshot.data();
    if (tenantData == null) {
      throw StateError('No existe el tenant seleccionado.');
    }

    final statusRaw = tenantData['status'];
    final tenantStatus = (statusRaw is String ? statusRaw : 'active')
        .trim()
        .toLowerCase();
    final tenantNameRaw = tenantData['name'];
    final tenantName =
        tenantNameRaw is String && tenantNameRaw.trim().isNotEmpty
        ? tenantNameRaw.trim()
        : tenantId;
    final planRaw = (tenantData['plan'] as String? ?? '').trim().toLowerCase();
    final trialEndsAt = _parseDateTime(tenantData['trialEndsAt']);

    if (tenantStatus != 'active') {
      throw TenantBlockedException(
        reason: TenantBlockReason.suspended,
        tenantId: tenantId,
        tenantName: tenantName,
        tenantStatus: tenantStatus,
        tenantPlan: planRaw,
        trialEndsAt: trialEndsAt,
      );
    }

    if (planRaw == 'trial' &&
        trialEndsAt != null &&
        trialEndsAt.isBefore(DateTime.now())) {
      throw TenantBlockedException(
        reason: TenantBlockReason.trialExpired,
        tenantId: tenantId,
        tenantName: tenantName,
        tenantStatus: tenantStatus,
        tenantPlan: planRaw,
        trialEndsAt: trialEndsAt,
      );
    }

    return tenantData;
  }

  Future<TenantUserAccess> loadTenantUserAccess(
    String tenantId,
    String uid,
  ) async {
    await loadTenant(tenantId);

    final snapshot = await TenantPath.tenantUserRef(
      _firestore,
      tenantId,
      uid,
    ).get();
    final data = snapshot.data();

    if (data == null) {
      throw StateError('No existe acceso del usuario en el tenant.');
    }

    return TenantUserAccess.fromMap(data);
  }
}
