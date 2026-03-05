import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/modules.dart';
import '../../../core/services/access_controller.dart';
import '../../../core/services/tenant_path.dart';
import '../domain/catalog_models.dart';

class RecetarioCatalogRepo {
  RecetarioCatalogRepo({
    required FirebaseFirestore firestore,
    required this.tenantId,
    required this.currentUid,
    required TenantUserAccess access,
  }) : _firestore = firestore,
       _access = access;

  final FirebaseFirestore _firestore;
  final String tenantId;
  final String currentUid;
  final TenantUserAccess _access;

  void _assertModuleAccess() {
    if (!_access.isActive) {
      throw StateError('Usuario inactivo en el tenant.');
    }
    if (!_access.hasModule(AppModules.recetarioAgronomico)) {
      throw StateError('Módulo recetario_agronomico no habilitado.');
    }
  }

  void _assertWriteAccess() {
    _assertModuleAccess();
    if (!_access.canEditRecetario) {
      throw StateError('Tu rol no puede modificar registros.');
    }
  }

  Stream<List<FieldRegistryItem>> watchFields() {
    _assertModuleAccess();
    return TenantPath.fieldsRef(_firestore, tenantId).snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((doc) => FieldRegistryItem.fromMap(doc.data(), id: doc.id))
          .toList(growable: true)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return List.unmodifiable(items);
    });
  }

  Future<void> createField({
    required String name,
  }) async {
    _assertWriteAccess();
    final doc = TenantPath.fieldsRef(_firestore, tenantId).doc();
    await doc.set({
      'name': name.trim(),
      'totalAreaHa': 0.0,
      'lots': const <Map<String, dynamic>>[],
      'createdBy': currentUid,
      'createdAt': Timestamp.now(),
    });
  }

  Future<void> updateField({
    required String fieldId,
    required String name,
  }) async {
    _assertWriteAccess();
    await TenantPath.fieldRef(_firestore, tenantId, fieldId).update({
      'name': name.trim(),
      'updatedBy': currentUid,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> deleteField(String fieldId) async {
    _assertWriteAccess();
    await TenantPath.fieldRef(_firestore, tenantId, fieldId).delete();
  }

  Future<void> addLot({
    required FieldRegistryItem field,
    required String lotName,
    required double lotAreaHa,
  }) async {
    _assertWriteAccess();
    final fieldId = field.id;
    if (fieldId == null || fieldId.isEmpty) {
      throw StateError('Campo sin id.');
    }
    final lots = field.lots.toList(growable: true)
      ..add(FieldLot(name: lotName.trim(), areaHa: lotAreaHa));
    final totalAreaHa = _sumLotsArea(lots);
    await TenantPath.fieldRef(_firestore, tenantId, fieldId).update({
      'lots': lots.map((lot) => lot.toMap()).toList(growable: false),
      'totalAreaHa': totalAreaHa,
      'updatedBy': currentUid,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> removeLot({
    required FieldRegistryItem field,
    required int lotIndex,
  }) async {
    _assertWriteAccess();
    final fieldId = field.id;
    if (fieldId == null || fieldId.isEmpty) {
      throw StateError('Campo sin id.');
    }
    if (lotIndex < 0 || lotIndex >= field.lots.length) {
      throw RangeError.index(lotIndex, field.lots, 'lotIndex');
    }
    final lots = field.lots.toList(growable: true)..removeAt(lotIndex);
    final totalAreaHa = _sumLotsArea(lots);
    await TenantPath.fieldRef(_firestore, tenantId, fieldId).update({
      'lots': lots.map((lot) => lot.toMap()).toList(growable: false),
      'totalAreaHa': totalAreaHa,
      'updatedBy': currentUid,
      'updatedAt': Timestamp.now(),
    });
  }

  double _sumLotsArea(List<FieldLot> lots) {
    var total = 0.0;
    for (final lot in lots) {
      total += lot.areaHa;
    }
    return total;
  }

  Stream<List<SupplyRegistryItem>> watchSupplies() {
    _assertModuleAccess();
    return TenantPath.inputsRef(_firestore, tenantId).snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((doc) => SupplyRegistryItem.fromMap(doc.data(), id: doc.id))
          .toList(growable: true)
        ..sort(
          (a, b) => a.commercialName.toLowerCase().compareTo(
            b.commercialName.toLowerCase(),
          ),
        );
      return List.unmodifiable(items);
    });
  }

  Future<void> createSupply(SupplyRegistryItem item) async {
    _assertWriteAccess();
    final doc = TenantPath.inputsRef(_firestore, tenantId).doc();
    await doc.set({
      ...item.toMap(),
      'createdBy': currentUid,
      'createdAt': Timestamp.now(),
    });
  }

  Future<void> updateSupply(SupplyRegistryItem item) async {
    _assertWriteAccess();
    final id = item.id;
    if (id == null || id.isEmpty) {
      throw StateError('Insumo sin id.');
    }
    await TenantPath.inputRef(_firestore, tenantId, id).update({
      ...item.toMap(),
      'updatedBy': currentUid,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> deleteSupply(String id) async {
    _assertWriteAccess();
    await TenantPath.inputRef(_firestore, tenantId, id).delete();
  }

  Stream<List<OperatorRegistryItem>> watchOperators() {
    _assertModuleAccess();
    return TenantPath.operatorsRef(_firestore, tenantId).snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((doc) => OperatorRegistryItem.fromMap(doc.data(), id: doc.id))
          .toList(growable: true)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return List.unmodifiable(items);
    });
  }

  Future<void> createOperator(String name) async {
    _assertWriteAccess();
    final doc = TenantPath.operatorsRef(_firestore, tenantId).doc();
    await doc.set({
      'name': name.trim(),
      'createdBy': currentUid,
      'createdAt': Timestamp.now(),
    });
  }

  Future<void> updateOperator({
    required String id,
    required String name,
  }) async {
    _assertWriteAccess();
    await TenantPath.operatorRef(_firestore, tenantId, id).update({
      'name': name.trim(),
      'updatedBy': currentUid,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> deleteOperator(String id) async {
    _assertWriteAccess();
    await TenantPath.operatorRef(_firestore, tenantId, id).delete();
  }
}
