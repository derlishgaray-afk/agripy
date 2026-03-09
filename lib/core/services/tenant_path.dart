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

  static String fieldsCollection(String tenantId) => 'tenants/$tenantId/fields';

  static String fieldDoc(String tenantId, String fieldId) =>
      '${fieldsCollection(tenantId)}/$fieldId';

  static String inputsCollection(String tenantId) => 'tenants/$tenantId/inputs';

  static String inputDoc(String tenantId, String inputId) =>
      '${inputsCollection(tenantId)}/$inputId';

  static String countersCollection(String tenantId) =>
      'tenants/$tenantId/counters';

  static String counterDoc(String tenantId, String counterId) =>
      '${countersCollection(tenantId)}/$counterId';

  static String operatorsCollection(String tenantId) =>
      'tenants/$tenantId/operators';

  static String operatorDoc(String tenantId, String operatorId) =>
      '${operatorsCollection(tenantId)}/$operatorId';

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

  static CollectionReference<Map<String, dynamic>> fieldsRef(
    FirebaseFirestore firestore,
    String tenantId,
  ) {
    return firestore.collection(fieldsCollection(tenantId));
  }

  static DocumentReference<Map<String, dynamic>> fieldRef(
    FirebaseFirestore firestore,
    String tenantId,
    String fieldId,
  ) {
    return firestore.doc(fieldDoc(tenantId, fieldId));
  }

  static CollectionReference<Map<String, dynamic>> inputsRef(
    FirebaseFirestore firestore,
    String tenantId,
  ) {
    return firestore.collection(inputsCollection(tenantId));
  }

  static DocumentReference<Map<String, dynamic>> inputRef(
    FirebaseFirestore firestore,
    String tenantId,
    String inputId,
  ) {
    return firestore.doc(inputDoc(tenantId, inputId));
  }

  static CollectionReference<Map<String, dynamic>> countersRef(
    FirebaseFirestore firestore,
    String tenantId,
  ) {
    return firestore.collection(countersCollection(tenantId));
  }

  static DocumentReference<Map<String, dynamic>> counterRef(
    FirebaseFirestore firestore,
    String tenantId,
    String counterId,
  ) {
    return firestore.doc(counterDoc(tenantId, counterId));
  }

  static CollectionReference<Map<String, dynamic>> operatorsRef(
    FirebaseFirestore firestore,
    String tenantId,
  ) {
    return firestore.collection(operatorsCollection(tenantId));
  }

  static DocumentReference<Map<String, dynamic>> operatorRef(
    FirebaseFirestore firestore,
    String tenantId,
    String operatorId,
  ) {
    return firestore.doc(operatorDoc(tenantId, operatorId));
  }
}
