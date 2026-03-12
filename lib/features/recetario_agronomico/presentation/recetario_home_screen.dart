import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/services/access_controller.dart';
import '../../../shared/widgets/responsive_page.dart';

class RecetarioHomeScreen extends StatelessWidget {
  const RecetarioHomeScreen({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final isOperator = session.access.role == TenantRole.operator;
    final isSecondaryUser = !session.isPrincipalUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Modulo Recetario Agronomico')),
      body: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (!isSecondaryUser && !isOperator) ...[
              _ModuleCard(
                icon: Icons.description_outlined,
                title: 'Recetas',
                subtitle: 'Borradores y publicados con acceso a nueva receta',
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.recipes),
              ),
              const SizedBox(height: 10),
            ],
            _ModuleCard(
              icon: Icons.local_shipping_outlined,
              title: 'Emitidos',
              subtitle: 'Pendientes, completados y anulados',
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.emittedRecipes),
            ),
            const SizedBox(height: 10),
            _ModuleCard(
              icon: Icons.assessment_outlined,
              title: 'Informes',
              subtitle: 'Resumen y seguimiento de aplicaciones',
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.reports),
            ),
            if (!isSecondaryUser) ...[
              const SizedBox(height: 10),
              _ModuleCard(
                icon: Icons.agriculture_outlined,
                title: 'Registro de Campos',
                subtitle: 'Campos y lotes con sus superficies',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.fieldRegistry),
              ),
              const SizedBox(height: 10),
              _ModuleCard(
                icon: Icons.inventory_2_outlined,
                title: 'Registro de Insumos',
                subtitle: 'Nombre comercial, principio activo, unidad y tipo',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.inputRegistry),
              ),
              const SizedBox(height: 10),
              _ModuleCard(
                icon: Icons.person_outline,
                title: 'Registro de Operadores',
                subtitle: 'Operadores habilitados para aplicaciones',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.operatorRegistry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
