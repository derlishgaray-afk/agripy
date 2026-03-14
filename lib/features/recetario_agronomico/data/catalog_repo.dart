import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/modules.dart';
import '../../../core/services/access_controller.dart';
import '../../../core/services/tenant_path.dart';
import '../domain/catalog_models.dart';

class DuplicateSupplyException implements Exception {
  DuplicateSupplyException({required this.commercialName});

  final String commercialName;

  String get userMessage =>
      'Ya existe un insumo con el mismo nombre comercial, unidad, tipo y formulacion.';

  @override
  String toString() => userMessage;
}

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
    return TenantPath.fieldsRef(_firestore, tenantId).snapshots().map((
      snapshot,
    ) {
      final items =
          snapshot.docs
              .map((doc) => FieldRegistryItem.fromMap(doc.data(), id: doc.id))
              .toList(growable: true)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      return List.unmodifiable(items);
    });
  }

  Future<void> createField({required String name}) async {
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

  Future<void> updateLot({
    required FieldRegistryItem field,
    required int lotIndex,
    required String lotName,
    required double lotAreaHa,
  }) async {
    _assertWriteAccess();
    final fieldId = field.id;
    if (fieldId == null || fieldId.isEmpty) {
      throw StateError('Campo sin id.');
    }
    if (lotIndex < 0 || lotIndex >= field.lots.length) {
      throw RangeError.index(lotIndex, field.lots, 'lotIndex');
    }
    final lots = field.lots.toList(growable: true);
    lots[lotIndex] = FieldLot(name: lotName.trim(), areaHa: lotAreaHa);
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
    return TenantPath.inputsRef(_firestore, tenantId).snapshots().map((
      snapshot,
    ) {
      final items =
          snapshot.docs
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
    await _assertSupplyNotDuplicated(item);
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
    await _assertSupplyNotDuplicated(item, excludeId: id);
    await TenantPath.inputRef(_firestore, tenantId, id).update({
      ...item.toMap(),
      'updatedBy': currentUid,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> _assertSupplyNotDuplicated(
    SupplyRegistryItem item, {
    String? excludeId,
  }) async {
    final normalizedTargetKey = _supplyDuplicateKey(item);
    final normalizedExcludeId = (excludeId ?? '').trim();
    final snapshot = await TenantPath.inputsRef(_firestore, tenantId).get();
    for (final doc in snapshot.docs) {
      if (normalizedExcludeId.isNotEmpty && doc.id == normalizedExcludeId) {
        continue;
      }
      final existing = SupplyRegistryItem.fromMap(doc.data(), id: doc.id);
      if (_supplyDuplicateKey(existing) == normalizedTargetKey) {
        throw DuplicateSupplyException(commercialName: existing.commercialName);
      }
    }
  }

  String _supplyDuplicateKey(SupplyRegistryItem item) {
    final normalizedCommercialName = item.commercialName
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toUpperCase();
    final normalizedUnit = _normalizeUnit(item.unit);
    final normalizedType = item.type
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    final normalizedFormulation = item.formulation
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    return [
      normalizedCommercialName,
      normalizedUnit,
      normalizedType,
      normalizedFormulation,
    ].join('|');
  }

  String _normalizeUnit(String value) {
    final raw = value
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('.', '')
        .toLowerCase();
    if (raw == 'kg' ||
        raw == 'kilo' ||
        raw == 'kilos' ||
        raw == 'kilogramo' ||
        raw == 'kilogramos') {
      return 'kg';
    }
    if (raw == 'lt' || raw == 'l' || raw == 'litro' || raw == 'litros') {
      return 'lt';
    }
    return raw;
  }

  Future<void> deleteSupply(String id) async {
    _assertWriteAccess();
    await TenantPath.inputRef(_firestore, tenantId, id).delete();
  }

  Stream<List<OperatorRegistryItem>> watchOperators() {
    _assertModuleAccess();
    final Stream<List<OperatorRegistryItem>> manualStream =
        TenantPath.operatorsRef(_firestore, tenantId).snapshots().map((
          snapshot,
        ) {
          final items = snapshot.docs
              .map(
                (doc) => OperatorRegistryItem.fromMap(doc.data(), id: doc.id),
              )
              .where((item) => item.name.isNotEmpty)
              .toList(growable: false);
          return List<OperatorRegistryItem>.unmodifiable(items);
        });

    final Stream<List<OperatorRegistryItem>> tenantUsersStream = _firestore
        .collection(TenantPath.tenantUsersCollection(tenantId))
        .where('role', isEqualTo: 'operator')
        .snapshots()
        .map((snapshot) {
          final items = <OperatorRegistryItem>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final status = (data['status'] as String? ?? 'active')
                .trim()
                .toLowerCase();
            if (status != 'active') {
              continue;
            }
            items.add(OperatorRegistryItem.fromTenantUser(doc.id, data));
          }
          return List<OperatorRegistryItem>.unmodifiable(items);
        });

    return _combineOperatorStreams(
      manualStream: manualStream,
      autoStream: tenantUsersStream,
    );
  }

  Stream<List<OperatorRegistryItem>> _combineOperatorStreams({
    required Stream<List<OperatorRegistryItem>> manualStream,
    required Stream<List<OperatorRegistryItem>> autoStream,
  }) {
    List<OperatorRegistryItem>? manualItems;
    List<OperatorRegistryItem>? autoItems;
    StreamSubscription<List<OperatorRegistryItem>>? manualSub;
    StreamSubscription<List<OperatorRegistryItem>>? autoSub;

    late final StreamController<List<OperatorRegistryItem>> controller;
    void emitIfReady() {
      if (manualItems == null || autoItems == null || controller.isClosed) {
        return;
      }
      controller.add(_mergeOperators(manualItems!, autoItems!));
    }

    controller = StreamController<List<OperatorRegistryItem>>(
      onListen: () {
        manualSub = manualStream.listen((items) {
          manualItems = items;
          emitIfReady();
        }, onError: controller.addError);
        autoSub = autoStream.listen((items) {
          autoItems = items;
          emitIfReady();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await manualSub?.cancel();
        await autoSub?.cancel();
      },
    );

    return controller.stream;
  }

  List<OperatorRegistryItem> _mergeOperators(
    List<OperatorRegistryItem> manualItems,
    List<OperatorRegistryItem> autoItems,
  ) {
    final byName = <String, OperatorRegistryItem>{};

    for (final item in manualItems) {
      _addOperatorIfUnique(byName, item);
    }
    for (final item in autoItems) {
      _addOperatorIfUnique(byName, item);
    }

    final merged = byName.values.toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(merged);
  }

  void _addOperatorIfUnique(
    Map<String, OperatorRegistryItem> byName,
    OperatorRegistryItem item,
  ) {
    final key = _normalizeOperatorName(item.name);
    if (key.isEmpty || byName.containsKey(key)) {
      return;
    }
    byName[key] = item;
  }

  String _normalizeOperatorName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
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
