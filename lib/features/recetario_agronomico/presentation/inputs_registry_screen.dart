import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/catalog_repo.dart';
import '../domain/catalog_models.dart';

class InputsRegistryScreen extends StatefulWidget {
  const InputsRegistryScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<InputsRegistryScreen> createState() => _InputsRegistryScreenState();
}

class _InputsRegistryScreenState extends State<InputsRegistryScreen> {
  late final RecetarioCatalogRepo _repo;
  static const List<String> _supplyTypeOptions = <String>[
    'herbicida',
    'fungicida',
    'insecticida',
    'coadyuvante',
    'fertilizante',
    'Otros',
  ];
  static const List<String> _formulationOptions = <String>[
    'WP',
    'WG',
    'SC',
    'EC',
    'SL',
    'Coadyuvante',
    'Aceite',
    'Otro',
  ];

  bool get _canEdit => widget.session.access.canEditRecetario;

  String _normalizeSupplyType(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    for (final option in _supplyTypeOptions) {
      if (option.toLowerCase() == raw) {
        return option;
      }
    }
    return 'Otros';
  }

  String _normalizeCommercialName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  }

  String _normalizeFormulation(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    for (final option in _formulationOptions) {
      if (option.toLowerCase() == raw) {
        return option;
      }
    }
    return 'Otro';
  }

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

  Future<void> _showSupplyDialog({SupplyRegistryItem? existing}) async {
    final nameController = TextEditingController(
      text: existing?.commercialName ?? '',
    );
    final activeController = TextEditingController(
      text: existing?.activeIngredient ?? '',
    );
    var unit = existing?.unit == 'Kg.' ? 'Kg.' : 'Lt.';
    var type = _normalizeSupplyType(existing?.type);
    var formulation = _normalizeFormulation(existing?.formulation);
    final isEditing = existing != null;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(isEditing ? 'Editar insumo' : 'Nuevo insumo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre comercial',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: activeController,
                      decoration: const InputDecoration(
                        labelText: 'Principio activo (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: unit,
                      decoration: const InputDecoration(
                        labelText: 'Unidad',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Kg.', child: Text('Kg.')),
                        DropdownMenuItem(value: 'Lt.', child: Text('Lt.')),
                      ],
                      onChanged: (value) {
                        setModalState(() {
                          unit = value ?? 'Lt.';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                      ),
                      items: _supplyTypeOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option,
                              child: Text(option),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setModalState(() {
                          type = value ?? 'Otros';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: formulation,
                      decoration: const InputDecoration(
                        labelText: 'Formulación',
                        border: OutlineInputBorder(),
                      ),
                      items: _formulationOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option,
                              child: Text(option),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setModalState(() {
                          formulation = value ?? 'Otro';
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = _normalizeCommercialName(nameController.text);
                    if (name.isEmpty) {
                      _showSnack('El nombre comercial es obligatorio.');
                      return;
                    }
                    final item = SupplyRegistryItem(
                      id: existing?.id,
                      commercialName: name,
                      activeIngredient: activeController.text.trim().isEmpty
                          ? null
                          : activeController.text.trim(),
                      unit: unit,
                      type: _normalizeSupplyType(type),
                      formulation: _normalizeFormulation(formulation),
                    );
                    try {
                      if (isEditing) {
                        await _repo.updateSupply(item);
                      } else {
                        await _repo.createSupply(item);
                      }
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                    } catch (error) {
                      _showSnack('No se pudo guardar el insumo: $error');
                    }
                  },
                  child: Text(isEditing ? 'Guardar' : 'Crear'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    activeController.dispose();
  }

  Future<void> _deleteSupply(SupplyRegistryItem item) async {
    final id = item.id;
    if (id == null || id.isEmpty) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar insumo'),
          content: Text('¿Eliminar "${item.commercialName}"?'),
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
      await _repo.deleteSupply(id);
    } catch (error) {
      _showSnack('No se pudo eliminar el insumo: $error');
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro de Insumos')),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: _showSupplyDialog,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo insumo'),
            )
          : null,
      body: StreamBuilder<List<SupplyRegistryItem>>(
        stream: _repo.watchSupplies(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final supplies = snapshot.data!;
          if (supplies.isEmpty) {
            return const Center(child: Text('Sin insumos registrados.'));
          }
          return ResponsivePage(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: supplies.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = supplies[index];
                return Card(
                  child: ListTile(
                    title: Text(item.commercialName),
                    subtitle: Text(
                      'Principio activo: ${item.activeIngredient ?? "-"}\nUnidad: ${item.unit}    Tipo: ${item.type}    Formulación: ${_normalizeFormulation(item.formulation)}',
                    ),
                    isThreeLine: true,
                    trailing: _canEdit
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar insumo',
                                onPressed: () =>
                                    _showSupplyDialog(existing: item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Eliminar insumo',
                                onPressed: () => _deleteSupply(item),
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
