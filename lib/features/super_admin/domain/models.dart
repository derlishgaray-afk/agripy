import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _parseDateTime(dynamic value) {
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
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}

DateTime? _parseNullableDateTime(dynamic value) {
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

enum TenantStatus { active, suspended }

TenantStatus tenantStatusFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'active':
      return TenantStatus.active;
    case 'suspended':
      return TenantStatus.suspended;
    default:
      return TenantStatus.active;
  }
}

String tenantStatusToString(TenantStatus value) {
  switch (value) {
    case TenantStatus.active:
      return 'active';
    case TenantStatus.suspended:
      return 'suspended';
  }
}

enum TenantPlan { trial, basic, pro, custom }

TenantPlan tenantPlanFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'trial':
      return TenantPlan.trial;
    case 'basic':
      return TenantPlan.basic;
    case 'pro':
      return TenantPlan.pro;
    case 'custom':
      return TenantPlan.custom;
    default:
      return TenantPlan.trial;
  }
}

String tenantPlanToString(TenantPlan value) {
  switch (value) {
    case TenantPlan.trial:
      return 'trial';
    case TenantPlan.basic:
      return 'basic';
    case TenantPlan.pro:
      return 'pro';
    case TenantPlan.custom:
      return 'custom';
  }
}

enum TenantSubscriptionStatus { active, pendingApproval, expired }

TenantSubscriptionStatus tenantSubscriptionStatusFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'active':
      return TenantSubscriptionStatus.active;
    case 'pending_approval':
      return TenantSubscriptionStatus.pendingApproval;
    case 'expired':
      return TenantSubscriptionStatus.expired;
    default:
      return TenantSubscriptionStatus.active;
  }
}

String tenantSubscriptionStatusToString(TenantSubscriptionStatus value) {
  switch (value) {
    case TenantSubscriptionStatus.active:
      return 'active';
    case TenantSubscriptionStatus.pendingApproval:
      return 'pending_approval';
    case TenantSubscriptionStatus.expired:
      return 'expired';
  }
}

enum TenantUserRole { admin, engineer, operator }

TenantUserRole tenantUserRoleFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'admin':
      return TenantUserRole.admin;
    case 'engineer':
      return TenantUserRole.engineer;
    case 'operator':
      return TenantUserRole.operator;
    default:
      return TenantUserRole.operator;
  }
}

String tenantUserRoleToString(TenantUserRole value) {
  switch (value) {
    case TenantUserRole.admin:
      return 'admin';
    case TenantUserRole.engineer:
      return 'engineer';
    case TenantUserRole.operator:
      return 'operator';
  }
}

enum AccountStatus { active, suspended }

AccountStatus accountStatusFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'active':
      return AccountStatus.active;
    case 'suspended':
      return AccountStatus.suspended;
    default:
      return AccountStatus.active;
  }
}

String accountStatusToString(AccountStatus value) {
  switch (value) {
    case AccountStatus.active:
      return 'active';
    case AccountStatus.suspended:
      return 'suspended';
  }
}

class SuperAdminProfile {
  const SuperAdminProfile({
    required this.uid,
    required this.email,
    required this.name,
    required this.status,
    this.whatsappContact = '',
  });

  final String uid;
  final String email;
  final String name;
  final AccountStatus status;
  final String whatsappContact;

  bool get isActive => status == AccountStatus.active;

  factory SuperAdminProfile.fromMap(String uid, Map<String, dynamic> map) {
    return SuperAdminProfile(
      uid: uid,
      email: (map['email'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      status: accountStatusFromString((map['status'] as String? ?? 'active')),
      whatsappContact: (map['whatsappContact'] as String? ?? '').trim(),
    );
  }
}

class TenantModel {
  const TenantModel({
    this.id,
    required this.name,
    required this.status,
    required this.plan,
    required this.modules,
    required this.createdAt,
    required this.createdBy,
    this.trialEndsAt,
    this.accessEndsAt,
    this.subscriptionStatus = TenantSubscriptionStatus.active,
  });

  final String? id;
  final String name;
  final TenantStatus status;
  final TenantPlan plan;
  final List<String> modules;
  final DateTime createdAt;
  final String createdBy;
  final DateTime? trialEndsAt;
  final DateTime? accessEndsAt;
  final TenantSubscriptionStatus subscriptionStatus;

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'status': tenantStatusToString(status),
      'plan': tenantPlanToString(plan),
      'modules': modules,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'trialEndsAt': trialEndsAt == null
          ? null
          : Timestamp.fromDate(trialEndsAt!),
      'accessEndsAt': accessEndsAt == null
          ? null
          : Timestamp.fromDate(accessEndsAt!),
      'subscriptionStatus': tenantSubscriptionStatusToString(
        subscriptionStatus,
      ),
    };
  }

