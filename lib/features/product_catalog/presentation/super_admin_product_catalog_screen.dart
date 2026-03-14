import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/responsive_page.dart';
import '../data/product_catalog_repo.dart';
import '../domain/product_catalog_models.dart';
import '../services/product_catalog_importer.dart';

class SuperAdminProductCatalogScreen extends StatefulWidget {
  const SuperAdminProductCatalogScreen({super.key, required this.adminUid});

  final String adminUid;

  @override
  State<SuperAdminProductCatalogScreen> createState() =>
      _SuperAdminProductCatalogScreenState();
}

class _SuperAdminProductCatalogScreenState
    extends State<SuperAdminProductCatalogScreen> {
  final _searchController = TextEditingController();
  late final MasterProductCatalogRepo _repo;
  late final ProductCatalogImporter _importer;
  String _searchQuery = '';
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _repo = MasterProductCatalogRepo(FirebaseFirestore.instance);
    _importer = ProductCatalogImporter();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(MasterProductCatalogItem item, String query) {
    if (query.isEmpty) {
      return true;
    }
    final normalizedQuery = query.toLowerCase();
    return item.commercialName.toLowerCase().contains(normalizedQuery) ||
        (item.activeIngredient ?? '').toLowerCase().contains(normalizedQuery) ||
        item.type.toLowerCase().contains(normalizedQuery) ||
        item.formulation.toLowerCase().contains(normalizedQuery);
  }

  Future<void> _openProductForm({MasterProductCatalogItem? existing}) async {
    final nameController = TextEditingController(
      text: existing?.commercialName ?? '',
    );
    final activeIngredientController = TextEditingController(
      text: existing?.activeIngredient ?? '',
    );
    var unit = existing?.unit ?? 'Lt.';
    var type = existing?.type ?? 'Otros';
    var formulation = existing?.formulation ?? 'Otro';
    var funcion = existing?.funcion;
    var active = existing?.active ?? true;
    var saving = false;
    final isEditing = existing != null;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(isEditing ? 'Editar producto' : 'Nuevo producto'),
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
                      controller: activeIngredientController,
                      decoration: const InputDecoration(
                        labelText: 'Principio activo (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: normalizeProductUnit(unit),
                      decoration: const InputDecoration(
                        labelText: 'Unidad',
                        border: OutlineInputBorder(),
                      ),
                      items: productCatalogUnitOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option,
                              child: Text(option),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: saving
                          ? null
                          : (value) {
                              setModalState(() {
                                unit = normalizeProductUnit(value);
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: normalizeProductType(type),
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                      ),
                      items: productCatalogTypeOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option,
                              child: Text(option),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: saving
                          ? null
                          : (value) {
                              setModalState(() {
                                type = normalizeProductType(value);
                                if (type != 'coadyuvante') {
                                  funcion = null;
                                }
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: normalizeProductFormulation(formulation),
                      decoration: const InputDecoration(
                        labelText: 'Formulacion',
                        border: OutlineInputBorder(),
                      ),
                      items: productCatalogFormulationOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option,
                              child: Text(option),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: saving
                          ? null
                          : (value) {
                              setModalState(() {
                                formulation = normalizeProductFormulation(
                                  value,
                                );
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: normalizeProductFunction(
                        funcion,
                        type: type,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Funcion (opcional)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Sin funcion'),
                        ),
                        ...productCatalogFunctionOptions
                            .where((option) => option != 'ninguna')
                            .map(
                              (option) => DropdownMenuItem<String?>(
                                value: option,
                                child: Text(option),
                              ),
                            ),
                      ],
                      onChanged:
                          saving || normalizeProductType(type) != 'coadyuvante'
                          ? null
                          : (value) {
                              setModalState(() {
                                funcion = value;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activo'),
                      value: active,
                      onChanged: saving
                          ? null
                          : (value) {
                              setModalState(() {
                                active = value;
                              });
                            },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final commercialName = normalizeProductCommercialName(
                            nameController.text,
                          );
                          if (commercialName.isEmpty) {
                            _showSnack('El nombre comercial es obligatorio.');
                            return;
                          }
                          setModalState(() {
                            saving = true;
                          });
                          final item = MasterProductCatalogItem(
                            id: existing?.id,
                            commercialName: commercialName,
                            activeIngredient: normalizeProductActiveIngredient(
                              activeIngredientController.text,
                            ),
                            unit: unit,
                            type: type,
                            formulation: formulation,
                            funcion: funcion,
                            active: active,
                            source: existing?.source ?? 'manual',
                          );
                          try {
                            if (isEditing) {
                              await _repo.updateProduct(
                                item: item,
                                actorUid: widget.adminUid,
                              );
                            } else {
                              await _repo.createProduct(
                                item: item,
                                actorUid: widget.adminUid,
                              );
                            }
                            if (!dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                          } catch (error) {
                            if (!mounted) {
                              return;
                            }
                            _showSnack('No se pudo guardar: $error');
                          } finally {
                            if (dialogContext.mounted) {
                              setModalState(() {
                                saving = false;
                              });
                            }
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

    Future<void>.delayed(const Duration(milliseconds: 300), () {
      nameController.dispose();
      activeIngredientController.dispose();
    });
  }

  Future<void> _toggleActive(MasterProductCatalogItem item, bool active) async {
    final id = item.id?.trim() ?? '';
    if (id.isEmpty) {
      return;
    }
    try {
      await _repo.setProductActive(
        productId: id,
        active: active,
        actorUid: widget.adminUid,
      );
    } catch (error) {
      _showSnack('No se pudo actualizar estado: $error');
    }
  }

  Future<void> _importCatalog() async {
    if (_importing) {
      return;
    }
    setState(() {
      _importing = true;
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        withData: true,
        allowedExtensions: const ['csv', 'xlsx', 'xls'],
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }
      final file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      final extension = (file.extension ?? '').trim().toLowerCase();
      if (bytes == null || bytes.isEmpty) {
        _showSnack('No se pudo leer el archivo seleccionado.');
        return;
      }
      if (extension.isEmpty) {
        _showSnack('No se pudo determinar la extension del archivo.');
        return;
      }

      final preview = _importer.parseBytes(bytes: bytes, extension: extension);
      if (!preview.hasValidRows && preview.issues.isEmpty) {
        _showSnack('No se encontraron filas validas para importar.');
        return;
      }

      final shouldImport = await _showImportPreviewDialog(preview);
      if (shouldImport != true) {
        return;
      }

      final result = await _repo.upsertImportedProducts(
        products: preview.products,
        actorUid: widget.adminUid,
        source: extension == 'csv' ? 'import_csv' : 'import_excel',
      );

      if (!mounted) {
        return;
      }
      _showSnack(
        'Importacion completada. Creados: ${result.created}, actualizados: ${result.updated}, omitidos: ${result.skipped}.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('No se pudo importar: $error');
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
        });
      }
    }
  }

  Future<bool?> _showImportPreviewDialog(ProductCatalogImportPreview preview) {
    final sampleProducts = preview.products.take(8).toList(growable: false);
    final sampleIssues = preview.issues.take(8).toList(growable: false);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Vista previa de importacion'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Filas validas: ${preview.products.length}'),
                  Text('Filas invalidas: ${preview.issues.length}'),
                  Text('Duplicadas en archivo: ${preview.duplicateRows}'),
                  const SizedBox(height: 12),
                  if (sampleProducts.isNotEmpty) ...[
                    const Text('Muestra de filas validas:'),
                    const SizedBox(height: 6),
                    ...sampleProducts.map(
                      (item) => Text(
                        '- ${item.commercialName} | ${item.unit} | ${item.type}',
                      ),
                    ),
                    if (preview.products.length > sampleProducts.length)
                      Text(
                        '... y ${preview.products.length - sampleProducts.length} mas.',
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (sampleIssues.isNotEmpty) ...[
                    const Text('Muestra de errores:'),
                    const SizedBox(height: 6),
                    ...sampleIssues.map(
                      (issue) =>
                          Text('- Fila ${issue.rowNumber}: ${issue.reason}'),
                    ),
                    if (preview.issues.length > sampleIssues.length)
                      Text(
                        '... y ${preview.issues.length - sampleIssues.length} mas.',
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: preview.products.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: const Text('Importar'),
            ),
          ],
        );
      },
    );
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
      appBar: AppBar(
        title: const Text('Catalogos de Productos'),
        actions: [
          IconButton(
            onPressed: _importing ? null : _importCatalog,
            tooltip: 'Importar CSV/Excel',
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openProductForm,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo producto'),
      ),
      body: StreamBuilder<List<MasterProductCatalogItem>>(
        stream: _repo.watchProducts(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allProducts = snapshot.data!;
          final query = _searchQuery.trim();
          final visibleProducts = allProducts
              .where((item) => _matchesSearch(item, query))
              .toList(growable: false);

          return ResponsivePage(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: visibleProducts.isEmpty
                  ? 2
                  : visibleProducts.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final activeCount = allProducts
                      .where((it) => it.active)
                      .length;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText:
                              'Buscar por nombre, principio activo o tipo',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpiar',
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
                      const SizedBox(height: 10),
                      Text(
                        'Total: ${allProducts.length} | Activos: $activeCount | Inactivos: ${allProducts.length - activeCount}',
                      ),
                    ],
                  );
                }
                if (visibleProducts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No hay productos para mostrar.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final item = visibleProducts[index - 1];
                final colorScheme = Theme.of(context).colorScheme;
                return Card(
                  child: ListTile(
                    title: Text(item.commercialName),
                    subtitle: Text(
                      'Principio activo: ${item.activeIngredient ?? '-'}\n'
                      'Unidad: ${item.unit} | Tipo: ${item.type} | Formulacion: ${item.formulation}\n'
                      'Funcion: ${item.funcion ?? '-'} | Fuente: ${item.source}',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Editar',
                          onPressed: () => _openProductForm(existing: item),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        Switch(
                          value: item.active,
                          activeThumbColor: colorScheme.primary,
                          onChanged: (value) => _toggleActive(item, value),
                        ),
                      ],
                    ),
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
