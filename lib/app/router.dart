import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/modules.dart';
import '../core/services/access_controller.dart';
import '../core/services/tenant_path.dart';
import '../core/services/tenant_resolver.dart';
import '../features/recetario_agronomico/domain/models.dart';
import '../features/recetario_agronomico/presentation/emit_order_screen.dart';
import '../features/recetario_agronomico/presentation/fields_registry_screen.dart';
import '../features/recetario_agronomico/presentation/inputs_registry_screen.dart';
import '../features/recetario_agronomico/presentation/operators_registry_screen.dart';
import '../features/recetario_agronomico/presentation/reports_hub_screen.dart';
import '../features/recetario_agronomico/presentation/recetario_home_screen.dart';
import '../features/recetario_agronomico/presentation/recipe_form_screen.dart';
import '../features/recetario_agronomico/presentation/recipes_list_screen.dart';
import '../features/super_admin/domain/models.dart';
import '../features/super_admin/presentation/onboarding_claim_screen.dart';
import '../features/super_admin/presentation/super_admin_home_screen.dart';
import '../features/super_admin/presentation/super_admin_settings_screen.dart';
import '../features/super_admin/presentation/tenant_detail_screen.dart';
import '../features/super_admin/presentation/tenant_form_screen.dart';
import '../features/super_admin/presentation/tenant_invite_form_screen.dart';
import '../features/super_admin/presentation/tenant_user_form_screen.dart';
import '../features/super_admin/presentation/tenant_users_screen.dart';
import '../features/super_admin/presentation/tenants_list_screen.dart';
import '../features/super_admin/services/super_admin_guard.dart';
import '../shared/widgets/blocked_screen.dart';
import '../shared/widgets/loading_screen.dart';
import '../shared/widgets/responsive_page.dart';
import 'theme_controller.dart';

class AppRoutes {
  static const String home = '/';
  static const String recetarioHome = '/recetario-home';
  static const String recipes = '/recipes';
  static const String emittedRecipes = '/recipes-emitted';
  static const String recipeForm = '/recipe-form';
  static const String emitOrder = '/emit-order';
  static const String fieldRegistry = '/field-registry';
  static const String inputRegistry = '/input-registry';
  static const String operatorRegistry = '/operator-registry';
  static const String reports = '/reports';

  static const String superAdminHome = '/super-admin';
  static const String superAdminSettings = '/super-admin/settings';
  static const String superAdminTenants = '/super-admin/tenants';
  static const String superAdminTenantForm = '/super-admin/tenant-form';
  static const String superAdminTenantDetail = '/super-admin/tenant-detail';
  static const String superAdminTenantUsers = '/super-admin/tenant-users';
  static const String superAdminTenantUserForm =
      '/super-admin/tenant-user-form';
  static const String superAdminTenantInviteForm =
      '/super-admin/tenant-invite-form';
}

class AppSession {
  const AppSession({
    required this.uid,
    required this.tenantId,
    required this.tenantName,
    required this.access,
  });

  final String uid;
  final String tenantId;
  final String tenantName;
  final TenantUserAccess access;

  bool get hasRecetarioAgronomico => access.hasRecetarioAgronomico;
}

enum PasswordResetEligibilityStatus {
  allowed,
  accountNotFound,
  socialSignInOnly,
  secondaryTenantUsersOnly,
  firestoreVerificationUnavailable,
}

class PasswordResetEligibility {
  const PasswordResetEligibility(this.status);

  final PasswordResetEligibilityStatus status;

  bool get isAllowed => status == PasswordResetEligibilityStatus.allowed;
}

class TenantBlockingSupportContext {
  const TenantBlockingSupportContext({
    required this.blockReason,
    required this.tenantId,
    required this.tenantName,
    required this.tenantStatus,
    required this.tenantPlan,
    required this.isPrincipalUser,
    required this.requesterUid,
    required this.requesterName,
    required this.requesterEmail,
    this.trialEndsAt,
    this.systemAdminName,
    this.systemAdminWhatsapp,
  });

  final TenantBlockReason blockReason;
  final String tenantId;
  final String tenantName;
  final String tenantStatus;
  final String tenantPlan;
  final DateTime? trialEndsAt;
  final bool isPrincipalUser;
  final String requesterUid;
  final String requesterName;
  final String requesterEmail;
  final String? systemAdminName;
  final String? systemAdminWhatsapp;

  bool get canContactSystemAdmin {
    if (!isPrincipalUser) {
      return false;
    }
    final raw = (systemAdminWhatsapp ?? '').trim();
    if (raw.isEmpty) {
      return false;
    }
    return raw.replaceAll(RegExp(r'\D'), '').isNotEmpty;
  }

  bool get canRequestActivation {
    return isPrincipalUser && blockReason != TenantBlockReason.suspended;
  }
}

class _SystemAdminContact {
  const _SystemAdminContact({required this.name, required this.whatsapp});

  final String name;
  final String whatsapp;
}

