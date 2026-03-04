import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/constants/modules.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/super_admin_repo.dart';
import '../domain/models.dart';

class TenantsListScreen extends StatefulWidget {
  const TenantsListScreen({super.key, required this.actorUid});

  final String actorUid;

  @override
  State<TenantsListScreen> createState() => _TenantsListScreenState();
}

class _TenantsListScreenState extends State<TenantsListScreen> {
  late final SuperAdminRepo _repo;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _repo = SuperAdminRepo(FirebaseFirestore.instance);
  }

  Future<void> _openCreateTenant() async {
    await Navigator.of(context).pushNamed(
      AppRoutes.superAdminTenantForm,
      arguments: TenantFormArgs(actorUid: widget.actorUid),
    );
  }

  Future<void> _openEditTenant(TenantModel tenant) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.superAdminTenantForm,
      arguments: TenantFormArgs(actorUid: widget.actorUid, tenant: tenant),
    );
  }

  Future<void> _openDetail(TenantModel tenant) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.superAdminTenantDetail,
      arguments: TenantDetailArgs(
        tenantId: tenant.id!,
        actorUid: widget.actorUid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Tenants')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateTenant,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Crear tenant'),
      ),
      body: ResponsivePage(
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por nombre',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value.trim().toLowerCase();
                });
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<TenantModel>>(
                stream: _repo.watchTenants(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final tenants = snapshot.data!
                      .where(
                        (tenant) =>
                            _query.isEmpty ||
                            tenant.name.toLowerCase().contains(_query),
                      )
                      .toList(growable: false);

                  if (tenants.isEmpty) {
                    return const Center(
                      child: Text('No hay tenants para mostrar.'),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: tenants.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final tenant = tenants[index];
                      final modules = tenant.modules
                          .map(AppModules.labelOf)
                          .join(', ');
                      return Card(
                        child: ListTile(
                          onTap: () => _openDetail(tenant),
                          title: Text(tenant.name),
                          subtitle: Text(
                            'Plan: ${tenantPlanToString(tenant.plan)}\n'
                            'Estado: ${tenantStatusToString(tenant.status)}\n'
                            'Modulos: ${modules.isEmpty ? '-' : modules}\n'
                            'Creado: ${dateFormat.format(tenant.createdAt)}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Editar tenant',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _openEditTenant(tenant),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
