import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/services/access_controller.dart';
import '../core/services/tenant_path.dart';
import '../core/services/tenant_resolver.dart';
import '../features/recetario_agronomico/domain/models.dart';
import '../features/recetario_agronomico/presentation/emit_order_screen.dart';
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
  static const String recipes = '/recipes';
  static const String recipeForm = '/recipe-form';
  static const String emitOrder = '/emit-order';

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

      final tenantId = await _tenantResolver.tryResolveTenantIdForUid(user.uid);
      if (tenantId == null) {
        if (isSuperAdmin) {
          warningMessage =
              'Sin tenant vinculado. Solo panel Super Admin disponible.';
          return;
        }
        needsOnboarding = true;
        return;
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
    return 'Error inesperado al cargar sesion.';
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

  Future<void> signOut() async {
    await _auth.signOut();
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
                message: 'Argumento invalido para receta.',
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
                message: 'Argumento invalido para tenant form.',
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
                message: 'Argumento invalido para tenant detail.',
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
                message: 'Argumento invalido para tenant users.',
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
                message: 'Argumento invalido para tenant user form.',
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
                message: 'Argumento invalido para tenant invite form.',
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
        actionLabel: 'Cerrar sesion',
        onAction: sessionController.signOut,
      );
    }

    if (!sessionController.isSuperAdmin && sessionController.session == null) {
      return BlockedScreen(
        title: 'Sesion invalida',
        message:
            sessionController.blockingMessage ??
            'No se pudo resolver acceso para este usuario.',
        actionLabel: 'Cerrar sesion',
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
            subtitle: const Text('Panel de administracion global'),
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
            title: const Text('Recetario Agronomico'),
            subtitle: const Text('Crear, emitir y compartir recetarios'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.recipes),
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
            tooltip: 'Cerrar sesion',
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
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  const Text('Acceso por empresa'),
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
