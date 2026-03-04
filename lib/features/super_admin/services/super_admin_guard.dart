import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models.dart';

class SuperAdminGuard {
  SuperAdminGuard(this._firestore);

  final FirebaseFirestore _firestore;

  Future<SuperAdminProfile?> loadActiveSuperAdmin(String uid) async {
    final snapshot = await _firestore.collection('super_admins').doc(uid).get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }

    final profile = SuperAdminProfile.fromMap(uid, data);
    if (!profile.isActive) {
      return null;
    }

    return profile;
  }

  Future<bool> isSuperAdmin(String uid) async {
    final profile = await loadActiveSuperAdmin(uid);
    return profile != null;
  }
}
