import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/services/access_controller.dart';
import '../core/services/tenant_resolver.dart';
import 'router.dart';

class AgripyApp extends StatefulWidget {
  const AgripyApp({super.key});

  @override
  State<AgripyApp> createState() => _AgripyAppState();
}

class _AgripyAppState extends State<AgripyApp> {
  late final SessionController _sessionController;

  @override
  void initState() {
    super.initState();
    _sessionController = SessionController(
      auth: FirebaseAuth.instance,
      firestore: FirebaseFirestore.instance,
      tenantResolver: TenantResolver(FirebaseFirestore.instance),
      accessController: AccessController(FirebaseFirestore.instance),
    );
  }

  @override
  void dispose() {
    _sessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sessionController,
      builder: (context, _) {
        final router = AppRouter(sessionController: _sessionController);
        return MaterialApp(
          title: 'AgriPy',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
            useMaterial3: true,
          ),
          onGenerateRoute: router.onGenerateRoute,
          initialRoute: AppRoutes.home,
        );
      },
    );
  }
}
