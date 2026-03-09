import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/responsive_page.dart';

class SuperAdminHomeScreen extends StatelessWidget {
  const SuperAdminHomeScreen({super.key, required this.adminName});

  final String adminName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Super Admin')),
      body: ResponsivePage(
        child: ListView(
          children: [
            Text(
              'Bienvenido, $adminName',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.business_outlined),
                title: const Text('Tenants'),
                subtitle: const Text('Crear y administrar empresas'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                ).pushNamed(AppRoutes.superAdminTenants),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Configuracion'),
                subtitle: const Text('Registrar contacto de WhatsApp'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                ).pushNamed(AppRoutes.superAdminSettings),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