class SessionController extends ChangeNotifier {
  SessionController({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required TenantResolver tenantResolver,
    required AccessController accessController,
  }) : _auth = auth,
       _firestore = firestore,
       _tenantResolver = tenantResolver,
       _accessController = accessController,
       _superAdminGuard = SuperAdminGuard(firestore) {
    _authSub = _auth.authStateChanges().listen((user) {
      unawaited(_onAuthStateChanged(user));
    });
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final TenantResolver _tenantResolver;
  final AccessController _accessController;
  final SuperAdminGuard _superAdminGuard;

  StreamSubscription<User?>? _authSub;

  bool isLoading = true;
  AppSession? session;
  User? currentUser;
  SuperAdminProfile? superAdminProfile;
  String? blockingMessage;
  TenantBlockingSupportContext? tenantBlockingSupportContext;
  String? warningMessage;
  bool needsOnboarding = false;

  bool get isAuthenticated => currentUser != null;

  bool get isSuperAdmin => superAdminProfile != null;

  String get userDisplayName {
    if (superAdminProfile != null && superAdminProfile!.name.isNotEmpty) {
      return superAdminProfile!.name;
    }
    if (session != null && session!.access.displayName.isNotEmpty) {
      return session!.access.displayName;
    }
    final email = currentUser?.email;
    if (email != null && email.trim().isNotEmpty) {
      return email;
    }
    return 'Usuario';
  }

  Future<void> _onAuthStateChanged(User? user) async {
    currentUser = user;
    if (user == null) {
      _clearSession();
      isLoading = false;
      notifyListeners();
      return;
    }

    unawaited(_upsertEmailIndexForUser(user));

    isLoading = true;
    _clearSession();
    notifyListeners();

    try {
      superAdminProfile = await _superAdminGuard.loadActiveSuperAdmin(user.uid);

      var tenantId = await _tenantResolver.tryResolveTenantIdForUid(user.uid);
      if (tenantId != null) {
        await _ensureUserTenantLink(user: user, tenantId: tenantId);
      }
      if (tenantId == null) {
        await _provisionPersonalWorkspace(user);
        tenantId = await _tenantResolver.tryResolveTenantIdForUid(user.uid);
      }
      if (tenantId == null) {
        throw StateError('No se pudo aprovisionar el espacio personal.');
      }
      unawaited(_upsertEmailIndexForUser(user, tenantId: tenantId));

      try {
        final access = await _accessController.loadTenantUserAccess(
          tenantId,
          user.uid,
        );
        if (!access.isActive) {
          throw StateError('Usuario bloqueado en la empresa actual.');
        }

        final tenantDoc = await TenantPath.tenantRef(
          _firestore,
          tenantId,
        ).get();
        final tenantName = _resolveTenantName(tenantDoc.data(), tenantId);

        session = AppSession(
          uid: user.uid,
          tenantId: tenantId,
          tenantName: tenantName,
          access: access,
        );
      } on TenantBlockedException catch (error) {
        if (isSuperAdmin) {
          warningMessage = _tenantBlockedMessage(error);
          session = null;
        } else {
          await _handleTenantBlocked(
            tenantId: tenantId,
            user: user,
            error: error,
          );
        }
      } catch (error) {
        if (isSuperAdmin) {
          warningMessage = _errorText(error);
          session = null;
        } else {
          blockingMessage = _errorText(error);
        }
      }
    } catch (error) {
      blockingMessage = _errorText(error);
      session = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _clearSession() {
    session = null;
    superAdminProfile = null;
    blockingMessage = null;
    tenantBlockingSupportContext = null;
    warningMessage = null;
    needsOnboarding = false;
  }

  String _resolveTenantName(
    Map<String, dynamic>? data,
    String fallbackTenantId,
  ) {
    final raw = data?['name'];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return fallbackTenantId;
  }

  Future<void> _provisionPersonalWorkspace(User user) async {
    final now = DateTime.now();
    final trialEndsAt = now.add(const Duration(days: 7));
    final tenantId = user.uid;
    final displayName = _resolveDefaultDisplayName(user);
    final allModules = List<String>.from(AppModules.availableModules);

    final tenantRef = TenantPath.tenantRef(_firestore, tenantId);
    final tenantUserRef = TenantPath.tenantUserRef(
      _firestore,
      tenantId,
      user.uid,
    );
    final linkRef = _firestore.collection('user_tenant').doc(user.uid);

    final batch = _firestore.batch();
    batch.set(tenantRef, {
      'name': displayName,
      'status': 'active',
      'plan': 'trial',
      'modules': allModules,
      'createdAt': Timestamp.fromDate(now),
      'createdBy': user.uid,
      'trialEndsAt': Timestamp.fromDate(trialEndsAt),
      'accessEndsAt': null,
      'subscriptionStatus': 'active',
    }, SetOptions(merge: true));

    batch.set(tenantUserRef, {
      'displayName': displayName,
      'email': user.email,
      'emailLower': user.email?.trim().toLowerCase(),
      'role': 'admin',
      'status': 'active',
      'activeModules': allModules,
      'createdAt': Timestamp.fromDate(now),
      'createdBy': user.uid,
    }, SetOptions(merge: true));

    batch.set(linkRef, {
      'tenantId': tenantId,
      'displayName': displayName,
      'createdAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> _ensureUserTenantLink({
    required User user,
    required String tenantId,
  }) async {
    final linkRef = _firestore.collection('user_tenant').doc(user.uid);
    final linkSnapshot = await linkRef.get();
    final existingTenantId = (linkSnapshot.data()?['tenantId'] as String? ?? '')
        .trim();
    if (linkSnapshot.exists && existingTenantId == tenantId) {
      return;
    }

    final tenantUserSnapshot = await TenantPath.tenantUserRef(
      _firestore,
      tenantId,
      user.uid,
    ).get();
    final tenantUserData = tenantUserSnapshot.data();
    final displayNameRaw = tenantUserData?['displayName'];
    final displayName =
        displayNameRaw is String && displayNameRaw.trim().isNotEmpty
        ? displayNameRaw.trim()
        : _resolveDefaultDisplayName(user);

    await linkRef.set({
      'tenantId': tenantId,
      'displayName': displayName,
      'createdAt': linkSnapshot.data()?['createdAt'] ?? Timestamp.now(),
    }, SetOptions(merge: true));
  }

  String _resolveDefaultDisplayName(User user) {
    final name = user.displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }
    return 'Mi espacio';
  }

  Future<void> _handleTenantBlocked({
    required String tenantId,
    required User user,
    required TenantBlockedException error,
  }) async {
    blockingMessage = _tenantBlockedMessage(error);

    final isPrincipalUser = await _isPrincipalTenantUser(
      tenantId: tenantId,
      uid: user.uid,
    );
    if (!isPrincipalUser) {
      tenantBlockingSupportContext = null;
      return;
    }

    final systemAdminContact = await _loadSystemAdminWhatsappContact();
    tenantBlockingSupportContext = TenantBlockingSupportContext(
      blockReason: error.reason,
      tenantId: error.tenantId,
      tenantName: error.tenantName,
      tenantStatus: error.tenantStatus,
      tenantPlan: error.tenantPlan,
      trialEndsAt: error.trialEndsAt,
      isPrincipalUser: true,
      requesterUid: user.uid,
      requesterName: _resolveDefaultDisplayName(user),
      requesterEmail: user.email?.trim() ?? '',
      systemAdminName: systemAdminContact?.name,
      systemAdminWhatsapp: systemAdminContact?.whatsapp,
    );
  }

  Future<bool> _isPrincipalTenantUser({
    required String tenantId,
    required String uid,
  }) async {
    if (uid == tenantId) {
      return true;
    }
    try {
      final snapshot = await TenantPath.tenantUserRef(
        _firestore,
        tenantId,
        uid,
      ).get();
      final role = (snapshot.data()?['role'] as String? ?? '')
          .trim()
          .toLowerCase();
      return role == 'admin';
    } catch (_) {
      return false;
    }
  }

  Future<_SystemAdminContact?> _loadSystemAdminWhatsappContact() async {
    try {
      final supportDoc = await _firestore
          .collection('system_config')
          .doc('support')
          .get();
      final supportData = supportDoc.data();
      if (supportData != null) {
        final whatsapp = (supportData['whatsappContact'] as String? ?? '')
            .trim();
        if (whatsapp.isNotEmpty) {
          final supportName = (supportData['supportName'] as String? ?? '')
              .trim();
          return _SystemAdminContact(
            name: supportName.isNotEmpty
                ? supportName
                : 'Administrador del sistema',
            whatsapp: whatsapp,
          );
        }
      }
    } catch (_) {}

    try {
      final snapshot = await _firestore
          .collection('super_admins')
          .where('status', isEqualTo: 'active')
          .limit(20)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final whatsapp = (data['whatsappContact'] as String? ?? '').trim();
        if (whatsapp.isEmpty) {
          continue;
        }
        final name = (data['name'] as String? ?? '').trim();
        final email = (data['email'] as String? ?? '').trim();
        return _SystemAdminContact(
          name: name.isNotEmpty
              ? name
              : (email.isNotEmpty ? email : 'Administrador'),
          whatsapp: whatsapp,
        );
      }
    } catch (_) {}
    return null;
  }

  String _tenantBlockedMessage(TenantBlockedException error) {
    switch (error.reason) {
      case TenantBlockReason.suspended:
        return 'La empresa "${error.tenantName}" se encuentra suspendida. '
            'Contacta al administrador del sistema para reactivar el acceso.';
      case TenantBlockReason.trialExpired:
        final dueDate = error.trialEndsAt == null
            ? ''
            : ' Fecha de vencimiento: ${_formatDate(error.trialEndsAt!)}.';
        return 'El periodo de prueba de la empresa "${error.tenantName}" '
            'ha vencido.$dueDate Contacta al administrador del sistema.';
      case TenantBlockReason.subscriptionExpired:
        final dueDate = error.trialEndsAt == null
            ? ''
            : ' Fecha de vencimiento: ${_formatDate(error.trialEndsAt!)}.';
        return 'La suscripcion de la empresa "${error.tenantName}" '
            'esta vencida o pendiente de aprobacion.$dueDate '
            'Solicita activacion al administrador del sistema.';
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }

  String _tenantPlanLabel(TenantPlan plan) {
    switch (plan) {
      case TenantPlan.trial:
        return 'trial';
      case TenantPlan.basic:
        return 'basic (mensual)';
      case TenantPlan.pro:
        return 'pro (anual)';
      case TenantPlan.custom:
        return 'custom (editable)';
    }
  }

  Uri? buildTenantSupportWhatsappUri({
    TenantPlan? requestedPlan,
    String? activationReason,
    DateTime? requestedCustomEndsAt,
  }) {
    final context = tenantBlockingSupportContext;
    if (context == null || !context.canContactSystemAdmin) {
      return null;
    }
    final adminDigits = (context.systemAdminWhatsapp ?? '').replaceAll(
      RegExp(r'\D'),
      '',
    );
    if (adminDigits.isEmpty) {
      return null;
    }

    final reasonText = switch (context.blockReason) {
      TenantBlockReason.suspended => 'empresa suspendida',
      TenantBlockReason.trialExpired => 'trial vencido',
      TenantBlockReason.subscriptionExpired =>
        'suscripcion vencida o pendiente',
    };
    final dueText = context.trialEndsAt == null
        ? 'N/D'
        : _formatDate(context.trialEndsAt!);
    final emailText = context.requesterEmail.isEmpty
        ? 'N/D'
        : context.requesterEmail;
    final normalizedActivationReason = (activationReason ?? '').trim();
    final includeActivationDetails =
        requestedPlan != null || normalizedActivationReason.isNotEmpty;
    final customRequestedUntil = requestedCustomEndsAt == null
        ? 'N/D'
        : _formatDate(requestedCustomEndsAt);
    final messageBuffer = StringBuffer(
      'Hola ${context.systemAdminName ?? 'Administrador'}, necesito asistencia '
      'para reactivar el acceso.\n'
      'Empresa: ${context.tenantName}\n'
      'Tenant ID: ${context.tenantId}\n'
      'Estado actual: ${context.tenantStatus}\n'
      'Plan: ${context.tenantPlan}\n'
      'Vencimiento: $dueText\n'
      'Motivo: $reasonText\n'
      'Solicitante: ${context.requesterName}\n'
      'UID: ${context.requesterUid}\n'
      'Email: $emailText',
    );
    if (includeActivationDetails) {
      messageBuffer
        ..write('\nSolicitud de activacion: SI')
        ..write('\nPlan solicitado: ');
      if (requestedPlan == null) {
        messageBuffer.write('N/D');
      } else {
        messageBuffer.write(_tenantPlanLabel(requestedPlan));
      }
      messageBuffer
        ..write('\nMotivo de activacion: ')
        ..write(
          normalizedActivationReason.isEmpty
              ? 'N/D'
              : normalizedActivationReason,
        );
      if (requestedPlan == TenantPlan.custom) {
        messageBuffer
          ..write('\nVigencia custom solicitada: ')
          ..write(customRequestedUntil);
      }
    }
    final message = messageBuffer.toString();

    return Uri.parse(
      'https://wa.me/$adminDigits?text=${Uri.encodeComponent(message)}',
    );
  }

  String _errorText(Object error) {
    if (error is TenantBlockedException) {
      return _tenantBlockedMessage(error);
    }
    if (error is FirebaseAuthException) {
      return error.message ?? 'Error de autenticacion.';
    }
    if (error is FirebaseException) {
      return error.message ?? 'Error de Firebase.';
    }
    if (error is StateError) {
      return error.message;
    }
    return 'Error inesperado al cargar sesión.';
  }

  Future<void> requestTenantActivation({
    required TenantBlockingSupportContext supportContext,
    required TenantPlan requestedPlan,
    required String reason,
    DateTime? customEndsAt,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw StateError('No hay sesion autenticada.');
    }
    if (!supportContext.canRequestActivation) {
      throw StateError('No tienes permisos para solicitar activacion.');
    }
    if (requestedPlan == TenantPlan.trial) {
      throw StateError('No se puede solicitar activacion al plan trial.');
    }
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw StateError('Debes indicar el motivo de activacion.');
    }
    if (requestedPlan == TenantPlan.custom) {
      if (customEndsAt == null || !customEndsAt.isAfter(DateTime.now())) {
        throw StateError('Para plan custom debes elegir una vigencia futura.');
      }
    }

    final pendingSnapshot = await _firestore
        .collection('tenant_activation_requests')
        .where('requesterUid', isEqualTo: user.uid)
        .get();
    final hasPendingForTenant = pendingSnapshot.docs.any((doc) {
      final data = doc.data();
      final tenantId = (data['tenantId'] as String? ?? '').trim();
      final status = (data['status'] as String? ?? '').trim().toLowerCase();
      return tenantId == supportContext.tenantId && status == 'pending';
    });
    if (hasPendingForTenant) {
      throw StateError('Ya tienes una solicitud de activacion pendiente.');
    }

    final now = Timestamp.now();
    await _firestore.collection('tenant_activation_requests').add({
      'tenantId': supportContext.tenantId,
      'tenantName': supportContext.tenantName,
      'requesterUid': user.uid,
      'requesterName': supportContext.requesterName,
      'requesterEmail': supportContext.requesterEmail,
      'requestedPlan': tenantPlanToString(requestedPlan),
      'requestedCustomEndsAt': requestedPlan == TenantPlan.custom
          ? Timestamp.fromDate(customEndsAt!)
          : null,
      'reason': normalizedReason,
      'status': 'pending',
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> registerWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return;
    }

    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw StateError('Inicio con Google cancelado.');
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await _auth.signInWithCredential(credential);
  }

  Future<void> signInWithApple() async {
    final provider = AppleAuthProvider();
    provider.addScope('email');
    provider.addScope('name');

    if (kIsWeb) {
      await _auth.signInWithPopup(provider);
      return;
    }

    await _auth.signInWithProvider(provider);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<PasswordResetEligibility> getPasswordResetEligibility({
    required String email,
  }) async {
    final normalizedEmail = email.trim();
    final emailLower = normalizedEmail.toLowerCase();
    if (emailLower.isEmpty) {
      return const PasswordResetEligibility(
        PasswordResetEligibilityStatus.accountNotFound,
      );
    }

    final methods = await _signInMethodsForEmail(normalizedEmail);
    if (methods.isNotEmpty) {
      final hasPasswordMethod =
          methods.contains(EmailAuthProvider.EMAIL_PASSWORD_SIGN_IN_METHOD) ||
          methods.contains('password');
      if (!hasPasswordMethod) {
        return const PasswordResetEligibility(
          PasswordResetEligibilityStatus.socialSignInOnly,
        );
      }
    }

    DocumentSnapshot<Map<String, dynamic>>? snapshot;
    try {
      snapshot = await _firestore
          .collection('auth_email_index')
          .doc(emailLower)
          .get();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return const PasswordResetEligibility(
          PasswordResetEligibilityStatus.firestoreVerificationUnavailable,
        );
      }
      rethrow;
    }

    if (methods.isEmpty && !snapshot.exists) {
      return const PasswordResetEligibility(
        PasswordResetEligibilityStatus.accountNotFound,
      );
    }

    final data = snapshot.data();
    final passwordResetAllowed = data?['passwordResetAllowed'] == true;
    final uid = (data?['uid'] as String? ?? '').trim();
    final tenantId = (data?['tenantId'] as String? ?? '').trim();
    final inferredAllowed =
        passwordResetAllowed ||
        (uid.isNotEmpty && tenantId.isNotEmpty && uid != tenantId);

    return PasswordResetEligibility(
      inferredAllowed
          ? PasswordResetEligibilityStatus.allowed
          : PasswordResetEligibilityStatus.secondaryTenantUsersOnly,
    );
  }

  Future<List<String>> _signInMethodsForEmail(String email) async {
    // ignore: deprecated_member_use
    return _auth.fetchSignInMethodsForEmail(email);
  }

  Future<void> _upsertEmailIndexForUser(User user, {String? tenantId}) async {
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      return;
    }

    final emailLower = email.toLowerCase();
    final payload = <String, dynamic>{
      'uid': user.uid,
      'email': email,
      'emailLower': emailLower,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (tenantId != null && tenantId.trim().isNotEmpty) {
      payload['tenantId'] = tenantId.trim();
      payload['passwordResetAllowed'] = tenantId.trim() != user.uid;
    }

    try {
      await _firestore
          .collection('auth_email_index')
          .doc(emailLower)
          .set(payload, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> refreshSession() async {
    final user = currentUser;
    if (user == null) {
      return;
    }
    await _onAuthStateChanged(user);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

class AppRouter {
  AppRouter({required this.sessionController, required this.themeController});

  final SessionController sessionController;
  final AppThemeController themeController;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.home:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _RootScreen(
            sessionController: sessionController,
            themeController: themeController,
          ),
        );
      case AppRoutes.recetarioHome:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) => RecetarioHomeScreen(session: session),
        );
      case AppRoutes.recipes:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) => RecipesListScreen(
            session: session,
            mode: RecipesListMode.recipes,
          ),
        );
      case AppRoutes.emittedRecipes:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) => RecipesListScreen(
            session: session,
            mode: RecipesListMode.emitted,
          ),
        );
      case AppRoutes.recipeForm:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) {
            final arg = settings.arguments;
            if (arg != null && arg is! Recipe) {
              return const _RouteErrorScreen(
                message: 'Argumento inválido para receta.',
              );
            }
            return RecipeFormScreen(session: session, recipe: arg as Recipe?);
          },
        );
      case AppRoutes.emitOrder:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) {
            final arg = settings.arguments;
            if (arg is! Recipe) {
              return const _RouteErrorScreen(
                message: 'Falta receta para emitir.',
              );
            }
            return EmitOrderScreen(session: session, recipe: arg);
          },
        );
      case AppRoutes.fieldRegistry:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) => FieldsRegistryScreen(session: session),
        );
      case AppRoutes.inputRegistry:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) => InputsRegistryScreen(session: session),
        );
      case AppRoutes.operatorRegistry:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) => OperatorsRegistryScreen(session: session),
        );
      case AppRoutes.reports:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) => ReportsHubScreen(session: session),
        );
      case AppRoutes.superAdminHome:
        return _superAdminGuardRoute(
          settings: settings,
          builder: (adminProfile) => SuperAdminHomeScreen(
            adminName: adminProfile.name.isEmpty
                ? (sessionController.currentUser?.email ?? 'Super Admin')
                : adminProfile.name,
          ),
        );
      case AppRoutes.superAdminSettings:
        return _superAdminGuardRoute(
          settings: settings,
          builder: (adminProfile) =>
              SuperAdminSettingsScreen(adminUid: adminProfile.uid),
        );
      case AppRoutes.superAdminTenants:
        return _superAdminGuardRoute(
          settings: settings,
          builder: (_) =>
              TenantsListScreen(actorUid: sessionController.currentUser!.uid),
        );
      case AppRoutes.superAdminTenantForm:
        return _superAdminGuardRoute(
          settings: settings,
          builder: (_) {
            final arg = settings.arguments;
            if (arg is! TenantFormArgs) {
              return const _RouteErrorScreen(
                message: 'Argumento inválido para tenant form.',
              );
            }
            return TenantFormScreen(args: arg);
          },
        );
      case AppRoutes.superAdminTenantDetail:
        return _superAdminGuardRoute(
          settings: settings,
          builder: (_) {
            final arg = settings.arguments;
            if (arg is! TenantDetailArgs) {
              return const _RouteErrorScreen(
                message: 'Argumento inválido para tenant detail.',
              );
            }
            return TenantDetailScreen(args: arg);
          },
        );
      case AppRoutes.superAdminTenantUsers:
        return _superAdminGuardRoute(
          settings: settings,
          builder: (_) {
            final arg = settings.arguments;
            if (arg is! TenantUsersArgs) {
              return const _RouteErrorScreen(
                message: 'Argumento inválido para tenant users.',
              );
            }
            return TenantUsersScreen(args: arg);
          },
        );
      case AppRoutes.superAdminTenantUserForm:
        return _superAdminGuardRoute(
          settings: settings,
          builder: (_) {
            final arg = settings.arguments;
            if (arg is! TenantUserFormArgs) {
              return const _RouteErrorScreen(
                message: 'Argumento inválido para tenant user form.',
              );
            }
            return TenantUserFormScreen(args: arg);
          },
        );
      case AppRoutes.superAdminTenantInviteForm:
        return _superAdminGuardRoute(
          settings: settings,
          builder: (_) {
            final arg = settings.arguments;
            if (arg is! TenantInviteFormArgs) {
              return const _RouteErrorScreen(
                message: 'Argumento inválido para tenant invite form.',
              );
            }
            return TenantInviteFormScreen(args: arg);
          },
        );
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              const _RouteErrorScreen(message: 'Ruta no encontrada.'),
        );
    }
  }

  Route<dynamic> _recetarioGuardRoute({
    required RouteSettings settings,
    required Widget Function(AppSession session) builder,
  }) {
    final session = sessionController.session;
    if (session == null) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            const _RouteErrorScreen(message: 'Sesion tenant no disponible.'),
      );
    }

    if (!session.hasRecetarioAgronomico) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const BlockedScreen(
          title: 'Modulo no habilitado',
          message: 'Tu usuario no tiene acceso a recetario agronomico.',
        ),
      );
    }

    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => builder(session),
    );
  }

  Route<dynamic> _superAdminGuardRoute({
    required RouteSettings settings,
    required Widget Function(SuperAdminProfile profile) builder,
  }) {
    final profile = sessionController.superAdminProfile;
    if (profile == null) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const BlockedScreen(
          title: 'No autorizado',
          message: 'Esta ruta es solo para usuarios Super Admin activos.',
        ),
      );
    }

    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => builder(profile),
    );
  }
}