  TenantModel copyWith({
    String? id,
    String? name,
    TenantStatus? status,
    TenantPlan? plan,
    List<String>? modules,
    DateTime? createdAt,
    String? createdBy,
    DateTime? trialEndsAt,
    DateTime? accessEndsAt,
    TenantSubscriptionStatus? subscriptionStatus,
  }) {
    return TenantModel(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      plan: plan ?? this.plan,
      modules: modules ?? this.modules,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      accessEndsAt: accessEndsAt ?? this.accessEndsAt,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
    );
  }

  factory TenantModel.fromMap(Map<String, dynamic> map, {String? id}) {
    final modulesRaw = map['modules'];
    final modules = <String>[];
    if (modulesRaw is List) {
      for (final item in modulesRaw) {
        if (item is String && item.trim().isNotEmpty) {
          modules.add(item.trim());
        }
      }
    }

    return TenantModel(
      id: id,
      name: (map['name'] as String? ?? '').trim(),
      status: tenantStatusFromString((map['status'] as String? ?? 'active')),
      plan: tenantPlanFromString((map['plan'] as String? ?? 'trial')),
      modules: List.unmodifiable(modules),
      createdAt: _parseDateTime(map['createdAt']),
      createdBy: (map['createdBy'] as String? ?? '').trim(),
      trialEndsAt: _parseNullableDateTime(map['trialEndsAt']),
      accessEndsAt: _parseNullableDateTime(map['accessEndsAt']),
      subscriptionStatus: tenantSubscriptionStatusFromString(
        (map['subscriptionStatus'] as String? ?? 'active').trim(),
      ),
    );
  }
}

enum TenantActivationRequestStatus { pending, approved, rejected }

TenantActivationRequestStatus tenantActivationRequestStatusFromString(
  String raw,
) {
  switch (raw.trim().toLowerCase()) {
    case 'pending':
      return TenantActivationRequestStatus.pending;
    case 'approved':
      return TenantActivationRequestStatus.approved;
    case 'rejected':
      return TenantActivationRequestStatus.rejected;
    default:
      return TenantActivationRequestStatus.pending;
  }
}

String tenantActivationRequestStatusToString(
  TenantActivationRequestStatus value,
) {
  switch (value) {
    case TenantActivationRequestStatus.pending:
      return 'pending';
    case TenantActivationRequestStatus.approved:
      return 'approved';
    case TenantActivationRequestStatus.rejected:
      return 'rejected';
  }
}

class TenantActivationRequestModel {
  const TenantActivationRequestModel({
    this.id,
    required this.tenantId,
    required this.tenantName,
    required this.requesterUid,
    required this.requesterName,
    required this.requesterEmail,
    required this.requestedPlan,
    this.requestedCustomEndsAt,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.resolvedByUid,
    this.resolvedAt,
    this.resolvedNotes,
  });

  final String? id;
  final String tenantId;
  final String tenantName;
  final String requesterUid;
  final String requesterName;
  final String requesterEmail;
  final TenantPlan requestedPlan;
  final DateTime? requestedCustomEndsAt;
  final String reason;
  final TenantActivationRequestStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? resolvedByUid;
  final DateTime? resolvedAt;
  final String? resolvedNotes;

  Map<String, dynamic> toMap() {
    return {
      'tenantId': tenantId,
      'tenantName': tenantName,
      'requesterUid': requesterUid,
      'requesterName': requesterName,
      'requesterEmail': requesterEmail,
      'requestedPlan': tenantPlanToString(requestedPlan),
      'requestedCustomEndsAt': requestedCustomEndsAt == null
          ? null
          : Timestamp.fromDate(requestedCustomEndsAt!),
      'reason': reason,
      'status': tenantActivationRequestStatusToString(status),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      'resolvedByUid': resolvedByUid,
      'resolvedAt': resolvedAt == null ? null : Timestamp.fromDate(resolvedAt!),
      'resolvedNotes': resolvedNotes,
    };
  }

