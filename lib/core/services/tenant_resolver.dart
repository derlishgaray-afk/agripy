import 'package:cloud_firestore/cloud_firestore.dart';

class TenantResolver {
  TenantResolver(this._firestore);

  final FirebaseFirestore _firestore;

  Future<String?> tryResolveTenantIdForUid(String uid) async {
    final snapshot = await _firestore.collection('user_tenant').doc(uid).get();
    final data = snapshot.data();
    final tenantId = data?['tenantId'];
    if (tenantId is String && tenantId.trim().isNotEmpty) {
      return tenantId.trim();
    }
    return null;
  }

  Future<String> resolveTenantIdForUid(String uid) async {
    final tenantId = await tryResolveTenantIdForUid(uid);
    if (tenantId == null) {
      throw StateError('No se encontro tenantId para el usuario actual.');
    }

    return tenantId;
  }
}
