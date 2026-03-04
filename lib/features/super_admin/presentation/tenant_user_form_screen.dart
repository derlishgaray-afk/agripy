import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/modules.dart';
import '../../../shared/widgets/blocked_screen.dart';
import '../../../shared/widgets/loading_screen.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/super_admin_repo.dart';
import '../domain/models.dart';

class TenantUserFormScreen extends StatefulWidget {
  const TenantUserFormScreen({super.key, required this.args});

  final TenantUserFormArgs args;

  @override
  State<TenantUserFormScreen> createState() => _TenantUserFormScreenState();
}

class _TenantUserFormScreenState extends State<TenantUserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uidController = TextEditingController();
  final _displayNameController = TextEditingController();

  late final SuperAdminRepo _repo;
  bool _loadingData = true;
  bool _saving = false;
  String? _error;

  TenantModel? _tenant;
  TenantUserModel? _existingTenantUser;
  TenantUserRole _role = TenantUserRole.operator;
  AccountStatus _status = AccountStatus.active;
  Set<String> _selectedModules = {};

  bool get _isEditing => widget.args.uid != null && widget.args.uid!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _repo = SuperAdminRepo(FirebaseFirestore.instance);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final tenant = await _repo.getTenantById(widget.args.tenantId);
      if (tenant == null) {
        setState(() {
          _error = 'No se encontro el tenant.';
          _loadingData = false;
        });
        return;
      }

      TenantUserModel? existingUser;
      if (_isEditing) {
        existingUser = await _repo.getTenantUser(
          widget.args.tenantId,
          widget.args.uid!,
        );
      }

      _tenant = tenant;
      _existingTenantUser = existingUser;

      _uidController.text = existingUser?.uid ?? widget.args.uid ?? '';
      _displayNameController.text = existingUser?.displayName ?? '';
      _role = existingUser?.role ?? TenantUserRole.operator;
      _status = existingUser?.status ?? AccountStatus.active;

      final tenantModules = tenant.modules.toSet();
      final existingModules = existingUser?.activeModules.toSet() ?? <String>{};
      _selectedModules = existingModules.intersection(tenantModules);
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loadingData = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _uidController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final tenant = _tenant;
    if (tenant == null) {
      return;
    }

    final tenantModules = tenant.modules.toSet();
    if (!_selectedModules.every(tenantModules.contains)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Active modules debe ser subconjunto de modules del tenant.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final uid = _uidController.text.trim();
      final user = TenantUserModel(
        uid: uid,
        displayName: _displayNameController.text.trim(),
        role: _role,
        status: _status,
        activeModules: _selectedModules.toList(growable: false),
        createdAt: _existingTenantUser?.createdAt ?? DateTime.now(),
        createdBy: _existingTenantUser?.createdBy ?? widget.args.actorUid,
      );

      await _repo.upsertTenantUserAndLink(
        tenantId: widget.args.tenantId,
        tenantUser: user,
        allowReassignUserTenant: false,
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuario guardado correctamente.')),
      );
      Navigator.of(context).pop(true);
    } on UserTenantConflictException catch (conflict) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'UID ya vinculado a otro tenant (${conflict.existingTenantId}).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingData) {
      return const LoadingScreen(message: 'Cargando datos de usuario...');
    }
    if (_error != null) {
      return BlockedScreen(title: 'No autorizado', message: _error!);
    }

    final tenant = _tenant!;
    final availableModules = tenant.modules;
    final isEdit = _existingTenantUser != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEdit ? 'Editar usuario tenant' : 'Agregar usuario tenant',
        ),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ResponsivePage(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                TextFormField(
                  controller: _uidController,
                  enabled: !isEdit,
                  decoration: const InputDecoration(
                    labelText: 'UID (Firebase Auth)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'UID obligatorio';
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
                    labelText: 'Status',
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
                const SizedBox(height: 16),
                Text(
                  'Active Modules',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (availableModules.isEmpty)
                  const Text('Este tenant no tiene modulos contratados.')
                else
                  ...availableModules.map((moduleKey) {
                    final selected = _selectedModules.contains(moduleKey);
                    return CheckboxListTile(
                      value: selected,
                      title: Text(AppModules.labelOf(moduleKey)),
                      subtitle: Text(moduleKey),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedModules.add(moduleKey);
                          } else {
                            _selectedModules.remove(moduleKey);
                          }
                        });
                      },
                    );
                  }),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar usuario'),
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