  TenantActivationRequestModel copyWith({
    String? id,
    String? tenantId,
    String? tenantName,
    String? requesterUid,
    String? requesterName,
    String? requesterEmail,
    TenantPlan? requestedPlan,
    DateTime? requestedCustomEndsAt,
    String? reason,
    TenantActivationRequestStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? resolvedByUid,
    DateTime? resolvedAt,
    String? resolvedNotes,
  }) {
    return TenantActivationRequestModel(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      tenantName: tenantName ?? this.tenantName,
      requesterUid: requesterUid ?? this.requesterUid,
      requesterName: requesterName ?? this.requesterName,
      requesterEmail: requesterEmail ?? this.requesterEmail,
      requestedPlan: requestedPlan ?? this.requestedPlan,
      requestedCustomEndsAt:
          requestedCustomEndsAt ?? this.requestedCustomEndsAt,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      resolvedByUid: resolvedByUid ?? this.resolvedByUid,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedNotes: resolvedNotes ?? this.resolvedNotes,
    );
  }

  factory TenantActivationRequestModel.fromMap(
    Map<String, dynamic> map, {
    String? id,
  }) {
    return TenantActivationRequestModel(
      id: id,
      tenantId: (map['tenantId'] as String? ?? '').trim(),
      tenantName: (map['tenantName'] as String? ?? '').trim(),
      requesterUid: (map['requesterUid'] as String? ?? '').trim(),
      requesterName: (map['requesterName'] as String? ?? '').trim(),
      requesterEmail: (map['requesterEmail'] as String? ?? '').trim(),
      requestedPlan: tenantPlanFromString(
        (map['requestedPlan'] as String? ?? 'basic').trim(),
      ),
      requestedCustomEndsAt: _parseNullableDateTime(
        map['requestedCustomEndsAt'],
      ),
      reason: (map['reason'] as String? ?? '').trim(),
      status: tenantActivationRequestStatusFromString(
        (map['status'] as String? ?? 'pending').trim(),
      ),
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseNullableDateTime(map['updatedAt']),
      resolvedByUid: (map['resolvedByUid'] as String?)?.trim(),
      resolvedAt: _parseNullableDateTime(map['resolvedAt']),
      resolvedNotes: (map['resolvedNotes'] as String?)?.trim(),
    );
  }
}

class TenantUserModel {
  const TenantUserModel({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.status,
    required this.activeModules,
    required this.createdAt,
    required this.createdBy,
  });

  final String uid;
  final String displayName;
  final TenantUserRole role;
  final AccountStatus status;
  final List<String> activeModules;
  final DateTime createdAt;
  final String createdBy;

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'role': tenantUserRoleToString(role),
      'status': accountStatusToString(status),
      'activeModules': activeModules,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
    };
  }

  factory TenantUserModel.fromMap(String uid, Map<String, dynamic> map) {
    final modulesRaw = map['activeModules'];
    final modules = <String>[];
    if (modulesRaw is List) {
      for (final item in modulesRaw) {
        if (item is String && item.trim().isNotEmpty) {
          modules.add(item.trim());
        }
      }
    }

    return TenantUserModel(
      uid: uid,
      displayName: (map['displayName'] as String? ?? '').trim(),
      role: tenantUserRoleFromString((map['role'] as String? ?? 'operator')),
      status: accountStatusFromString((map['status'] as String? ?? 'active')),
      activeModules: List.unmodifiable(modules),
      createdAt: _parseDateTime(map['createdAt']),
      createdBy: (map['createdBy'] as String? ?? '').trim(),
    );
  }
}

class UserTenantLink {
  const UserTenantLink({
    required this.uid,
    required this.tenantId,
    required this.createdAt,
    this.displayName = '',
  });

  final String uid;
  final String tenantId;
  final DateTime createdAt;
  final String displayName;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'tenantId': tenantId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
    if (displayName.trim().isNotEmpty) {
      map['displayName'] = displayName.trim();
    }
    return map;
  }

  factory UserTenantLink.fromMap(String uid, Map<String, dynamic> map) {
    return UserTenantLink(
      uid: uid,
      tenantId: (map['tenantId'] as String? ?? '').trim(),
      createdAt: _parseDateTime(map['createdAt']),
      displayName: (map['displayName'] as String? ?? '').trim(),
    );
  }
}

class TenantFormArgs {
  const TenantFormArgs({required this.actorUid, this.tenant});

  final String actorUid;
  final TenantModel? tenant;
}

class TenantDetailArgs {
  const TenantDetailArgs({required this.tenantId, required this.actorUid});

  final String tenantId;
  final String actorUid;
}

class TenantUsersArgs {
  const TenantUsersArgs({required this.tenantId, required this.actorUid});

  final String tenantId;
  final String actorUid;
}

class TenantUserFormArgs {
  const TenantUserFormArgs({
    required this.tenantId,
    required this.actorUid,
    this.uid,
  });

  final String tenantId;
  final String actorUid;
  final String? uid;
}