class _RootScreen extends StatelessWidget {
  const _RootScreen({
    required this.sessionController,
    required this.themeController,
  });

  final SessionController sessionController;
  final AppThemeController themeController;

  @override
  Widget build(BuildContext context) {
    if (sessionController.isLoading) {
      return const LoadingScreen(message: 'Resolviendo acceso...');
    }

    if (!sessionController.isAuthenticated) {
      return LoginScreen(sessionController: sessionController);
    }

    if (sessionController.needsOnboarding &&
        !sessionController.isSuperAdmin &&
        sessionController.currentUser != null) {
      return OnboardingClaimScreen(
        uid: sessionController.currentUser!.uid,
        onClaimed: sessionController.refreshSession,
        onSignOut: sessionController.signOut,
      );
    }

    if (sessionController.blockingMessage != null &&
        !sessionController.isSuperAdmin) {
      final supportContext = sessionController.tenantBlockingSupportContext;
      if (supportContext != null) {
        return _TenantBlockedSupportScreen(
          sessionController: sessionController,
          supportContext: supportContext,
        );
      }
      return BlockedScreen(
        title: 'Acceso bloqueado',
        message: sessionController.blockingMessage!,
        actionLabel: 'Cerrar sesión',
        onAction: sessionController.signOut,
      );
    }

    if (!sessionController.isSuperAdmin && sessionController.session == null) {
      return BlockedScreen(
        title: 'Sesion invalida',
        message:
            sessionController.blockingMessage ??
            'No se pudo resolver acceso para este usuario.',
        actionLabel: 'Cerrar sesión',
        onAction: sessionController.signOut,
      );
    }

    return _ModuleHomeScreen(
      sessionController: sessionController,
      themeController: themeController,
    );
  }
}

