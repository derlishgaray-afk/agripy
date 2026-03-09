import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/catalog_repo.dart';
import '../domain/catalog_models.dart';

class OperatorsRegistryScreen extends StatefulWidget {
  const OperatorsRegistryScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<OperatorsRegistryScreen> createState() =>
      _OperatorsRegistryScreenState();
}

class _OperatorsRegistryScreenState extends State<OperatorsRegistryScreen> {
  late final RecetarioCatalogRepo _repo;

  bool get _canEdit => widget.session.access.canEditRecetario;

  @override
  void initState() {
    super.initState();
    _repo = RecetarioCatalogRepo(
      firestore: FirebaseFirestore.instance,
      tenantId: widget.session.tenantId,
      currentUid: widget.session.uid,
      access: widget.session.access,
    );
  }

  Future<void> _showOperatorDialog({OperatorRegistryItem? existing}) async {
    if (existing?.isAuto == true) {
      _showSnack('Este operador se gestiona desde Usuarios del tenant.');
      return;
    }
    final controller = TextEditingController(text: existing?.name ?? '');
    final isEditing = existing != null;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Editar operador' : 'Nuevo operador'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  _showSnack('El nombre es obligatorio.');
                  return;
                }
                try {
                  if (isEditing) {
                    await _repo.updateOperator(id: existing.id!, name: name);
                  } else {
                    await _repo.createOperator(name);
                  }
                  if (!context.mounted) {
                    return;
                  }
                  Navigator.of(context).pop();
                } catch (error) {
                  _showSnack('No se pudo guardar el operador: $error');
                }
              },
              child: Text(isEditing ? 'Guardar' : 'Crear'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  Future<void> _deleteOperator(OperatorRegistryItem item) async {
    if (item.isAuto) {
      _showSnack('Este operador se gestiona desde Usuarios del tenant.');
      return;
    }
    final id = item.id;
    if (id == null || id.isEmpty) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar operador'),
          content: Text('¿Eliminar "${item.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (confirm != true) {
      return;
    }
    try {
      await _repo.deleteOperator(id);
    } catch (error) {
      _showSnack('No se pudo eliminar el operador: $error');
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro de Operadores')),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: _showOperatorDialog,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo operador'),
            )
          : null,
      body: StreamBuilder<List<OperatorRegistryItem>>(
        stream: _repo.watchOperators(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final operators = snapshot.data!;
          if (operators.isEmpty) {
            return const Center(child: Text('Sin operadores registrados.'));
          }
          return ResponsivePage(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: operators.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = operators[index];
                return Card(
                  child: ListTile(
                    title: Text(item.name),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              item.isAuto ? 'Automático' : 'Manual',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          if (item.isAuto)
                            const Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text('Usuario secundario'),
                            ),
                        ],
                      ),
                    ),
                    trailing: _canEdit && !item.isAuto
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar operador',
                                onPressed: () =>
                                    _showOperatorDialog(existing: item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Eliminar operador',
                                onPressed: () => _deleteOperator(item),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
