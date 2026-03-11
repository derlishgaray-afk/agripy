import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/catalog_repo.dart';
import '../domain/catalog_models.dart';
import '../domain/models.dart';

class FieldsRegistryScreen extends StatefulWidget {
  const FieldsRegistryScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<FieldsRegistryScreen> createState() => _FieldsRegistryScreenState();
}

class _FieldsRegistryScreenState extends State<FieldsRegistryScreen> {
  late final RecetarioCatalogRepo _repo;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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

  Future<void> _showFieldDialog({FieldRegistryItem? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final isEditing = existing != null;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Editar campo' : 'Nuevo campo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del campo',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  _showSnack('El nombre del campo es obligatorio.');
                  return;
                }
                try {
                  if (isEditing) {
                    await _repo.updateField(fieldId: existing.id!, name: name);
                  } else {
                    await _repo.createField(name: name);
                  }
                  if (!context.mounted) {
                    return;
                  }
                  Navigator.of(context).pop();
                } catch (error) {
                  _showSnack('No se pudo guardar el campo: $error');
                }
              },
              child: Text(isEditing ? 'Guardar' : 'Crear'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
  }

  Future<void> _showLotDialog(
    FieldRegistryItem field, {
    FieldLot? existing,
    int? lotIndex,
  }) async {
    final isEditing = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final areaController = TextEditingController(
      text: existing == null ? '' : existing.areaHa.toString(),
    );
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Editar lote' : 'Nuevo lote'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del lote',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: areaController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Superficie (ha)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final area = parseFlexibleDouble(areaController.text.trim());
                if (name.isEmpty) {
                  _showSnack('El nombre del lote es obligatorio.');
                  return;
                }
                try {
                  if (isEditing) {
                    final index = lotIndex;
                    if (index == null) {
                      _showSnack('No se pudo editar el lote.');
                      return;
                    }
                    await _repo.updateLot(
                      field: field,
                      lotIndex: index,
                      lotName: name,
                      lotAreaHa: area,
                    );
                  } else {
                    await _repo.addLot(
                      field: field,
                      lotName: name,
                      lotAreaHa: area,
                    );
                  }
                  if (!context.mounted) {
                    return;
                  }
                  Navigator.of(context).pop();
                } catch (error) {
                  _showSnack('No se pudo guardar el lote: $error');
                }
              },
              child: Text(isEditing ? 'Guardar' : 'Crear'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    areaController.dispose();
  }

  Future<void> _deleteField(FieldRegistryItem field) async {
    final fieldId = field.id;
    if (fieldId == null || fieldId.isEmpty) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar campo'),
          content: Text('¿Eliminar "${field.name}" y todos sus lotes?'),
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
      await _repo.deleteField(fieldId);
    } catch (error) {
      _showSnack('No se pudo eliminar el campo: $error');
    }
  }

  Future<void> _deleteLot(FieldRegistryItem field, int index) async {
    try {
      await _repo.removeLot(field: field, lotIndex: index);
    } catch (error) {
      _showSnack('No se pudo eliminar el lote: $error');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double _fieldTotalArea(FieldRegistryItem field) {
    if (field.lots.isEmpty) {
      return field.totalAreaHa;
    }
    var total = 0.0;
    for (final lot in field.lots) {
      total += lot.areaHa;
    }
    return total;
  }

  bool _matchesSearch(FieldRegistryItem field, String query) {
    if (query.isEmpty) {
      return true;
    }
    final normalizedQuery = query.toLowerCase();
    if (field.name.toLowerCase().contains(normalizedQuery)) {
      return true;
    }
    for (final lot in field.lots) {
      if (lot.name.toLowerCase().contains(normalizedQuery)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro de Campos')),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: _showFieldDialog,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo campo'),
            )
          : null,
      body: StreamBuilder<List<FieldRegistryItem>>(
        stream: _repo.watchFields(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allFields = snapshot.data!;
          if (allFields.isEmpty) {
            return const Center(child: Text('Sin campos registrados.'));
          }
          final query = _searchQuery.trim();
          final fields = allFields
              .where((field) => _matchesSearch(field, query))
              .toList(growable: false);
          return ResponsivePage(
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar campo o lote',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: fields.isEmpty
                      ? Center(
                          child: Text(
                            'No se encontraron campos para "$query".',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: fields.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final field = fields[index];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            field.name,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                        ),
                                        if (_canEdit)
                                          IconButton(
                                            tooltip: 'Editar campo',
                                            onPressed: () => _showFieldDialog(
                                              existing: field,
                                            ),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                          ),
                                        if (_canEdit)
                                          IconButton(
                                            tooltip: 'Eliminar campo',
                                            onPressed: () =>
                                                _deleteField(field),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                          ),
                                      ],
                                    ),
                                    Text(
                                      'Superficie total: ${_fieldTotalArea(field).toStringAsFixed(2)} ha',
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Lotes',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 6),
                                    if (field.lots.isEmpty)
                                      const Text('Sin lotes cargados.')
                                    else
                                      ...field.lots.asMap().entries.map((
                                        entry,
                                      ) {
                                        final lot = entry.value;
                                        return Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '- ${lot.name}: ${lot.areaHa.toStringAsFixed(2)} ha',
                                              ),
                                            ),
                                            if (_canEdit)
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18,
                                                ),
                                                tooltip: 'Editar lote',
                                                onPressed: () => _showLotDialog(
                                                  field,
                                                  existing: lot,
                                                  lotIndex: entry.key,
                                                ),
                                              ),
                                            if (_canEdit)
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                ),
                                                tooltip: 'Eliminar lote',
                                                onPressed: () => _deleteLot(
                                                  field,
                                                  entry.key,
                                                ),
                                              ),
                                          ],
                                        );
                                      }),
                                    if (_canEdit) ...[
                                      const SizedBox(height: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => _showLotDialog(field),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Agregar lote'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
