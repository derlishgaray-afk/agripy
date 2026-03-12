import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/services/access_controller.dart';
import '../core/services/tenant_resolver.dart';
import 'router.dart';
import 'theme_controller.dart';

class AgripyApp extends StatefulWidget {
  const AgripyApp({super.key});

  @override
  State<AgripyApp> createState() => _AgripyAppState();
}

class _AgripyAppState extends State<AgripyApp> {
  late final SessionController _sessionController;
  late final AppThemeController _themeController;
  late final ThemeData _lightTheme;
  late final ThemeData _darkTheme;
  String? _lastThemeUid;
  bool _hasSyncedThemeAtLeastOnce = false;

  @override
  void initState() {
    super.initState();
    _themeController = AppThemeController();
    _sessionController = SessionController(
      auth: FirebaseAuth.instance,
      firestore: FirebaseFirestore.instance,
      tenantResolver: TenantResolver(FirebaseFirestore.instance),
      accessController: AccessController(FirebaseFirestore.instance),
    );
    _sessionController.addListener(_syncThemeForCurrentUser);
    _syncThemeForCurrentUser();
    _lightTheme = _buildTheme(Brightness.light);
    _darkTheme = _buildTheme(Brightness.dark);
  }

  void _syncThemeForCurrentUser() {
    final uid = _sessionController.currentUser?.uid;
    if (_hasSyncedThemeAtLeastOnce && _lastThemeUid == uid) {
      return;
    }
    _lastThemeUid = uid;
    _hasSyncedThemeAtLeastOnce = true;
    unawaited(_themeController.syncForUser(uid));
  }

  @override
  void dispose() {
    _sessionController.removeListener(_syncThemeForCurrentUser);
    _themeController.dispose();
    _sessionController.dispose();
    super.dispose();
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1B7F5B),
      brightness: brightness,
    );
    final scheme = baseScheme.copyWith(
      primary: isDark ? const Color(0xFF66D6A7) : const Color(0xFF136948),
      onPrimary: isDark ? const Color(0xFF002114) : Colors.white,
      secondary: isDark ? const Color(0xFF9ED49E) : const Color(0xFF4D7A37),
      surface: isDark ? const Color(0xFF101513) : const Color(0xFFF8FBF8),
      surfaceContainer: isDark
          ? const Color(0xFF1A211D)
          : const Color(0xFFEFF5EF),
      surfaceContainerHigh: isDark
          ? const Color(0xFF232C27)
          : const Color(0xFFE7F0E7),
      outline: isDark ? const Color(0xFF809488) : const Color(0xFF7A8F83),
    );

    return ThemeData(
      useMaterial3: true,
      splashFactory: kIsWeb ? NoSplash.splashFactory : InkRipple.splashFactory,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        elevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: isDark ? 1 : 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_sessionController, _themeController]),
      builder: (context, _) {
        final router = AppRouter(
          sessionController: _sessionController,
          themeController: _themeController,
        );
        return MaterialApp(
          title: 'AgriPy',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: _themeController.themeMode,
          locale: const Locale('es', 'PY'),
          supportedLocales: const [
            Locale('es'),
            Locale('es', 'PY'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            if (child == null) {
              return const SizedBox.shrink();
            }
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(alwaysUse24HourFormat: true),
              child: child,
            );
          },
          onGenerateRoute: router.onGenerateRoute,
          initialRoute: AppRoutes.home,
        );
      },
    );
  }
}
