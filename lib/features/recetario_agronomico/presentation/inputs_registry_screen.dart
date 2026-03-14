import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../product_catalog/data/product_catalog_repo.dart';
import '../../product_catalog/domain/product_catalog_models.dart';
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
  late final MasterProductCatalogRepo _masterCatalogRepo;
  StreamSubscription<List<MasterProductCatalogItem>>? _masterCatalogSub;
  List<MasterProductCatalogItem> _masterProducts = const [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  static const List<String> _supplyTypeOptions = <String>[
    'herbicida',
    'fungicida',
    'insecticida',
    'coadyuvante',
    'fertilizante',
    'Otros',
  ];
  static const List<String> _formulationOptions =
      productCatalogFormulationOptions;
  static const List<String> _functionOptions = <String>[
    'ninguna',
    'corrector_ph',
    'secuestrante_dureza',
    'antideriva',
    'antiespumante',
    'adherente',
    'humectante',
    'penetrante',
    'acondicionador_agua',
    'otro',
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

  String? _normalizeUnitForForm(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    if (raw == 'kg' || raw == 'kg.') {
      return 'Kg.';
    }
    if (raw == 'lt' || raw == 'lt.' || raw == 'l' || raw == 'l.') {
      return 'Lt.';
    }
    return null;
  }

  String _normalizeFunction(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    for (final option in _functionOptions) {
      if (option.toLowerCase() == raw) {
        return option;
      }
    }
    return 'ninguna';
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
    _masterCatalogRepo = MasterProductCatalogRepo(FirebaseFirestore.instance);
    _masterCatalogSub = _masterCatalogRepo.watchActiveProducts().listen((
      items,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _masterProducts = items;
      });
    });
  }

  Future<void> _showSupplyDialog({SupplyRegistryItem? existing}) async {
    final nameController = TextEditingController(
      text: existing?.commercialName ?? '',
    );
    final activeController = TextEditingController(
      text: existing?.activeIngredient ?? '',
    );
    String? unit = _normalizeUnitForForm(existing?.unit);
    var type = _normalizeSupplyType(existing?.type);
    var formulation = _normalizeFormulation(existing?.formulation);
    var funcion = _normalizeFunction(existing?.funcion);
    if (type != 'coadyuvante') {
      funcion = 'ninguna';
    }
    final isEditing = existing != null;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(isEditing ? 'Editar insumo' : 'Nuevo insumo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_masterProducts.isNotEmpty) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final selected = await _selectMasterCatalogProduct(
                              context,
                            );
                            if (!context.mounted) {
                              return;
                            }
                            if (selected == null) {
                              return;
                            }
                            setModalState(() {
                              nameController.text = selected.commercialName;
                              activeController.text =
                                  selected.activeIngredient ?? '';
                              unit = _normalizeUnitForForm(selected.unit);
                              type = _normalizeSupplyType(selected.type);
                              formulation = _normalizeFormulation(
                                selected.formulation,
                              );
                              funcion = _normalizeFunction(selected.funcion);
                              if (type != 'coadyuvante') {
                                funcion = 'ninguna';
                              }
                            });
                          },
                          icon: const Icon(Icons.search),
                          label: const Text('Seleccionar desde catalogo'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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
                      hint: const Text('Seleccionar unidad'),
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
                          unit = value;
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
                          if (type != 'coadyuvante') {
                            funcion = 'ninguna';
                          }
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
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: funcion,
                      decoration: const InputDecoration(
                        labelText: 'Funcion (opcional)',
                        border: OutlineInputBorder(),
                      ),
                      items: _functionOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option,
                              child: Text(option),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: type == 'coadyuvante'
                          ? (value) {
                              setModalState(() {
                                funcion = _normalizeFunction(value);
                              });
                            }
                          : null,
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
                    final resolvedUnit = _normalizeUnitForForm(unit);
                    if (resolvedUnit == null) {
                      _showSnack('La unidad es obligatoria.');
                      return;
                    }
                    final item = SupplyRegistryItem(
                      id: existing?.id,
                      commercialName: name,
                      activeIngredient: activeController.text.trim().isEmpty
                          ? null
                          : activeController.text.trim(),
                      unit: resolvedUnit,
                      type: _normalizeSupplyType(type),
                      formulation: _normalizeFormulation(formulation),
                      funcion: _normalizeSupplyType(type) == 'coadyuvante'
                          ? _normalizeFunction(funcion)
                          : 'ninguna',
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
                    } on DuplicateSupplyException catch (error) {
                      _showSnack(error.userMessage);
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

  Future<MasterProductCatalogItem?> _selectMasterCatalogProduct(
    BuildContext parentDialogContext,
  ) async {
    if (_masterProducts.isEmpty) {
      return null;
    }
    return showDialog<MasterProductCatalogItem>(
      context: parentDialogContext,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final normalizedQuery = query.trim().toLowerCase();
            final visibleItems = _masterProducts
                .where((item) {
                  if (normalizedQuery.isEmpty) {
                    return true;
                  }
                  return item.commercialName.toLowerCase().contains(
                        normalizedQuery,
                      ) ||
                      (item.activeIngredient ?? '').toLowerCase().contains(
                        normalizedQuery,
                      ) ||
                      item.type.toLowerCase().contains(normalizedQuery);
                })
                .toList(growable: false);

            return AlertDialog(
              title: const Text('Catalogo maestro de productos'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Buscar producto',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          query = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: visibleItems.isEmpty
                          ? const Center(
                              child: Text('No se encontraron productos.'),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: visibleItems.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final item = visibleItems[index];
                                return ListTile(
                                  title: Text(item.commercialName),
                                  subtitle: Text(
                                    'PA: ${item.activeIngredient ?? '-'} | ${item.unit} | ${item.type}',
                                  ),
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _masterCatalogSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(SupplyRegistryItem item, String query) {
    if (query.isEmpty) {
      return true;
    }
    final normalizedQuery = query.toLowerCase();
    final activeIngredient = item.activeIngredient ?? '';
    return item.commercialName.toLowerCase().contains(normalizedQuery) ||
        activeIngredient.toLowerCase().contains(normalizedQuery) ||
        item.type.toLowerCase().contains(normalizedQuery);
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
          final allSupplies = snapshot.data!;
          if (allSupplies.isEmpty) {
            return const Center(child: Text('Sin insumos registrados.'));
          }
          final query = _searchQuery.trim();
          final supplies = allSupplies
              .where((item) => _matchesSearch(item, query))
              .toList(growable: false);
          final hasResults = supplies.isNotEmpty;
          final listItemCount = hasResults ? supplies.length + 1 : 2;
          return ResponsivePage(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: listItemCount,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre, principio activo o tipo',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar busqueda',
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
                  );
                }
                if (!hasResults) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No se encontraron insumos para "$query".',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final item = supplies[index - 1];
                return Card(
                  child: ListTile(
                    title: Text(item.commercialName),
                    subtitle: Text(
                      'Principio activo: ${item.activeIngredient ?? "-"}\n'
                      'Unidad: ${item.unit}    Tipo: ${item.type}    '
                      'Formulación: ${_normalizeFormulation(item.formulation)}    '
                      'Funcion: ${_normalizeFunction(item.funcion)}',
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
