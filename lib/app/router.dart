import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/constants/modules.dart';
import '../core/services/access_controller.dart';
import '../core/services/tenant_path.dart';
import '../core/services/tenant_resolver.dart';
import '../features/recetario_agronomico/domain/models.dart';
import '../features/recetario_agronomico/presentation/emit_order_screen.dart';
import '../features/recetario_agronomico/presentation/fields_registry_screen.dart';
import '../features/recetario_agronomico/presentation/inputs_registry_screen.dart';
import '../features/recetario_agronomico/presentation/operators_registry_screen.dart';
import '../features/recetario_agronomico/presentation/recetario_home_screen.dart';
import '../features/recetario_agronomico/presentation/recipe_form_screen.dart';
import '../features/recetario_agronomico/presentation/recipes_list_screen.dart';
import '../features/super_admin/domain/models.dart';
import '../features/super_admin/presentation/onboarding_claim_screen.dart';
import '../features/super_admin/presentation/super_admin_home_screen.dart';
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

class AppRoutes {
  static const String home = '/';
  static const String recetarioHome = '/recetario-home';
  static const String recipes = '/recipes';
  static const String recipeForm = '/recipe-form';
  static const String emitOrder = '/emit-order';
  static const String fieldRegistry = '/field-registry';
  static const String inputRegistry = '/input-registry';
  static const String operatorRegistry = '/operator-registry';

  static const String superAdminHome = '/super-admin';
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

    isLoading = true;
    _clearSession();
    notifyListeners();

    try {
      superAdminProfile = await _superAdminGuard.loadActiveSuperAdmin(user.uid);

      var tenantId = await _tenantResolver.tryResolveTenantIdForUid(user.uid);
      if (tenantId == null) {
        await _provisionPersonalWorkspace(user);
        tenantId = await _tenantResolver.tryResolveTenantIdForUid(user.uid);
      }
      if (tenantId == null) {
        throw StateError('No se pudo aprovisionar el espacio personal.');
      }

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

    final tenantRef = TenantPath.tenantRef(_firestore, tenantId);
    final tenantUserRef = TenantPath.tenantUserRef(_firestore, tenantId, user.uid);
    final linkRef = _firestore.collection('user_tenant').doc(user.uid);

    final batch = _firestore.batch();
    batch.set(tenantRef, {
      'name': displayName,
      'status': 'active',
      'plan': 'trial',
      'modules': const [AppModules.recetarioAgronomico],
      'createdAt': Timestamp.fromDate(now),
      'createdBy': user.uid,
      'trialEndsAt': Timestamp.fromDate(trialEndsAt),
    }, SetOptions(merge: true));

    batch.set(tenantUserRef, {
      'displayName': displayName,
      'role': 'admin',
      'status': 'active',
      'activeModules': const [AppModules.recetarioAgronomico],
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

  String _errorText(Object error) {
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
  AppRouter({required this.sessionController});

  final SessionController sessionController;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.home:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _RootScreen(sessionController: sessionController),
        );
      case AppRoutes.recetarioHome:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) => RecetarioHomeScreen(session: session),
        );
      case AppRoutes.recipes:
        return _recetarioGuardRoute(
          settings: settings,
          builder: (session) => RecipesListScreen(session: session),
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
      case AppRoutes.superAdminHome:
        return _superAdminGuardRoute(
          settings: settings,
          builder: (adminProfile) => SuperAdminHomeScreen(
            adminName: adminProfile.name.isEmpty
                ? (sessionController.currentUser?.email ?? 'Super Admin')
                : adminProfile.name,
          ),
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
  const _RootScreen({required this.sessionController});

  final SessionController sessionController;

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

    return _ModuleHomeScreen(sessionController: sessionController);
  }
}

class _ModuleHomeScreen extends StatelessWidget {
  const _ModuleHomeScreen({required this.sessionController});

  final SessionController sessionController;

  @override
  Widget build(BuildContext context) {
    final session = sessionController.session;
    final modules = <Widget>[];

    if (sessionController.isSuperAdmin) {
      modules.add(
        Card(
          child: ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
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
            leading: const Icon(Icons.description_outlined),
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
            onPressed: sessionController.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: ResponsivePage(
        child: ListView(
          children: [
            Text(
              'Usuario: ${sessionController.userDisplayName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('Rol: $roleText'),
            const SizedBox(height: 8),
            if (sessionController.warningMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: Colors.orange.shade100,
                child: Text(sessionController.warningMessage!),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
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
        const SnackBar(content: Text('Ingresa tu email para recuperar acceso.')),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
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
                    child: OutlinedButton(
                      onPressed: _loading
                          ? null
                          : () => _submit(createAccount: true),
                      child: const Text('Crear cuenta'),
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
