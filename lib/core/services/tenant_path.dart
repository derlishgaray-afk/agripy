import 'package:cloud_firestore/cloud_firestore.dart';

class TenantPath {
  static String tenantDoc(String tenantId) => 'tenants/$tenantId';

  static String tenantUsersCollection(String tenantId) =>
      'tenants/$tenantId/users';

  static String tenantUserDoc(String tenantId, String uid) =>
      '${tenantUsersCollection(tenantId)}/$uid';

  static String recipesCollection(String tenantId) =>
      'tenants/$tenantId/recipes';

  static String recipeDoc(String tenantId, String recipeId) =>
      '${recipesCollection(tenantId)}/$recipeId';

  static String applicationOrdersCollection(String tenantId) =>
      'tenants/$tenantId/application_orders';

  static String applicationOrderDoc(String tenantId, String orderId) =>
      '${applicationOrdersCollection(tenantId)}/$orderId';

  static DocumentReference<Map<String, dynamic>> tenantRef(
    FirebaseFirestore firestore,
    String tenantId,
  ) {
    return firestore.doc(tenantDoc(tenantId));
  }

  static DocumentReference<Map<String, dynamic>> tenantUserRef(
    FirebaseFirestore firestore,
    String tenantId,
    String uid,
  ) {
    return firestore.doc(tenantUserDoc(tenantId, uid));
  }

  static CollectionReference<Map<String, dynamic>> recipesRef(
    FirebaseFirestore firestore,
    String tenantId,
  ) {
    return firestore.collection(recipesCollection(tenantId));
  }

  static DocumentReference<Map<String, dynamic>> recipeRef(
    FirebaseFirestore firestore,
    String tenantId,
    String recipeId,
  ) {
    return firestore.doc(recipeDoc(tenantId, recipeId));
  }

  static CollectionReference<Map<String, dynamic>> applicationOrdersRef(
    FirebaseFirestore firestore,
    String tenantId,
  ) {
    return firestore.collection(applicationOrdersCollection(tenantId));
  }

  static DocumentReference<Map<String, dynamic>> applicationOrderRef(
    FirebaseFirestore firestore,
    String tenantId,
    String orderId,
  ) {
    return firestore.doc(applicationOrderDoc(tenantId, orderId));
  }
}
