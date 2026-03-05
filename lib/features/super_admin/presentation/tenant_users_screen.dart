import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/constants/modules.dart';
import '../../../shared/widgets/blocked_screen.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/super_admin_repo.dart';
import '../domain/models.dart';

class TenantUsersScreen extends StatefulWidget {
  const TenantUsersScreen({super.key, required this.args});

  final TenantUsersArgs args;

  @override
  State<TenantUsersScreen> createState() => _TenantUsersScreenState();
}

class _TenantUsersScreenState extends State<TenantUsersScreen> {
  late final SuperAdminRepo _repo;

  @override
  void initState() {
    super.initState();
    _repo = SuperAdminRepo(FirebaseFirestore.instance);
  }

  Future<void> _openUserForm({String? uid}) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.superAdminTenantUserForm,
      arguments: TenantUserFormArgs(
        tenantId: widget.args.tenantId,
        actorUid: widget.args.actorUid,
        uid: uid,
      ),
    );
  }

  Future<void> _openInviteForm() async {
    await Navigator.of(context).pushNamed(
      AppRoutes.superAdminTenantInviteForm,
      arguments: TenantInviteFormArgs(
        tenantId: widget.args.tenantId,
        actorUid: widget.args.actorUid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TenantModel?>(
      stream: _repo.watchTenantById(widget.args.tenantId),
      builder: (context, tenantSnapshot) {
        if (tenantSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Usuarios tenant')),
            body: Center(child: Text('Error: ${tenantSnapshot.error}')),
          );
        }
        if (!tenantSnapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Usuarios tenant')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final tenant = tenantSnapshot.data;
        if (tenant == null) {
          return const BlockedScreen(
            title: 'Tenant no encontrado',
            message: 'No se pudo cargar el tenant solicitado.',
          );
        }

        final modules = tenant.modules.map(AppModules.labelOf).join(', ');

        return Scaffold(
          appBar: AppBar(
            title: Text('Usuarios - ${tenant.name}'),
            actions: [
              IconButton(
                onPressed: _openInviteForm,
                icon: const Icon(Icons.key_outlined),
                tooltip: 'Generar invitación',
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openUserForm(),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Agregar usuario'),
          ),
          body: ResponsivePage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tenant.status == TenantStatus.suspended)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade100,
                    padding: const EdgeInsets.all(10),
                    child: const Text(
                      'Tenant suspendido: los usuarios quedaran bloqueados en login.',
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Modulos del tenant: ${modules.isEmpty ? '-' : modules}',
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<TenantUserModel>>(
                    stream: _repo.watchTenantUsers(widget.args.tenantId),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final users = snapshot.data!;
                      if (users.isEmpty) {
                        return const Center(
                          child: Text(
                            'No hay usuarios cargados en este tenant.',
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: users.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final userModules = user.activeModules
                              .map(AppModules.labelOf)
                              .join(', ');
                          return Card(
                            child: ListTile(
                              onTap: () => _openUserForm(uid: user.uid),
                              title: Text(
                                user.displayName.isEmpty
                                    ? user.uid
                                    : '${user.displayName} (${user.uid})',
                              ),
                              subtitle: Text(
                                'Rol: ${tenantUserRoleToString(user.role)}\n'
                                'Estado: ${accountStatusToString(user.status)}\n'
                                'Modulos: ${userModules.isEmpty ? '-' : userModules}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
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
      },
    );
  }
}
