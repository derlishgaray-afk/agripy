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

class SystemSupportContact {
  const SystemSupportContact({required this.name, required this.whatsapp});

  final String name;
  final String whatsapp;
}

class SuperAdminRepo {
  SuperAdminRepo(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _superAdmins =>
      _firestore.collection('super_admins');
  DocumentReference<Map<String, dynamic>> get _systemSupportConfig =>
      _firestore.collection('system_config').doc('support');
  CollectionReference<Map<String, dynamic>> get _tenants =>
      _firestore.collection('tenants');
  CollectionReference<Map<String, dynamic>> get _tenantInvites =>
      _firestore.collection('tenant_user_invites');
  CollectionReference<Map<String, dynamic>> get _activationRequests =>
      _firestore.collection('tenant_activation_requests');

  DateTime _addMonths(DateTime value, int months) {
    final year = value.year + ((value.month - 1 + months) ~/ 12);
    final month = ((value.month - 1 + months) % 12) + 1;
    final day = value.day;
    final endOfMonth = DateTime(year, month + 1, 0).day;
    final safeDay = day <= endOfMonth ? day : endOfMonth;
    return DateTime(
      year,
      month,
      safeDay,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  Future<SuperAdminProfile?> getSuperAdminProfile(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw StateError('UID de super admin invalido.');
    }
    final snapshot = await _superAdmins.doc(normalizedUid).get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    return SuperAdminProfile.fromMap(snapshot.id, data);
  }

  Future<void> updateSuperAdminWhatsappContact({
    required String uid,
    required String whatsappContact,
  }) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw StateError('UID de super admin invalido.');
    }

    await _superAdmins.doc(normalizedUid).set({
      'whatsappContact': whatsappContact.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<SystemSupportContact?> getSystemSupportContact() async {
    final snapshot = await _systemSupportConfig.get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    final whatsapp = (data['whatsappContact'] as String? ?? '').trim();
    if (whatsapp.isEmpty) {
      return null;
    }
    final name = (data['supportName'] as String? ?? '').trim();
    return SystemSupportContact(
      name: name.isNotEmpty ? name : 'Administrador del sistema',
      whatsapp: whatsapp,
    );
  }

  Future<void> updateSystemSupportContact({
    required String updatedByUid,
    required String supportName,
    required String whatsappContact,
  }) async {
    final uid = updatedByUid.trim();
    if (uid.isEmpty) {
      throw StateError('UID de super admin invalido.');
    }
    await _systemSupportConfig.set({
      'supportName': supportName.trim(),
      'whatsappContact': whatsappContact.trim(),
      'updatedByUid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

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

  Stream<List<TenantActivationRequestModel>> watchActivationRequests({
    String? tenantId,
    TenantActivationRequestStatus? status,
  }) {
    Query<Map<String, dynamic>> query = _activationRequests;
    final normalizedTenantId = (tenantId ?? '').trim();
    if (normalizedTenantId.isNotEmpty) {
      query = query.where('tenantId', isEqualTo: normalizedTenantId);
    }
    return query.snapshots().map((snapshot) {
      var items = snapshot.docs
          .map(
            (doc) =>
                TenantActivationRequestModel.fromMap(doc.data(), id: doc.id),
          )
          .toList(growable: true);
      if (status != null) {
        items = items
            .where((item) => item.status == status)
            .toList(growable: true);
      }
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List.unmodifiable(items);
    });
  }

  Future<void> createTenantActivationRequest({
    required String tenantId,
    required String tenantName,
    required String requesterUid,
    required String requesterName,
    required String requesterEmail,
    required TenantPlan requestedPlan,
    DateTime? requestedCustomEndsAt,
    required String reason,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedRequesterUid = requesterUid.trim();
    final normalizedReason = reason.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Tenant invalido para solicitud.');
    }
    if (normalizedRequesterUid.isEmpty) {
      throw StateError('Usuario invalido para solicitud.');
    }
    if (requestedPlan == TenantPlan.trial) {
      throw StateError('El plan trial no requiere solicitud de activacion.');
    }
    if (normalizedReason.isEmpty) {
      throw StateError('Debes indicar el motivo de activacion.');
    }
    if (requestedPlan == TenantPlan.custom) {
      if (requestedCustomEndsAt == null ||
          !requestedCustomEndsAt.isAfter(DateTime.now())) {
        throw StateError(
          'Para plan custom debes definir una fecha de vigencia futura.',
        );
      }
    }

    final duplicateSnapshot = await _activationRequests
        .where('requesterUid', isEqualTo: normalizedRequesterUid)
        .get();
    final hasPendingForTenant = duplicateSnapshot.docs.any((doc) {
      final data = doc.data();
      final tenantId = (data['tenantId'] as String? ?? '').trim();
      final status = (data['status'] as String? ?? '').trim().toLowerCase();
      return tenantId == normalizedTenantId && status == 'pending';
    });
    if (hasPendingForTenant) {
      throw StateError('Ya existe una solicitud pendiente para este usuario.');
    }

    final now = DateTime.now();
    final request = TenantActivationRequestModel(
      tenantId: normalizedTenantId,
      tenantName: tenantName.trim(),
      requesterUid: normalizedRequesterUid,
      requesterName: requesterName.trim(),
      requesterEmail: requesterEmail.trim(),
      requestedPlan: requestedPlan,
      requestedCustomEndsAt: requestedPlan == TenantPlan.custom
          ? requestedCustomEndsAt
          : null,
      reason: normalizedReason,
      status: TenantActivationRequestStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
    await _activationRequests.doc().set(request.toMap());
  }

  Future<void> approveActivationRequest({
    required String requestId,
    required String resolvedByUid,
    required TenantPlan approvedPlan,
    DateTime? customEndsAt,
    String? resolvedNotes,
  }) async {
    final normalizedRequestId = requestId.trim();
    final normalizedResolver = resolvedByUid.trim();
    if (normalizedRequestId.isEmpty) {
      throw StateError('Solicitud invalida.');
    }
    if (normalizedResolver.isEmpty) {
      throw StateError('Usuario resolutor invalido.');
    }
    if (approvedPlan == TenantPlan.trial) {
      throw StateError('No se puede aprobar activacion al plan trial.');
    }

    final now = DateTime.now();
    DateTime resolvedAccessEndsAt;
    if (approvedPlan == TenantPlan.basic) {
      resolvedAccessEndsAt = _addMonths(now, 1);
    } else if (approvedPlan == TenantPlan.pro) {
      resolvedAccessEndsAt = _addMonths(now, 12);
    } else {
      if (customEndsAt == null || !customEndsAt.isAfter(now)) {
        throw StateError('Para plan custom debes indicar una vigencia futura.');
      }
      resolvedAccessEndsAt = customEndsAt;
    }

    final requestRef = _activationRequests.doc(normalizedRequestId);
    await _firestore.runTransaction((transaction) async {
      final requestSnapshot = await transaction.get(requestRef);
      final requestData = requestSnapshot.data();
      if (requestData == null) {
        throw StateError('Solicitud no encontrada.');
      }
      final request = TenantActivationRequestModel.fromMap(
        requestData,
        id: requestSnapshot.id,
      );
      if (request.status != TenantActivationRequestStatus.pending) {
        throw StateError('La solicitud ya fue procesada.');
      }

      final tenantRef = _tenants.doc(request.tenantId);
      final tenantSnapshot = await transaction.get(tenantRef);
      if (!tenantSnapshot.exists) {
        throw StateError('Tenant no encontrado para activar.');
      }

      transaction.update(tenantRef, {
        'plan': tenantPlanToString(approvedPlan),
        'accessEndsAt': Timestamp.fromDate(resolvedAccessEndsAt),
        'trialEndsAt': FieldValue.delete(),
        'subscriptionStatus': tenantSubscriptionStatusToString(
          TenantSubscriptionStatus.active,
        ),
        'updatedBy': normalizedResolver,
        'updatedAt': Timestamp.fromDate(now),
      });
      transaction.update(requestRef, {
        'status': tenantActivationRequestStatusToString(
          TenantActivationRequestStatus.approved,
        ),
        'approvedPlan': tenantPlanToString(approvedPlan),
        'approvedAccessEndsAt': Timestamp.fromDate(resolvedAccessEndsAt),
        'resolvedByUid': normalizedResolver,
        'resolvedAt': Timestamp.fromDate(now),
        'resolvedNotes': (resolvedNotes ?? '').trim(),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<void> rejectActivationRequest({
    required String requestId,
    required String resolvedByUid,
    String? resolvedNotes,
  }) async {
    final normalizedRequestId = requestId.trim();
    final normalizedResolver = resolvedByUid.trim();
    if (normalizedRequestId.isEmpty) {
      throw StateError('Solicitud invalida.');
    }
    if (normalizedResolver.isEmpty) {
      throw StateError('Usuario resolutor invalido.');
    }
    final now = DateTime.now();
    final requestRef = _activationRequests.doc(normalizedRequestId);
    await _firestore.runTransaction((transaction) async {
      final requestSnapshot = await transaction.get(requestRef);
      final requestData = requestSnapshot.data();
      if (requestData == null) {
        throw StateError('Solicitud no encontrada.');
      }
      final request = TenantActivationRequestModel.fromMap(
        requestData,
        id: requestSnapshot.id,
      );
      if (request.status != TenantActivationRequestStatus.pending) {
        throw StateError('La solicitud ya fue procesada.');
      }

      transaction.update(requestRef, {
        'status': tenantActivationRequestStatusToString(
          TenantActivationRequestStatus.rejected,
        ),
        'resolvedByUid': normalizedResolver,
        'resolvedAt': Timestamp.fromDate(now),
        'resolvedNotes': (resolvedNotes ?? '').trim(),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
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
      'displayName': tenantUser.displayName,
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
        'La invitación contiene módulos no contratados por el tenant: ${invalidModules.join(', ')}',
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
      throw StateError('Código de invitación inválido o vencido.');
    }

    final inviteRef = _tenantInvites.doc(invite.id!);
    final linkRef = _firestore.collection('user_tenant').doc(uid);
    final linkSnapshot = await linkRef.get();
    final existingLinkData = linkSnapshot.data();
    final existingTenantId = (existingLinkData?['tenantId'] as String?)?.trim();
    if (existingTenantId != null &&
        existingTenantId.isNotEmpty &&
        existingTenantId != invite.tenantId) {
      throw UserTenantConflictException(existingTenantId);
    }

    final tenantUserRef = _tenants
        .doc(invite.tenantId)
        .collection('users')
        .doc(uid);
    final now = Timestamp.now();
    final batch = _firestore.batch();

    batch.set(tenantUserRef, {
      'displayName': invite.displayName,
      'email': invite.email,
      'emailLower': invite.email.trim().toLowerCase(),
      'role': tenantUserRoleToString(invite.role),
      'status': accountStatusToString(invite.status),
      'activeModules': invite.activeModules,
      'onboardingInviteCode': invite.inviteCode,
      'createdAt': now,
      'createdBy': invite.createdBy,
    }, SetOptions(merge: true));

    if (!linkSnapshot.exists) {
      batch.set(linkRef, {
        'tenantId': invite.tenantId,
        'displayName': invite.displayName,
        'onboardingInviteCode': invite.inviteCode,
        'createdAt': now,
      }, SetOptions(merge: true));
    }

    batch.update(inviteRef, {
      'claimedByUid': uid,
      'claimedAt': now,
      'inviteState': inviteStatusToString(InviteStatus.claimed),
    });

    await batch.commit();
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
