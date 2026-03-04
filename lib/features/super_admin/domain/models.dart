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

enum InviteStatus { pending, claimed, revoked, expired }

InviteStatus inviteStatusFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'pending':
      return InviteStatus.pending;
    case 'claimed':
      return InviteStatus.claimed;
    case 'revoked':
      return InviteStatus.revoked;
    case 'expired':
      return InviteStatus.expired;
    default:
      return InviteStatus.pending;
  }
}

String inviteStatusToString(InviteStatus value) {
  switch (value) {
    case InviteStatus.pending:
      return 'pending';
    case InviteStatus.claimed:
      return 'claimed';
    case InviteStatus.revoked:
      return 'revoked';
    case InviteStatus.expired:
      return 'expired';
  }
}

class SuperAdminProfile {
  const SuperAdminProfile({
    required this.uid,
    required this.email,
    required this.name,
    required this.status,
  });

  final String uid;
  final String email;
  final String name;
  final AccountStatus status;

  bool get isActive => status == AccountStatus.active;

  factory SuperAdminProfile.fromMap(String uid, Map<String, dynamic> map) {
    return SuperAdminProfile(
      uid: uid,
      email: (map['email'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      status: accountStatusFromString((map['status'] as String? ?? 'active')),
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
  });

  final String? id;
  final String name;
  final TenantStatus status;
  final TenantPlan plan;
  final List<String> modules;
  final DateTime createdAt;
  final String createdBy;

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'status': tenantStatusToString(status),
      'plan': tenantPlanToString(plan),
      'modules': modules,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
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
  }) {
    return TenantModel(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      plan: plan ?? this.plan,
      modules: modules ?? this.modules,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
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
  });

  final String uid;
  final String tenantId;
  final DateTime createdAt;

  Map<String, dynamic> toMap() {
    return {'tenantId': tenantId, 'createdAt': Timestamp.fromDate(createdAt)};
  }

  factory UserTenantLink.fromMap(String uid, Map<String, dynamic> map) {
    return UserTenantLink(
      uid: uid,
      tenantId: (map['tenantId'] as String? ?? '').trim(),
      createdAt: _parseDateTime(map['createdAt']),
    );
  }
}

class TenantInviteModel {
  const TenantInviteModel({
    this.id,
    required this.tenantId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
    required this.activeModules,
    required this.inviteCode,
    required this.createdAt,
    required this.createdBy,
    this.expiresAt,
    this.claimedByUid,
    this.claimedAt,
  });

  final String? id;
  final String tenantId;
  final String email;
  final String displayName;
  final TenantUserRole role;
  final AccountStatus status;
  final List<String> activeModules;
  final String inviteCode;
  final DateTime createdAt;
  final String createdBy;
  final DateTime? expiresAt;
  final String? claimedByUid;
  final DateTime? claimedAt;

  bool get isPending => claimedAt == null;

  Map<String, dynamic> toMap() {
    return {
      'tenantId': tenantId,
      'email': email,
      'emailLower': email.trim().toLowerCase(),
      'displayName': displayName,
      'role': tenantUserRoleToString(role),
      'status': accountStatusToString(status),
      'activeModules': activeModules,
      'inviteCode': inviteCode.toUpperCase(),
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
      'claimedByUid': claimedByUid,
      'claimedAt': claimedAt == null ? null : Timestamp.fromDate(claimedAt!),
    };
  }

  factory TenantInviteModel.fromMap(Map<String, dynamic> map, {String? id}) {
    final modulesRaw = map['activeModules'];
    final modules = <String>[];
    if (modulesRaw is List) {
      for (final item in modulesRaw) {
        if (item is String && item.trim().isNotEmpty) {
          modules.add(item.trim());
        }
      }
    }

    return TenantInviteModel(
      id: id,
      tenantId: (map['tenantId'] as String? ?? '').trim(),
      email: (map['email'] as String? ?? '').trim(),
      displayName: (map['displayName'] as String? ?? '').trim(),
      role: tenantUserRoleFromString((map['role'] as String? ?? 'operator')),
      status: accountStatusFromString((map['status'] as String? ?? 'active')),
      activeModules: List.unmodifiable(modules),
      inviteCode: (map['inviteCode'] as String? ?? '').trim().toUpperCase(),
      createdAt: _parseDateTime(map['createdAt']),
      createdBy: (map['createdBy'] as String? ?? '').trim(),
      expiresAt: map['expiresAt'] == null
          ? null
          : _parseDateTime(map['expiresAt']),
      claimedByUid: (map['claimedByUid'] as String?)?.trim(),
      claimedAt: map['claimedAt'] == null
          ? null
          : _parseDateTime(map['claimedAt']),
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

class TenantInviteFormArgs {
  const TenantInviteFormArgs({required this.tenantId, required this.actorUid});

  final String tenantId;
  final String actorUid;
}
