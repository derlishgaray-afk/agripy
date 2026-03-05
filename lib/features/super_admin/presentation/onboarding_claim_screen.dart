import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/responsive_page.dart';
import '../data/super_admin_repo.dart';
import '../services/onboarding_service.dart';

class OnboardingClaimScreen extends StatefulWidget {
  const OnboardingClaimScreen({
    super.key,
    required this.uid,
    required this.onClaimed,
    required this.onSignOut,
  });

  final String uid;
  final Future<void> Function() onClaimed;
  final Future<void> Function() onSignOut;

  @override
  State<OnboardingClaimScreen> createState() => _OnboardingClaimScreenState();
}

class _OnboardingClaimScreenState extends State<OnboardingClaimScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;

  late final OnboardingService _onboardingService;

  @override
  void initState() {
    super.initState();
    _onboardingService = OnboardingService(
      SuperAdminRepo(FirebaseFirestore.instance),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _claimInvite() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showSnack('Ingresa un codigo de invitacion.');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _onboardingService.claimInvite(uid: widget.uid, inviteCode: code);
      await widget.onClaimed();
      if (!mounted) {
        return;
      }
      _showSnack('Onboarding completado. Bienvenido.');
    } catch (error) {
      _showSnack('No se pudo reclamar la invitacion: ${_claimErrorText(error)}');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _claimErrorText(Object error) {
    final unwrapped = _tryUnwrapError(error);
    if (unwrapped is UserTenantConflictException) {
      return 'Este usuario ya pertenece a otro tenant (${unwrapped.existingTenantId}).';
    }
    if (unwrapped is StateError) {
      return unwrapped.message;
    }
    if (unwrapped is FirebaseException) {
      switch (unwrapped.code) {
        case 'permission-denied':
          return 'Permiso denegado. Verifica email de invitacion y vigencia del codigo.';
        case 'not-found':
          return 'Codigo de invitacion no encontrado.';
      }
      return unwrapped.message ?? 'Error de Firebase al reclamar la invitacion.';
    }
    return unwrapped.toString();
  }

  Object _tryUnwrapError(Object error) {
    try {
      final dynamic any = error;
      final inner = any.error;
      if (inner is Object) {
        return inner;
      }
    } catch (_) {}
    return error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Onboarding'),
        actions: [
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesion',
          ),
        ],
      ),
      body: ResponsivePage(
        maxWidth: 520,
        child: ListView(
          children: [
            Text(
              'Completa tu acceso',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Ingresa el codigo de invitacion provisto por el Super Admin para vincularte a tu empresa.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Codigo de invitacion',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _claimInvite,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Activar mi cuenta'),
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
