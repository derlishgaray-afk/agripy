import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/modules.dart';
import 'tenant_path.dart';

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
      throw StateError('Rol invalido: $value');
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
      throw StateError('Documento de acceso invalido.');
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
    if (tenantStatus != 'active') {
      throw StateError('Empresa suspendida. Contactar al administrador.');
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
