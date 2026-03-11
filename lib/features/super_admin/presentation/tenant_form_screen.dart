import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/modules.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/super_admin_repo.dart';
import '../domain/models.dart';

class TenantFormScreen extends StatefulWidget {
  const TenantFormScreen({super.key, required this.args});

  final TenantFormArgs args;

  @override
  State<TenantFormScreen> createState() => _TenantFormScreenState();
}

class _TenantFormScreenState extends State<TenantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  late final SuperAdminRepo _repo;
  late TenantPlan _plan;
  late TenantStatus _status;
  late Set<String> _selectedModules;
  bool _saving = false;

  TenantModel? get _editingTenant => widget.args.tenant;

  DateTime _addMonths(DateTime value, int months) {
    final year = value.year + ((value.month - 1 + months) ~/ 12);
    final month = ((value.month - 1 + months) % 12) + 1;
    final endOfMonth = DateTime(year, month + 1, 0).day;
    final safeDay = value.day <= endOfMonth ? value.day : endOfMonth;
    return DateTime(
      year,
      month,
      safeDay,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  DateTime _defaultAccessEndsAt(TenantPlan plan, DateTime now) {
    switch (plan) {
      case TenantPlan.basic:
        return _addMonths(now, 1);
      case TenantPlan.pro:
        return _addMonths(now, 12);
      case TenantPlan.custom:
        return _addMonths(now, 1);
      case TenantPlan.trial:
        return now.add(const Duration(days: 7));
    }
  }

  @override
  void initState() {
    super.initState();
    _repo = SuperAdminRepo(FirebaseFirestore.instance);
    _plan = _editingTenant?.plan ?? TenantPlan.trial;
    _status = _editingTenant?.status ?? TenantStatus.active;
    _selectedModules = {...?_editingTenant?.modules};
    _nameController.text = _editingTenant?.name ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final now = DateTime.now();
      DateTime? trialEndsAt = _editingTenant?.trialEndsAt;
      DateTime? accessEndsAt = _editingTenant?.accessEndsAt;
      final subscriptionStatus =
          _editingTenant?.subscriptionStatus ?? TenantSubscriptionStatus.active;
      if (_plan == TenantPlan.trial) {
        trialEndsAt ??= now.add(const Duration(days: 7));
        accessEndsAt = null;
      } else {
        trialEndsAt = null;
        accessEndsAt ??= _defaultAccessEndsAt(_plan, now);
      }

      final tenant = TenantModel(
        id: _editingTenant?.id,
        name: _nameController.text.trim(),
        status: _status,
        plan: _plan,
        modules: _selectedModules.toList(growable: false),
        createdAt: _editingTenant?.createdAt ?? DateTime.now(),
        createdBy: _editingTenant?.createdBy ?? widget.args.actorUid,
        trialEndsAt: trialEndsAt,
        accessEndsAt: accessEndsAt,
        subscriptionStatus: subscriptionStatus,
      );

      if (_editingTenant == null) {
        await _repo.createTenant(tenant);
      } else {
        await _repo.updateTenant(tenant);
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tenant guardado correctamente.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
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
    final isEditing = _editingTenant != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Editar tenant' : 'Crear tenant')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ResponsivePage(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la empresa',
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
                DropdownButtonFormField<TenantPlan>(
                  initialValue: _plan,
                  decoration: const InputDecoration(
                    labelText: 'Plan',
                    border: OutlineInputBorder(),
                  ),
                  items: TenantPlan.values
                      .map(
                        (plan) => DropdownMenuItem<TenantPlan>(
                          value: plan,
                          child: Text(tenantPlanToString(plan)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _plan = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TenantStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    border: OutlineInputBorder(),
                  ),
                  items: TenantStatus.values
                      .map(
                        (status) => DropdownMenuItem<TenantStatus>(
                          value: status,
                          child: Text(tenantStatusToString(status)),
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
                Text('Modulos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...AppModules.availableModules.map((moduleKey) {
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
                  label: const Text('Guardar tenant'),
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
