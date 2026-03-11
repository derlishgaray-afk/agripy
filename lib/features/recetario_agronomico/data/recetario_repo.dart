import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/modules.dart';
import '../../../core/services/access_controller.dart';
import '../../../core/services/tenant_path.dart';
import '../domain/models.dart';
import '../services/recetario_code_service.dart';

class RecetarioRepo {
  RecetarioRepo({
    required FirebaseFirestore firestore,
    required this.tenantId,
    required this.currentUid,
    required TenantUserAccess access,
    RecetarioCodeService? recetarioCodeService,
  }) : _firestore = firestore,
       _access = access,
       _recetarioCodeService =
           recetarioCodeService ?? RecetarioCodeService(firestore: firestore);

  final FirebaseFirestore _firestore;
  final String tenantId;
  final String currentUid;
  final TenantUserAccess _access;
  final RecetarioCodeService _recetarioCodeService;

  void _assertModuleAccess() {
    if (!_access.isActive) {
      throw StateError('Usuario inactivo en el tenant.');
    }
    if (!_access.hasModule(AppModules.recetarioAgronomico)) {
      throw StateError('Modulo recetario_agronomico no habilitado.');
    }
  }

  void _assertWriteAccess() {
    _assertModuleAccess();
    if (_access.role == TenantRole.operator) {
      throw StateError('El rol operator no puede modificar recetarios.');
    }
  }

  void _assertOrderExecutionAccess() {
    _assertModuleAccess();
    final role = _access.role;
    if (role != TenantRole.admin &&
        role != TenantRole.engineer &&
        role != TenantRole.operator) {
      throw StateError('Tu rol no puede actualizar aplicaciones.');
    }
  }

  bool _operatorCanHandleOrder(ApplicationOrder order) {
    if (order.assignedToUid.trim() == currentUid) {
      return true;
    }
    if (_access.role != TenantRole.operator) {
      return false;
    }
    final currentName = _normalizeName(_access.displayName);
    final operatorName = _normalizeName(order.operatorName);
    return currentName.isNotEmpty && operatorName == currentName;
  }

  String _normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Stream<List<Recipe>> watchRecipes({String? status}) {
    _assertModuleAccess();
    final normalizedStatus = status?.trim().toLowerCase();
    Query<Map<String, dynamic>> query = TenantPath.recipesRef(
      _firestore,
      tenantId,
    );
    if (normalizedStatus == null || normalizedStatus.isEmpty) {
      query = query.orderBy('createdAt', descending: true);
    } else if (normalizedStatus == 'draft') {
      query = query.where('status', isEqualTo: 'draft');
    } else if (normalizedStatus == 'published') {
      query = query.where('status', isEqualTo: 'published');
    } else if (normalizedStatus == 'emitted') {
      query = query.where('status', isEqualTo: 'emitted');
    }
    return query.snapshots().map((snapshot) {
      final recipes = snapshot.docs
          .map((doc) => Recipe.fromMap(doc.data(), id: doc.id))
          .toList(growable: false);
      final sorted = recipes.toList(growable: true)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List.unmodifiable(sorted);
    });
  }

  Future<Recipe?> getRecipeById(String recipeId) async {
    _assertModuleAccess();
    final snapshot = await TenantPath.recipeRef(
      _firestore,
      tenantId,
      recipeId,
    ).get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    return Recipe.fromMap(data, id: snapshot.id);
  }

  Future<String> createRecipe(Recipe recipe) async {
    _assertWriteAccess();
    final docRef = TenantPath.recipesRef(_firestore, tenantId).doc();
    final payload = recipe.copyWith(
      id: docRef.id,
      createdAt: recipe.createdAt,
      createdBy: recipe.createdBy.isEmpty ? currentUid : recipe.createdBy,
    );
    await docRef.set(payload.toMap());
    return docRef.id;
  }

  Future<void> updateRecipe(Recipe recipe) async {
    _assertWriteAccess();
    final recipeId = recipe.id;
    if (recipeId == null || recipeId.isEmpty) {
      throw StateError('No se puede actualizar una receta sin id.');
    }
    await TenantPath.recipeRef(
      _firestore,
      tenantId,
      recipeId,
    ).update(recipe.toMap());
  }

