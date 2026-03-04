import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/modules.dart';
import '../../../shared/widgets/blocked_screen.dart';
import '../../../shared/widgets/loading_screen.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/super_admin_repo.dart';
import '../domain/models.dart';

class TenantInviteFormScreen extends StatefulWidget {
  const TenantInviteFormScreen({super.key, required this.args});

  final TenantInviteFormArgs args;

  @override
  State<TenantInviteFormScreen> createState() => _TenantInviteFormScreenState();
}

class _TenantInviteFormScreenState extends State<TenantInviteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  late final SuperAdminRepo _repo;

  TenantModel? _tenant;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  TenantUserRole _role = TenantUserRole.operator;
  AccountStatus _status = AccountStatus.active;
  final Set<String> _activeModules = {};
  bool _expiresIn7Days = true;

  @override
  void initState() {
    super.initState();
    _repo = SuperAdminRepo(FirebaseFirestore.instance);
    _loadTenant();
  }

  Future<void> _loadTenant() async {
    try {
      final tenant = await _repo.getTenantById(widget.args.tenantId);
      if (tenant == null) {
        _error = 'Tenant no encontrado.';
      } else {
        _tenant = tenant;
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _createInvite() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final tenant = _tenant;
    if (tenant == null) {
      return;
    }

    final tenantModules = tenant.modules.toSet();
    if (!_activeModules.every(tenantModules.contains)) {
      _showSnack('Active modules debe ser subconjunto de modules del tenant.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final invite = await _repo.createTenantInvite(
        tenantId: tenant.id!,
        email: _emailController.text.trim(),
        displayName: _displayNameController.text.trim(),
        role: _role,
        status: _status,
        activeModules: _activeModules.toList(growable: false),
        createdBy: widget.args.actorUid,
        expiresAt: _expiresIn7Days
            ? DateTime.now().add(const Duration(days: 7))
            : null,
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Invitacion creada'),
            content: SelectableText(
              'Codigo: ${invite.inviteCode}\n\n'
              'Comparti este codigo con el usuario para que complete onboarding.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      _showSnack('Error al crear invitacion: $error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingScreen(message: 'Cargando tenant...');
    }
    if (_error != null) {
      return BlockedScreen(title: 'Error', message: _error!);
    }

    final tenant = _tenant!;
    final tenantModules = tenant.modules;

    return Scaffold(
      appBar: AppBar(title: const Text('Invitar usuario')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ResponsivePage(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Tenant: ${tenant.name}'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email del usuario',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty || !text.contains('@')) {
                      return 'Email invalido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nombre obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TenantUserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Rol',
                    border: OutlineInputBorder(),
                  ),
                  items: TenantUserRole.values
                      .map(
                        (role) => DropdownMenuItem(
                          value: role,
                          child: Text(tenantUserRoleToString(role)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _role = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status inicial',
                    border: OutlineInputBorder(),
                  ),
                  items: AccountStatus.values
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(accountStatusToString(status)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _status = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _expiresIn7Days,
                  onChanged: (value) => setState(() => _expiresIn7Days = value),
                  title: const Text('Vence en 7 dias'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Active Modules',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...tenantModules.map((moduleKey) {
                  final selected = _activeModules.contains(moduleKey);
                  return CheckboxListTile(
                    value: selected,
                    title: Text(AppModules.labelOf(moduleKey)),
                    subtitle: Text(moduleKey),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _activeModules.add(moduleKey);
                        } else {
                          _activeModules.remove(moduleKey);
                        }
                      });
                    },
                  );
                }),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _createInvite,
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Generar codigo de invitacion'),
                ),
                if (_saving) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