class _ModuleHomeScreen extends StatelessWidget {
  const _ModuleHomeScreen({
    required this.sessionController,
    required this.themeController,
  });

  final SessionController sessionController;
  final AppThemeController themeController;

  Future<void> _openThemeSettings(BuildContext context) async {
    final selectedMode = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final currentMode = themeController.themeMode;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Apariencia',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ListTile(
                  onTap: () => Navigator.of(sheetContext).pop(ThemeMode.light),
                  leading: const Icon(Icons.light_mode_outlined),
                  title: const Text('Modo claro'),
                  subtitle: const Text('Ideal para espacios con mucha luz.'),
                  trailing: currentMode == ThemeMode.light
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(sheetContext).colorScheme.primary,
                        )
                      : null,
                ),
                ListTile(
                  onTap: () => Navigator.of(sheetContext).pop(ThemeMode.dark),
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Modo oscuro'),
                  subtitle: const Text('Reduce brillo en uso nocturno.'),
                  trailing: currentMode == ThemeMode.dark
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(sheetContext).colorScheme.primary,
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedMode == null) {
      return;
    }
    await themeController.setThemeMode(selectedMode);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final session = sessionController.session;
    final modules = <Widget>[];

    if (sessionController.isSuperAdmin) {
      modules.add(
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: const Icon(Icons.admin_panel_settings_outlined),
            ),
            title: const Text('Super Admin'),
            subtitle: const Text('Panel de administración global'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.superAdminHome),
          ),
        ),
      );
    }

    if (session != null && session.hasRecetarioAgronomico) {
      modules.add(
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: const Icon(Icons.description_outlined),
            ),
            title: const Text('Recetario Agronómico'),
            subtitle: const Text('Crear, emitir y compartir recetarios'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.recetarioHome),
          ),
        ),
      );
    }

    final appBarTitle = session == null
        ? 'AgriPy'
        : 'AgriPy - ${session.tenantName}';
    final roleText = sessionController.isSuperAdmin
        ? 'super_admin'
        : (session?.access.role.name ?? '-');

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          IconButton(
            onPressed: () => _openThemeSettings(context),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configuracion de tema',
          ),
          IconButton(
            onPressed: sessionController.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.person_outline),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sessionController.userDisplayName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rol: $roleText',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (sessionController.warningMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  sessionController.warningMessage!,
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
            const SizedBox(height: 12),
            Text('Modulos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (modules.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hay modulos habilitados para este usuario.'),
                ),
              ),
            ...modules,
          ],
        ),
      ),
    );
  }
}

