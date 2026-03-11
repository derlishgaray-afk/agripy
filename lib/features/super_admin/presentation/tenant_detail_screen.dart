import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/constants/modules.dart';
import '../../../shared/widgets/blocked_screen.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/super_admin_repo.dart';
import '../domain/models.dart';

class TenantDetailScreen extends StatefulWidget {
  const TenantDetailScreen({super.key, required this.args});

  final TenantDetailArgs args;

  @override
  State<TenantDetailScreen> createState() => _TenantDetailScreenState();
}

class _TenantDetailScreenState extends State<TenantDetailScreen> {
  late final SuperAdminRepo _repo;

  @override
  void initState() {
    super.initState();
    _repo = SuperAdminRepo(FirebaseFirestore.instance);
  }

  Future<void> _openEdit(TenantModel tenant) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.superAdminTenantForm,
      arguments: TenantFormArgs(actorUid: widget.args.actorUid, tenant: tenant),
    );
  }

  Future<void> _openUsers(TenantModel tenant) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.superAdminTenantUsers,
      arguments: TenantUsersArgs(
        tenantId: tenant.id!,
        actorUid: widget.args.actorUid,
      ),
    );
  }

  Future<void> _resolveActivationRequest(
    TenantActivationRequestModel request,
  ) async {
    var selectedPlan = request.requestedPlan == TenantPlan.trial
        ? TenantPlan.basic
        : request.requestedPlan;
    var customEndsAt = request.requestedCustomEndsAt;
    final notesController = TextEditingController(text: request.reason);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var submitting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickCustomEndsAt() async {
              final now = DateTime.now();
              final initial = customEndsAt ?? now.add(const Duration(days: 30));
              final picked = await showDatePicker(
                context: context,
                firstDate: now,
                lastDate: DateTime(now.year + 5),
                initialDate: initial,
              );
              if (picked == null) {
                return;
              }
              setDialogState(() {
                customEndsAt = DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  23,
                  59,
                );
              });
            }

            return AlertDialog(
              title: const Text('Resolver solicitud de activacion'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Solicitante: ${request.requesterName}'),
                  Text('Email: ${request.requesterEmail}'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<TenantPlan>(
                    initialValue: selectedPlan,
                    decoration: const InputDecoration(
                      labelText: 'Plan a aprobar',
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
                    onChanged: submitting
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              selectedPlan = value;
                            });
                          },
                  ),
                  if (selectedPlan == TenantPlan.custom) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: submitting ? null : pickCustomEndsAt,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        customEndsAt == null
                            ? 'Elegir vigencia custom'
                            : 'Vence: ${DateFormat('dd/MM/yyyy').format(customEndsAt!)}',
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesController,
                    enabled: !submitting,
                    maxLines: 3,
                    maxLength: 280,
                    decoration: const InputDecoration(
                      labelText: 'Notas de resolucion',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cerrar'),
                ),
                OutlinedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() {
                            submitting = true;
                          });
                          try {
                            await _repo.rejectActivationRequest(
                              requestId: request.id ?? '',
                              resolvedByUid: widget.args.actorUid,
                              resolvedNotes: notesController.text.trim(),
                            );
                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Solicitud rechazada.'),
                              ),
                            );
                          } catch (error) {
                            if (!mounted) {
                              return;
                            }
                            setDialogState(() {
                              submitting = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('No se pudo rechazar: $error'),
                              ),
                            );
                          }
                        },
                  child: const Text('Rechazar'),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() {
                            submitting = true;
                          });
                          try {
                            await _repo.approveActivationRequest(
                              requestId: request.id ?? '',
                              resolvedByUid: widget.args.actorUid,
                              approvedPlan: selectedPlan,
                              customEndsAt: selectedPlan == TenantPlan.custom
                                  ? customEndsAt
                                  : null,
                              resolvedNotes: notesController.text.trim(),
                            );
                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Solicitud aprobada.'),
                              ),
                            );
                          } catch (error) {
                            if (!mounted) {
                              return;
                            }
                            setDialogState(() {
                              submitting = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('No se pudo aprobar: $error'),
                              ),
                            );
                          }
                        },
                  child: const Text('Aprobar'),
                ),
              ],
            );
          },
        );
      },
    );
    notesController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return StreamBuilder<TenantModel?>(
      stream: _repo.watchTenantById(widget.args.tenantId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detalle tenant')),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detalle tenant')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final tenant = snapshot.data;
        if (tenant == null) {
          return const BlockedScreen(
            title: 'Tenant no encontrado',
            message: 'No existe informacion para este tenant.',
          );
        }

        final modules = tenant.modules.map(AppModules.labelOf).join(', ');
        final trialEndsAt = tenant.trialEndsAt == null
            ? '-'
            : dateFormat.format(tenant.trialEndsAt!);
        final accessEndsAt = tenant.accessEndsAt == null
            ? '-'
            : dateFormat.format(tenant.accessEndsAt!);

        return Scaffold(
          appBar: AppBar(
            title: Text('Tenant: ${tenant.name}'),
            actions: [
              IconButton(
                onPressed: () => _openEdit(tenant),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Editar',
              ),
            ],
          ),
          body: ResponsivePage(
            child: ListView(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tenant.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text('ID: ${tenant.id}'),
                        const SizedBox(height: 4),
                        Text('Estado: ${tenantStatusToString(tenant.status)}'),
                        const SizedBox(height: 4),
                        Text('Plan: ${tenantPlanToString(tenant.plan)}'),
                        const SizedBox(height: 4),
                        Text(
                          'Suscripcion: ${tenantSubscriptionStatusToString(tenant.subscriptionStatus)}',
                        ),
                        const SizedBox(height: 4),
                        Text('Trial vence: $trialEndsAt'),
                        const SizedBox(height: 4),
                        Text('Acceso vence: $accessEndsAt'),
                        const SizedBox(height: 4),
                        Text('Modulos: ${modules.isEmpty ? '-' : modules}'),
                        const SizedBox(height: 4),
                        Text('Creado por: ${tenant.createdBy}'),
                        const SizedBox(height: 4),
                        Text(
                          'Creado en: ${dateFormat.format(tenant.createdAt)}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _openUsers(tenant),
                  icon: const Icon(Icons.people_alt_outlined),
                  label: const Text('Administrar usuarios del tenant'),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<TenantActivationRequestModel>>(
                  stream: _repo.watchActivationRequests(
                    tenantId: tenant.id,
                    status: TenantActivationRequestStatus.pending,
                  ),
                  builder: (context, requestSnapshot) {
                    if (requestSnapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Error cargando solicitudes: ${requestSnapshot.error}',
                          ),
                        ),
                      );
                    }
                    if (!requestSnapshot.hasData) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: LinearProgressIndicator(),
                        ),
                      );
                    }
                    final requests = requestSnapshot.data!;
                    if (requests.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Sin solicitudes de activacion pendientes.',
                          ),
                        ),
                      );
                    }
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Solicitudes pendientes',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            ...requests.map((request) {
                              final requestedEnds =
                                  request.requestedCustomEndsAt == null
                                  ? '-'
                                  : dateFormat.format(
                                      request.requestedCustomEndsAt!,
                                    );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Plan solicitado: ${tenantPlanToString(request.requestedPlan)}',
                                      ),
                                      Text(
                                        'Vigencia custom solicitada: $requestedEnds',
                                      ),
                                      Text(
                                        'Solicitante: ${request.requesterName}',
                                      ),
                                      Text('Motivo: ${request.reason}'),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton.icon(
                                          onPressed: () =>
                                              _resolveActivationRequest(
                                                request,
                                              ),
                                          icon: const Icon(
                                            Icons.fact_check_outlined,
                                          ),
                                          label: const Text('Resolver'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
