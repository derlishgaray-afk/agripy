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
              ],
            ),
          ),
        );
      },
    );
  }
}