  Future<void> deleteDraftRecipe(String recipeId) async {
    _assertWriteAccess();
    final normalizedId = recipeId.trim();
    if (normalizedId.isEmpty) {
      throw StateError('No se puede eliminar una receta sin id.');
    }

    final recipeRef = TenantPath.recipeRef(_firestore, tenantId, normalizedId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(recipeRef);
      final data = snapshot.data();
      if (data == null) {
        throw StateError('Receta no encontrada.');
      }
      final recipe = Recipe.fromMap(data, id: snapshot.id);
      final status = recipe.status.trim().toLowerCase();
      final isDraft = status == 'draft' || status == 'borrador';
      if (!isDraft) {
        throw StateError('Solo se puede eliminar una receta en borrador.');
      }
      transaction.delete(recipeRef);
    });
  }

  Future<void> publishRecipe(String recipeId) async {
    _assertWriteAccess();
    await TenantPath.recipeRef(
      _firestore,
      tenantId,
      recipeId,
    ).update({'status': 'published'});
  }

  Future<ApplicationOrder> createOrder({
    required Recipe recipe,
    required String farmName,
    required String plotName,
    required double areaHa,
    required double affectedAreaHa,
    required double tankCapacityLt,
    required DateTime plannedDate,
    required String engineerName,
    required String operatorName,
    required String assignedToUid,
  }) async {
    _assertWriteAccess();
    if (recipe.id == null || recipe.id!.isEmpty) {
      throw StateError('La receta debe estar guardada antes de emitir.');
    }

    final now = DateTime.now();
    final tankCount = _calculateTankCount(
      affectedAreaHa: affectedAreaHa,
      tankCapacityLt: tankCapacityLt,
      waterVolumeLHa: recipe.waterVolumeLHa,
    );
    final ordersRef = TenantPath.applicationOrdersRef(_firestore, tenantId);
    final docRef = ordersRef.doc();
    final emittedRecipeRef = TenantPath.recipesRef(_firestore, tenantId).doc();
    ApplicationOrder? createdOrder;

    await _firestore.runTransaction((transaction) async {
      final code = await _recetarioCodeService
          .generateNextRecetarioCodeInTransaction(
            tenantId: tenantId,
            transaction: transaction,
            issuedAt: now,
          );
      final order = ApplicationOrder(
        id: docRef.id,
        recipeId: emittedRecipeRef.id,
        code: code,
        farmName: farmName.trim(),
        plotName: plotName.trim(),
        areaHa: areaHa,
        affectedAreaHa: affectedAreaHa,
        tankCapacityLt: tankCapacityLt,
        tankCount: tankCount,
        issuedAt: now,
        plannedDate: plannedDate,
        engineerName: engineerName.trim(),
        operatorName: operatorName.trim(),
        assignedToUid: assignedToUid.trim(),
        status: 'pending',
        execution: const ExecutionData(done: false),
      );
      final emissionData = RecipeEmissionData.fromOrder(order);
      final emittedRecipe = recipe.copyWith(
        id: emittedRecipeRef.id,
        status: 'emitted',
        createdBy: currentUid,
        createdAt: now,
        emissionCount: 1,
        lastEmission: emissionData,
      );

      transaction.set(docRef, order.toMap());
      transaction.set(emittedRecipeRef, emittedRecipe.toMap());
      createdOrder = order;
    });

    if (createdOrder == null) {
      throw StateError('No se pudo emitir el recetario.');
    }
    return createdOrder!;
  }

  double _calculateTankCount({
    required double affectedAreaHa,
    required double tankCapacityLt,
    required double waterVolumeLHa,
  }) {
    if (affectedAreaHa <= 0 || tankCapacityLt <= 0 || waterVolumeLHa <= 0) {
      return 0;
    }
    return affectedAreaHa / (tankCapacityLt / waterVolumeLHa);
  }

  Future<RecipeEmissionData?> getLatestEmissionData(String recipeId) async {
    _assertModuleAccess();
    final snapshot = await TenantPath.applicationOrdersRef(
      _firestore,
      tenantId,
    ).where('recipeId', isEqualTo: recipeId).get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    final orders = snapshot.docs
        .map((doc) => ApplicationOrder.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
    final latest = orders.toList(growable: true)
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return RecipeEmissionData.fromOrder(latest.first);
  }

  Stream<List<ApplicationOrder>> myOrders() {
    _assertModuleAccess();
    final query = TenantPath.applicationOrdersRef(_firestore, tenantId)
        .where('assignedToUid', isEqualTo: currentUid)
        .orderBy('issuedAt', descending: true);
    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => ApplicationOrder.fromMap(doc.data(), id: doc.id))
          .toList(growable: false);
    });
  }

  Stream<List<ApplicationOrder>> watchApplicationOrders() {
    _assertModuleAccess();
    final query = TenantPath.applicationOrdersRef(
      _firestore,
      tenantId,
    ).orderBy('issuedAt', descending: true);
    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => ApplicationOrder.fromMap(doc.data(), id: doc.id))
          .toList(growable: false);
    });
  }

  Future<void> registerOrderTankApplication({
    required String orderId,
    required DateTime appliedAt,
    required double appliedTankCount,
    required double tankCapacityLt,
    required String plotName,
  }) async {
    _assertOrderExecutionAccess();
    if (appliedAt.isAfter(DateTime.now())) {
      throw StateError('La fecha y hora de aplicacion no puede ser futura.');
    }
    if (orderId.trim().isEmpty) {
      throw StateError('Orden sin id.');
    }
    if (appliedTankCount <= 0) {
      throw StateError(
        'La cantidad de tanques aplicados debe ser mayor a cero.',
      );
    }
    if (tankCapacityLt <= 0) {
      throw StateError('La capacidad del tanque debe ser mayor a cero.');
    }
    if (plotName.trim().isEmpty) {
      throw StateError('Debes seleccionar el lote aplicado.');
    }

    final orderRef = TenantPath.applicationOrderRef(
      _firestore,
      tenantId,
      orderId,
    );
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(orderRef);
      final data = snapshot.data();
      if (data == null) {
        throw StateError('Orden no encontrada.');
      }
      final order = ApplicationOrder.fromMap(data, id: snapshot.id);
      if (_access.role == TenantRole.operator &&
          !_operatorCanHandleOrder(order)) {
        throw StateError(
          'Solo puedes actualizar aplicaciones asignadas a tu usuario.',
        );
      }
      final status = order.status.trim().toLowerCase();
      if (status == 'annulled' ||
          status == 'anulado' ||
          status == 'cancelled') {
        throw StateError('No se puede registrar avance en una orden anulada.');
      }

      final plannedTankCount = order.tankCount;
      if (plannedTankCount <= 0 || order.tankCapacityLt <= 0) {
        throw StateError('La orden no tiene tanque total previsto valido.');
      }

      final previousVolume = order.execution.appliedVolumeLt > 0
          ? order.execution.appliedVolumeLt
          : order.execution.appliedTankCount * order.tankCapacityLt;
      final currentAppliedEquivalent = previousVolume / order.tankCapacityLt;
      final addedVolume = appliedTankCount * tankCapacityLt;
      final totalVolume = previousVolume + addedVolume;
      final rawAppliedTankEquivalent = totalVolume / order.tankCapacityLt;
      if (rawAppliedTankEquivalent > plannedTankCount + 0.000001) {
        final remaining = (plannedTankCount - currentAppliedEquivalent)
            .clamp(0, plannedTankCount)
            .toDouble();
        throw StateError(
          'La cantidad registrada excede el pendiente (${remaining.toStringAsFixed(2)} tanque(s)).',
        );
      }
      final appliedTankEquivalent = rawAppliedTankEquivalent
          .clamp(0, plannedTankCount)
          .toDouble();
      final completed = appliedTankEquivalent >= plannedTankCount - 0.000001;

      final progress = order.execution.tankApplications.toList(growable: true)
        ..add(
          TankApplicationEntry(
            tankCount: appliedTankCount,
            tankCapacityLt: tankCapacityLt,
            appliedVolumeLt: addedVolume,
            appliedTankEquivalent: addedVolume / order.tankCapacityLt,
            appliedAt: appliedAt,
            operatorUid: currentUid,
            plotName: plotName.trim(),
          ),
        );

      final updatePayload = <String, dynamic>{
        'status': completed ? 'completed' : 'pending',
        'execution.done': completed,
        'execution.operatorUid': currentUid,
        'execution.appliedTankCount': appliedTankEquivalent,
        'execution.appliedVolumeLt': totalVolume,
        'execution.tankApplications': progress
            .map((entry) => entry.toMap())
            .toList(growable: false),
        'updatedBy': currentUid,
        'updatedAt': Timestamp.now(),
      };
      if (completed) {
        updatePayload['execution.doneAt'] = Timestamp.fromDate(appliedAt);
      } else {
        updatePayload['execution.doneAt'] = FieldValue.delete();
      }

      transaction.update(orderRef, updatePayload);
    });
  }

  Future<void> markOrderAnnulled({required String orderId}) async {
    _assertWriteAccess();
    if (orderId.trim().isEmpty) {
      throw StateError('Orden sin id.');
    }
    await TenantPath.applicationOrderRef(_firestore, tenantId, orderId).update({
      'status': 'annulled',
      'execution.done': false,
      'execution.doneAt': FieldValue.delete(),
      'execution.operatorUid': FieldValue.delete(),
      'updatedBy': currentUid,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> deleteAnnulledOrderAndRecipe({
    required String orderId,
    required String recipeId,
  }) async {
    _assertWriteAccess();
    if (orderId.trim().isEmpty) {
      throw StateError('Orden sin id.');
    }
    if (recipeId.trim().isEmpty) {
      throw StateError('Receta emitida sin id.');
    }

    final orderRef = TenantPath.applicationOrderRef(
      _firestore,
      tenantId,
      orderId,
    );
    final recipeRef = TenantPath.recipeRef(_firestore, tenantId, recipeId);
    await _firestore.runTransaction((transaction) async {
      final orderSnapshot = await transaction.get(orderRef);
      final orderData = orderSnapshot.data();
      if (orderData == null) {
        throw StateError('Orden no encontrada.');
      }
      final order = ApplicationOrder.fromMap(orderData, id: orderSnapshot.id);
      final status = order.status.trim().toLowerCase();
      final isAnnulled =
          status == 'annulled' || status == 'anulado' || status == 'cancelled';
      if (!isAnnulled) {
        throw StateError('Solo se puede eliminar una orden anulada.');
      }

      transaction.delete(orderRef);
      transaction.delete(recipeRef);
    });
  }
}
