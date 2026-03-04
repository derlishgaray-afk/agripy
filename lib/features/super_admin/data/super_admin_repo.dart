import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

import '../domain/models.dart';

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

class UserTenantConflictException implements Exception {
  UserTenantConflictException(this.existingTenantId);

  final String existingTenantId;

  @override
  String toString() {
    return 'UID ya vinculado a otro tenant: $existingTenantId';
  }
}

class SuperAdminRepo {
  SuperAdminRepo(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _tenants =>
      _firestore.collection('tenants');
  CollectionReference<Map<String, dynamic>> get _tenantInvites =>
      _firestore.collection('tenant_user_invites');

  Stream<List<TenantModel>> watchTenants() {
    return _tenants.orderBy('createdAt', descending: true).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => TenantModel.fromMap(doc.data(), id: doc.id))
          .toList(growable: false);
    });
  }

  Stream<TenantModel?> watchTenantById(String tenantId) {
    return _tenants.doc(tenantId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return null;
      }
      return TenantModel.fromMap(data, id: snapshot.id);
    });
  }

  Future<TenantModel?> getTenantById(String tenantId) async {
    final snapshot = await _tenants.doc(tenantId).get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    return TenantModel.fromMap(data, id: snapshot.id);
  }

  Future<String> createTenant(TenantModel tenant) async {
    final docRef = _tenants.doc();
    final payload = tenant.copyWith(id: docRef.id);
    await docRef.set(payload.toMap());
    return docRef.id;
  }

  Future<void> updateTenant(TenantModel tenant) async {
    final tenantId = tenant.id;
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('Tenant sin id no puede actualizarse.');
    }
    await _tenants.doc(tenantId).update(tenant.toMap());
  }

  Stream<List<TenantUserModel>> watchTenantUsers(String tenantId) {
    return _tenants
        .doc(tenantId)
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => TenantUserModel.fromMap(doc.id, doc.data()))
              .toList(growable: false);
        });
  }

  Future<TenantUserModel?> getTenantUser(String tenantId, String uid) async {
    final snapshot = await _tenants
        .doc(tenantId)
        .collection('users')
        .doc(uid)
        .get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    return TenantUserModel.fromMap(uid, data);
  }

  Future<void> upsertTenantUserAndLink({
    required String tenantId,
    required TenantUserModel tenantUser,
    required bool allowReassignUserTenant,
  }) async {
    final tenant = await getTenantById(tenantId);
    if (tenant == null) {
      throw StateError('Tenant no encontrado.');
    }

    final tenantModules = tenant.modules.toSet();
    final invalidModules = tenantUser.activeModules
        .where((module) => !tenantModules.contains(module))
        .toList(growable: false);
    if (invalidModules.isNotEmpty) {
      throw StateError(
        'El usuario contiene modulos no contratados por el tenant: ${invalidModules.join(', ')}',
      );
    }

    final linkRef = _firestore.collection('user_tenant').doc(tenantUser.uid);
    final existingLinkSnapshot = await linkRef.get();
    final existingLink = existingLinkSnapshot.data();
    final existingTenantId = (existingLink?['tenantId'] as String?)?.trim();
    final existingLinkCreatedAt = existingLink == null
        ? null
        : existingLink['createdAt'];

    if (existingTenantId != null &&
        existingTenantId.isNotEmpty &&
        existingTenantId != tenantId &&
        !allowReassignUserTenant) {
      throw UserTenantConflictException(existingTenantId);
    }

    final userDocRef = _tenants
        .doc(tenantId)
        .collection('users')
        .doc(tenantUser.uid);
    final existingTenantUserSnapshot = await userDocRef.get();
    final existingTenantUserData = existingTenantUserSnapshot.data();
    final createdAt =
        _parseDateTime(existingTenantUserData?['createdAt']) ??
        tenantUser.createdAt;
    final createdBy =
        (existingTenantUserData?['createdBy'] as String?)?.trim().isNotEmpty ==
            true
        ? (existingTenantUserData?['createdBy'] as String).trim()
        : tenantUser.createdBy;

    final payload = {
      ...tenantUser.toMap(),
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
    };

    await userDocRef.set(payload, SetOptions(merge: true));
    await linkRef.set({
      'tenantId': tenantId,
      'createdAt': existingLinkSnapshot.exists
          ? existingLinkCreatedAt ?? Timestamp.now()
          : Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<TenantInviteModel> createTenantInvite({
    required String tenantId,
    required String email,
    required String displayName,
    required TenantUserRole role,
    required AccountStatus status,
    required List<String> activeModules,
    required String createdBy,
    DateTime? expiresAt,
  }) async {
    final tenant = await getTenantById(tenantId);
    if (tenant == null) {
      throw StateError('Tenant no encontrado.');
    }

    final tenantModules = tenant.modules.toSet();
    final invalidModules = activeModules
        .where((module) => !tenantModules.contains(module))
        .toList(growable: false);
    if (invalidModules.isNotEmpty) {
      throw StateError(
        'La invitacion contiene modulos no contratados por el tenant: ${invalidModules.join(', ')}',
      );
    }

    final now = DateTime.now();
    final inviteCode = await _generateUniqueInviteCode();
    final docRef = _tenantInvites.doc(inviteCode);
    final invite = TenantInviteModel(
      id: inviteCode,
      tenantId: tenantId,
      email: email.trim(),
      displayName: displayName.trim(),
      role: role,
      status: status,
      activeModules: activeModules,
      inviteCode: inviteCode,
      createdAt: now,
      createdBy: createdBy,
      expiresAt: expiresAt,
    );

    await docRef.set({
      ...invite.toMap(),
      'inviteState': inviteStatusToString(InviteStatus.pending),
    });

    return invite;
  }

  Future<TenantInviteModel?> findPendingInviteByCode(String inviteCode) async {
    final normalizedCode = inviteCode.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      return null;
    }

    final snapshot = await _tenantInvites.doc(normalizedCode).get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }

    final invite = TenantInviteModel.fromMap(data, id: snapshot.id);
    if (invite.claimedAt != null) {
      return null;
    }
    if (invite.expiresAt != null &&
        invite.expiresAt!.isBefore(DateTime.now())) {
      return null;
    }
    return invite;
  }

  Future<void> claimInviteWithCode({
    required String uid,
    required String inviteCode,
  }) async {
    final invite = await findPendingInviteByCode(inviteCode);
    if (invite == null || invite.id == null) {
      throw StateError('Codigo de invitacion invalido o vencido.');
    }

    final inviteRef = _tenantInvites.doc(invite.id!);
    await _firestore.runTransaction((transaction) async {
      final inviteSnapshot = await transaction.get(inviteRef);
      final inviteData = inviteSnapshot.data();
      if (inviteData == null) {
        throw StateError('La invitacion no existe.');
      }

      final currentInvite = TenantInviteModel.fromMap(
        inviteData,
        id: inviteSnapshot.id,
      );
      if (currentInvite.claimedAt != null) {
        throw StateError('Esta invitacion ya fue utilizada.');
      }
      if (currentInvite.expiresAt != null &&
          currentInvite.expiresAt!.isBefore(DateTime.now())) {
        throw StateError('La invitacion esta vencida.');
      }

      final tenantRef = _tenants.doc(currentInvite.tenantId);
      final tenantSnapshot = await transaction.get(tenantRef);
      final tenantData = tenantSnapshot.data();
      if (tenantData == null) {
        throw StateError('Tenant de la invitacion no encontrado.');
      }
      final tenant = TenantModel.fromMap(tenantData, id: tenantSnapshot.id);

      final tenantModules = tenant.modules.toSet();
      final invalidModules = currentInvite.activeModules
          .where((module) => !tenantModules.contains(module))
          .toList(growable: false);
      if (invalidModules.isNotEmpty) {
        throw StateError(
          'La invitacion tiene modulos fuera del plan del tenant.',
        );
      }

      final linkRef = _firestore.collection('user_tenant').doc(uid);
      final linkSnapshot = await transaction.get(linkRef);
      final existingLinkData = linkSnapshot.data();
      final existingTenantId = (existingLinkData?['tenantId'] as String?)
          ?.trim();
      if (existingTenantId != null &&
          existingTenantId.isNotEmpty &&
          existingTenantId != currentInvite.tenantId) {
        throw UserTenantConflictException(existingTenantId);
      }

      final tenantUserRef = _tenants
          .doc(currentInvite.tenantId)
          .collection('users')
          .doc(uid);
      final tenantUserSnapshot = await transaction.get(tenantUserRef);
      final existingTenantUserData = tenantUserSnapshot.data();

      final createdAt =
          _parseDateTime(existingTenantUserData?['createdAt']) ??
          DateTime.now();
      final createdBy =
          (existingTenantUserData?['createdBy'] as String?)
                  ?.trim()
                  .isNotEmpty ==
              true
          ? (existingTenantUserData?['createdBy'] as String).trim()
          : currentInvite.createdBy;

      transaction.set(tenantUserRef, {
        'displayName': currentInvite.displayName,
        'role': tenantUserRoleToString(currentInvite.role),
        'status': accountStatusToString(currentInvite.status),
        'activeModules': currentInvite.activeModules,
        'onboardingInviteCode': currentInvite.inviteCode,
        'createdAt': Timestamp.fromDate(createdAt),
        'createdBy': createdBy,
      }, SetOptions(merge: true));

      transaction.set(linkRef, {
        'tenantId': currentInvite.tenantId,
        'onboardingInviteCode': currentInvite.inviteCode,
        'createdAt': linkSnapshot.exists
            ? (existingLinkData?['createdAt'] ?? Timestamp.now())
            : Timestamp.now(),
      }, SetOptions(merge: true));

      transaction.update(inviteRef, {
        'claimedByUid': uid,
        'claimedAt': Timestamp.now(),
        'inviteState': inviteStatusToString(InviteStatus.claimed),
      });
    });
  }

  Future<String> _generateUniqueInviteCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();

    for (var i = 0; i < 5; i++) {
      final code = List.generate(
        8,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
      final existing = await _tenantInvites.doc(code).get();
      if (!existing.exists) {
        return code;
      }
    }

    return DateTime.now().millisecondsSinceEpoch.toString().substring(5, 13);
  }
}
