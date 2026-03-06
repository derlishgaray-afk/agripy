import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/modules.dart';
import '../../../core/services/access_controller.dart';
import '../../../core/services/tenant_path.dart';
import '../domain/models.dart';

class RecetarioRepo {
  RecetarioRepo({
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
      throw StateError('Modulo recetario_agronomico no habilitado.');
    }
  }

  void _assertWriteAccess() {
    _assertModuleAccess();
    if (_access.role == TenantRole.operator) {
      throw StateError('El rol operator no puede modificar recetarios.');
    }
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
    required String code,
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

    final batch = _firestore.batch();
    batch.set(docRef, order.toMap());
    batch.set(emittedRecipeRef, emittedRecipe.toMap());
    await batch.commit();
    return order;
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
}