class _TenantBlockedSupportScreen extends StatefulWidget {
  const _TenantBlockedSupportScreen({
    required this.sessionController,
    required this.supportContext,
  });

  final SessionController sessionController;
  final TenantBlockingSupportContext supportContext;

  @override
  State<_TenantBlockedSupportScreen> createState() =>
      _TenantBlockedSupportScreenState();
}

class _TenantBlockedSupportScreenState
    extends State<_TenantBlockedSupportScreen> {
  final TextEditingController _reasonController = TextEditingController();
  TenantPlan _requestedPlan = TenantPlan.basic;
  DateTime? _customEndsAt;
  bool _submittingRequest = false;

  TenantBlockingSupportContext get supportContext => widget.supportContext;
  SessionController get sessionController => widget.sessionController;

  String get _title {
    switch (supportContext.blockReason) {
      case TenantBlockReason.suspended:
        return 'Empresa suspendida';
      case TenantBlockReason.trialExpired:
        return 'Trial vencido';
      case TenantBlockReason.subscriptionExpired:
        return 'Suscripcion vencida';
    }
  }

  String get _message {
    if (supportContext.blockReason == TenantBlockReason.suspended) {
      return 'La empresa fue suspendida. Solicita reactivacion al administrador del sistema.';
    }
    final dueDate = supportContext.trialEndsAt == null
        ? 'N/D'
        : _formatDate(supportContext.trialEndsAt!);
    if (supportContext.blockReason == TenantBlockReason.trialExpired) {
      return 'El periodo de prueba finalizo el $dueDate. '
          'Solicita activacion del plan contratado.';
    }
    return 'La suscripcion se encuentra vencida o pendiente de aprobacion. '
        'Vencimiento: $dueDate.';
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }

  Future<void> _pickCustomEndsAt() async {
    final now = DateTime.now();
    final initial = _customEndsAt ?? now.add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      initialDate: initial,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _customEndsAt = DateTime(picked.year, picked.month, picked.day, 23, 59);
    });
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final uri = sessionController.buildTenantSupportWhatsappUri();
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay un WhatsApp configurado para el Administrador del sistema.',
          ),
        ),
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir WhatsApp en este dispositivo.'),
        ),
      );
    }
  }

  Future<void> _submitActivationRequest() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes indicar el motivo de activacion.')),
      );
      return;
    }
    if (_requestedPlan == TenantPlan.custom &&
        (_customEndsAt == null || !_customEndsAt!.isAfter(DateTime.now()))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes seleccionar una vigencia futura para custom.'),
        ),
      );
      return;
    }
    setState(() {
      _submittingRequest = true;
    });
    final requestedPlan = _requestedPlan;
    final requestedCustomEndsAt = requestedPlan == TenantPlan.custom
        ? _customEndsAt
        : null;
    try {
      await sessionController.requestTenantActivation(
        supportContext: supportContext,
        requestedPlan: requestedPlan,
        customEndsAt: requestedCustomEndsAt,
        reason: reason,
      );
      if (!mounted) {
        return;
      }
      final uri = sessionController.buildTenantSupportWhatsappUri(
        requestedPlan: requestedPlan,
        activationReason: reason,
        requestedCustomEndsAt: requestedCustomEndsAt,
      );
      _reasonController.clear();
      setState(() {
        _requestedPlan = TenantPlan.basic;
        _customEndsAt = null;
      });
      if (uri == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud enviada para aprobacion.')),
        );
      } else {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!mounted) {
          return;
        }
        final message = launched
            ? 'Solicitud enviada y WhatsApp preparado para notificar al administrador.'
            : 'Solicitud enviada. No se pudo abrir WhatsApp en este dispositivo.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is StateError
          ? error.message
          : 'No se pudo enviar la solicitud: $error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _submittingRequest = false;
        });
      }
    }
  }

  Widget _detailRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dueAt = supportContext.trialEndsAt == null
        ? 'N/D'
        : _formatDate(supportContext.trialEndsAt!);
    final adminName = (supportContext.systemAdminName ?? '').trim();
    final adminWhatsapp = (supportContext.systemAdminWhatsapp ?? '').trim();
    final adminLabel = adminName.isEmpty
        ? 'Administrador del sistema'
        : adminName;

    return Scaffold(
      body: Center(
        child: ResponsivePage(
          maxWidth: 760,
          child: ListView(
            shrinkWrap: true,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(_message),
                      const SizedBox(height: 18),
                      _detailRow(
                        context,
                        label: 'Empresa',
                        value: supportContext.tenantName,
                      ),
                      _detailRow(
                        context,
                        label: 'Tenant ID',
                        value: supportContext.tenantId,
                      ),
                      _detailRow(
                        context,
                        label: 'Estado',
                        value: supportContext.tenantStatus,
                      ),
                      _detailRow(
                        context,
                        label: 'Plan',
                        value: supportContext.tenantPlan,
                      ),
                      _detailRow(context, label: 'Vence', value: dueAt),
                      const Divider(height: 24),
                      _detailRow(
                        context,
                        label: 'Contacto sistema',
                        value: adminLabel,
                      ),
                      _detailRow(
                        context,
                        label: 'WhatsApp',
                        value: adminWhatsapp.isEmpty
                            ? 'No configurado'
                            : adminWhatsapp,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: supportContext.canContactSystemAdmin
                                ? () => _openWhatsApp(context)
                                : null,
                            icon: const Icon(Icons.message_outlined),
                            label: const Text(
                              'Enviar WhatsApp al Administrador del sistema',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: sessionController.signOut,
                            icon: const Icon(Icons.logout),
                            label: const Text('Cerrar sesion'),
                          ),
                        ],
                      ),
                      if (supportContext.canRequestActivation) ...[
                        const Divider(height: 28),
                        Text(
                          'Solicitar activacion',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<TenantPlan>(
                          initialValue: _requestedPlan,
                          decoration: const InputDecoration(
                            labelText: 'Plan solicitado',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: TenantPlan.basic,
                              child: Text('basic (mensual)'),
                            ),
                            DropdownMenuItem(
                              value: TenantPlan.pro,
                              child: Text('pro (anual)'),
                            ),
                            DropdownMenuItem(
                              value: TenantPlan.custom,
                              child: Text('custom (editable)'),
                            ),
                          ],
                          onChanged: _submittingRequest
                              ? null
                              : (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    _requestedPlan = value;
                                    if (value != TenantPlan.custom) {
                                      _customEndsAt = null;
                                    }
                                  });
                                },
                        ),
                        if (_requestedPlan == TenantPlan.custom) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _submittingRequest
                                ? null
                                : _pickCustomEndsAt,
                            icon: const Icon(Icons.event_outlined),
                            label: Text(
                              _customEndsAt == null
                                  ? 'Elegir vigencia custom'
                                  : 'Vence: ${_formatDate(_customEndsAt!)}',
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: _reasonController,
                          maxLines: 3,
                          maxLength: 280,
                          enabled: !_submittingRequest,
                          decoration: const InputDecoration(
                            labelText: 'Motivo de activacion',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _submittingRequest
                              ? null
                              : _submitActivationRequest,
                          icon: _submittingRequest
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(
                            _submittingRequest
                                ? 'Enviando...'
                                : 'Solicitar activacion',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.sessionController});

  final SessionController sessionController;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool createAccount}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      if (createAccount) {
        await widget.sessionController.registerWithEmailPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await widget.sessionController.signInWithEmailPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyAuthError(error, createAccount))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa tu email para recuperar acceso.'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final eligibility = await widget.sessionController
          .getPasswordResetEligibility(email: email);
      if (!mounted) {
        return;
      }

      if (!eligibility.isAllowed) {
        final message = switch (eligibility.status) {
          PasswordResetEligibilityStatus.accountNotFound =>
            'No existe una cuenta con ese email.',
          PasswordResetEligibilityStatus.socialSignInOnly =>
            'Esta cuenta no usa contrasena. Ingresa con Google o Apple.',
          PasswordResetEligibilityStatus.secondaryTenantUsersOnly =>
            'La recuperacion de contrasena solo aplica a usuarios secundarios registrados con email y contrasena.',
          PasswordResetEligibilityStatus.firestoreVerificationUnavailable =>
            'No se pudo validar el email por permisos de Firestore. Publica las reglas nuevas o crea auth_email_index manualmente.',
          PasswordResetEligibilityStatus.allowed =>
            'No se pudo validar la recuperacion de contrasena.',
        };
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return;
      }

      await widget.sessionController.sendPasswordResetEmail(email: email);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Te enviamos un correo para restablecer tu contrasena.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyResetError(error))));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
    });

    try {
      await widget.sessionController.signInWithGoogle();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyAuthError(error, false))));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _loading = true;
    });

    try {
      await widget.sessionController.signInWithApple();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyAuthError(error, false))));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _friendlyAuthError(Object error, bool createAccount) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'Ese email ya existe. Usa "Ingresar" con tu contrasena.';
        case 'invalid-email':
          return 'Email inválido.';
        case 'weak-password':
          return 'Contrasena debil. Minimo 6 caracteres.';
        case 'user-not-found':
          return createAccount
              ? 'No se pudo crear la cuenta.'
              : 'No existe una cuenta con ese email. Usa "Crear cuenta".';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Email o contrasena incorrectos.';
        case 'too-many-requests':
          return 'Demasiados intentos. Espera unos minutos e intenta de nuevo.';
        case 'account-exists-with-different-credential':
          return 'Esta cuenta ya existe con otro método de inicio de sesión.';
        case 'operation-not-allowed':
          return 'Proveedor no habilitado en Firebase Auth.';
        case 'operation-not-supported-in-this-environment':
          return 'Este método no está soportado en este dispositivo.';
      }
      return error.message ?? 'No se pudo autenticar.';
    }
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
  }

  String _friendlyResetError(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'No se pudo verificar el email por permisos de Firestore.';
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'Email inválido.';
        case 'user-not-found':
          return 'No existe una cuenta con ese email.';
        case 'too-many-requests':
          return 'Demasiados intentos. Espera unos minutos e intenta de nuevo.';
      }
      return error.message ?? 'No se pudo enviar el correo de recuperacion.';
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final showAppleButton =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ResponsivePage(
            maxWidth: 460,
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AgriPy',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Acceso por usuario'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _signInWithGoogle,
                      icon: const Icon(Icons.login_outlined),
                      label: const Text('Continuar con Google'),
                    ),
                  ),
                  if (showAppleButton) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _signInWithApple,
                        icon: const Icon(Icons.apple),
                        label: const Text('Continuar con Apple'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('O continuar con email'),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresar email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().length < 6) {
                        return 'Minimo 6 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading
                          ? null
                          : () => _submit(createAccount: false),
                      child: const Text('Ingresar'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _resetPassword,
                      icon: const Icon(Icons.lock_reset_outlined),
                      label: const Text('Recuperar contrasena'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return BlockedScreen(
      title: 'Error de navegacion',
      message: message,
      actionLabel: 'Inicio',
      onAction: () => Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false),
    );
  }
}
