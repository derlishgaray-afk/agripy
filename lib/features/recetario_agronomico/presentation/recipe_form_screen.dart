import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/catalog_repo.dart';
import '../data/recetario_repo.dart';
import '../domain/catalog_models.dart';
import '../domain/models.dart';

class RecipeFormScreen extends StatefulWidget {
  const RecipeFormScreen({super.key, required this.session, this.recipe});

  final AppSession session;
  final Recipe? recipe;

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final RecetarioRepo _repo;
  late final RecetarioCatalogRepo _catalogRepo;

  final _titleController = TextEditingController();
  final _objectiveController = TextEditingController();
  final _cropController = TextEditingController();
  final _stageController = TextEditingController();
  final _waterVolumeController = TextEditingController();
  final _nozzleTypesController = TextEditingController();
  final _warningsController = TextEditingController();
  final _notesController = TextEditingController();

  final List<_DoseLineInput> _doseLineInputs = [];
  StreamSubscription<List<SupplyRegistryItem>>? _suppliesSub;
  List<SupplyRegistryItem> _supplies = const [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repo = RecetarioRepo(
      firestore: FirebaseFirestore.instance,
      tenantId: widget.session.tenantId,
      currentUid: widget.session.uid,
      access: widget.session.access,
    );
    _catalogRepo = RecetarioCatalogRepo(
      firestore: FirebaseFirestore.instance,
      tenantId: widget.session.tenantId,
      currentUid: widget.session.uid,
      access: widget.session.access,
    );
    _suppliesSub = _catalogRepo.watchSupplies().listen((items) {
      if (!mounted) {
        return;
      }
      setState(() {
        _supplies = items;
        _syncDoseLinesWithSupplies();
      });
    });
    _populateForm(widget.recipe);
  }

  void _populateForm(Recipe? recipe) {
    if (recipe == null) {
      _doseLineInputs.add(_DoseLineInput.empty());
      return;
    }

    _titleController.text = recipe.title;
    _objectiveController.text = recipe.objective;
    _cropController.text = recipe.crop;
    _stageController.text = recipe.stage;
    _waterVolumeController.text = recipe.waterVolumeLHa.toString();
    _nozzleTypesController.text = recipe.nozzleTypes;
    _warningsController.text = recipe.warnings;
    _notesController.text = recipe.notes;

    if (recipe.doseLines.isEmpty) {
      _doseLineInputs.add(_DoseLineInput.empty());
    } else {
      for (final line in recipe.doseLines) {
        _doseLineInputs.add(_DoseLineInput.fromLine(line));
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _objectiveController.dispose();
    _cropController.dispose();
    _stageController.dispose();
    _waterVolumeController.dispose();
    _nozzleTypesController.dispose();
    _warningsController.dispose();
    _notesController.dispose();
    for (final row in _doseLineInputs) {
      row.dispose();
    }
    _suppliesSub?.cancel();
    super.dispose();
  }

  void _syncDoseLinesWithSupplies() {
    for (final line in _doseLineInputs) {
      final selectedId = line.selectedSupplyId;
      if (selectedId != null && selectedId.isNotEmpty) {
        final selectedSupply = _findSupplyById(selectedId);
        if (selectedSupply == null) {
          line.selectedSupplyId = null;
          continue;
        }
        line.productName.text = selectedSupply.commercialName;
        line.activeIngredient.text = selectedSupply.activeIngredient ?? '';
        line.unit.text = _normalizeUnit(selectedSupply.unit);
        continue;
      }
      final product = line.productName.text.trim();
      if (product.isEmpty) {
        continue;
      }
      final matched = _findSupplyByCommercialName(product);
      if (matched == null) {
        continue;
      }
      line.selectedSupplyId = matched.id;
      line.productName.text = matched.commercialName;
      line.activeIngredient.text = matched.activeIngredient ?? '';
      line.unit.text = _normalizeUnit(matched.unit);
    }
  }

  SupplyRegistryItem? _findSupplyById(String id) {
    for (final item in _supplies) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  SupplyRegistryItem? _findSupplyByCommercialName(String commercialName) {
    final normalized = commercialName.trim().toLowerCase();
    for (final item in _supplies) {
      if (item.commercialName.trim().toLowerCase() == normalized) {
        return item;
      }
    }
    return null;
  }

  String _normalizeUnit(String unit) {
    final normalized = unit.trim();
    if (normalized == 'Kg.' || normalized == 'Lt.') {
      return normalized;
    }
    return 'Lt.';
  }

  Future<void> _saveRecipe({required String status}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!widget.session.access.canEditRecetario) {
      _showSnack('Sin permisos para editar recetas.');
      return;
    }
    final isEmitted = widget.recipe?.status.trim().toLowerCase() == 'emitted';
    if (isEmitted) {
      _showSnack('Las recetas emitidas no se pueden editar.');
      return;
    }
    if (status.trim().toLowerCase() == 'published') {
      final publishValidationError = _validateDoseLinesForPublish();
      if (publishValidationError != null) {
        _showSnack(publishValidationError);
        return;
      }
    }

    final doseLines = _doseLineInputs
        .map((input) => input.toDoseLine())
        .where((line) => line != null)
        .cast<DoseLine>()
        .toList(growable: false);
    final mixOrder = _buildMixOrderFromDoseLines(doseLines);

    final baseRecipe = Recipe(
      id: widget.recipe?.id,
      title: _titleController.text.trim(),
      objective: _objectiveController.text.trim(),
      crop: _cropController.text.trim(),
      stage: _stageController.text.trim(),
      doseLines: doseLines,
      waterVolumeLHa: parseFlexibleDouble(_waterVolumeController.text.trim()),
      nozzleTypes: _nozzleTypesController.text.trim(),
      mixOrder: mixOrder,
      warnings: _warningsController.text.trim(),
      notes: _notesController.text.trim(),
      status: status,
      createdBy: widget.recipe?.createdBy ?? widget.session.uid,
      createdAt: widget.recipe?.createdAt ?? DateTime.now(),
      emissionCount: widget.recipe?.emissionCount ?? 0,
      lastEmission: widget.recipe?.lastEmission,
    );

    setState(() {
      _saving = true;
    });

    try {
      if (widget.recipe == null) {
        await _repo.createRecipe(baseRecipe);
      } else {
        await _repo.updateRecipe(baseRecipe);
      }
      if (!mounted) {
        return;
      }
      _showSnack('Receta guardada (${_statusLabel(status)}).');
      Navigator.of(context).pop();
    } catch (error) {
      _showSnack('Error al guardar: $error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String? _validateDoseLinesForPublish() {
    for (var i = 0; i < _doseLineInputs.length; i++) {
      final row = _doseLineInputs[i];
      final product = row.productName.text.trim();
      if (product.isEmpty) {
        continue;
      }
      final doseText = row.dose.text.trim();
      final doseValue = parseFlexibleDouble(doseText);
      if (doseText.isEmpty || doseValue <= 0) {
        return 'Completa la dosis en "Producto comercial ${i + 1}" antes de publicar.';
      }
    }
    return null;
  }

  List<String> _buildMixOrderFromDoseLines(List<DoseLine> doseLines) {
    return doseLines
        .map((line) => line.productName.trim())
        .where((step) => step.isNotEmpty)
        .toList(growable: false);
  }

  void _moveDoseLine({required int from, required int to}) {
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= _doseLineInputs.length ||
        to >= _doseLineInputs.length) {
      return;
    }
    setState(() {
      final item = _doseLineInputs.removeAt(from);
      _doseLineInputs.insert(to, item);
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.recipe != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Editar receta' : 'Nueva receta')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ResponsivePage(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Text(
                  'Titulo',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    hintText: 'Ej: 5ta. Aplicacion',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.fromLTRB(12, 16, 12, 14),
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _objectiveController,
                  decoration: const InputDecoration(
                    labelText: 'Objetivo',
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                _buildCropAndStageFields(),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _waterVolumeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Volumen de agua (L/ha)',
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nozzleTypesController,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de pico/boquilla',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                _buildDoseLinesEditor(),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _warningsController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Advertencias',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _saveRecipe(status: 'draft'),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar borrador'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _saveRecipe(status: 'published'),
                      icon: const Icon(Icons.publish_outlined),
                      label: const Text('Publicar'),
                    ),
                  ],
                ),
                if (_saving) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCropAndStageFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        if (compact) {
          return Column(
            children: [
              TextFormField(
                controller: _cropController,
                decoration: const InputDecoration(
                  labelText: 'Cultivo',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stageController,
                decoration: const InputDecoration(
                  labelText: 'Estado fenológico',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _cropController,
                decoration: const InputDecoration(
                  labelText: 'Cultivo',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _stageController,
                decoration: const InputDecoration(
                  labelText: 'Estado fenológico',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDoseLinesEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Mezcla / dosis',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _doseLineInputs.add(_DoseLineInput.empty())),
              icon: const Icon(Icons.add),
              label: const Text('Agregar fila'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'El orden de los productos define el checklist / orden de carga.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < _doseLineInputs.length; index++) ...[
          _DoseLineEditorRow(
            key: ObjectKey(_doseLineInputs[index]),
            input: _doseLineInputs[index],
            lineNumber: index + 1,
            supplies: _supplies,
            onMoveUp: index == 0
                ? null
                : () => _moveDoseLine(from: index, to: index - 1),
            onMoveDown: index == _doseLineInputs.length - 1
                ? null
                : () => _moveDoseLine(from: index, to: index + 1),
            onRemove: _doseLineInputs.length == 1
                ? null
                : () {
                    setState(() {
                      _doseLineInputs.removeAt(index).dispose();
                    });
                  },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo obligatorio';
    }
    return null;
  }

  String _statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'published':
        return 'publicado';
      case 'emitted':
        return 'emitido';
      case 'draft':
      default:
        return 'borrador';
    }
  }
}

class _DoseLineEditorRow extends StatelessWidget {
  const _DoseLineEditorRow({
    super.key,
    required this.input,
    required this.lineNumber,
    required this.supplies,
    this.onMoveUp,
    this.onMoveDown,
    this.onRemove,
  });

  final _DoseLineInput input;
  final int lineNumber;
  final List<SupplyRegistryItem> supplies;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    Widget buildProductField() {
      final hasOptions = supplies.any((item) => (item.id ?? '').isNotEmpty);
      return TextFormField(
        controller: input.productName,
        readOnly: true,
        decoration: InputDecoration(
          labelText: 'Producto comercial $lineNumber',
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Quitar producto',
                onPressed: () {
                  input.selectedSupplyId = null;
                  input.productName.clear();
                  input.activeIngredient.clear();
                  input.dose.clear();
                  input.unit.text = 'Lt.';
                },
                icon: const Icon(Icons.clear),
              ),
              IconButton(
                tooltip: 'Buscar producto',
                onPressed: !hasOptions
                    ? null
                    : () async {
                        final picked = await _pickSupplyWithSearch(
                          context,
                          supplies,
                          selectedSupplyId: input.selectedSupplyId,
                        );
                        if (picked == null) {
                          return;
                        }
                        if (picked.cleared) {
                          input.selectedSupplyId = null;
                          input.productName.clear();
                          input.activeIngredient.clear();
                          input.dose.clear();
                          input.unit.text = 'Lt.';
                          return;
                        }
                        final selected = picked.supply;
                        if (selected == null) {
                          return;
                        }
                        input.selectedSupplyId = selected.id;
                        input.productName.text = selected.commercialName;
                        input.activeIngredient.text =
                            selected.activeIngredient ?? '';
                        input.unit.text = _resolveSelectedUnit(selected.unit);
                      },
                icon: const Icon(Icons.search),
              ),
            ],
          ),
        ),
        onTap: !hasOptions
            ? null
            : () async {
                final picked = await _pickSupplyWithSearch(
                  context,
                  supplies,
                  selectedSupplyId: input.selectedSupplyId,
                );
                if (picked == null) {
                  return;
                }
                if (picked.cleared) {
                  input.selectedSupplyId = null;
                  input.productName.clear();
                  input.activeIngredient.clear();
                  input.dose.clear();
                  input.unit.text = 'Lt.';
                  return;
                }
                final selected = picked.supply;
                if (selected == null) {
                  return;
                }
                input.selectedSupplyId = selected.id;
                input.productName.text = selected.commercialName;
                input.activeIngredient.text = selected.activeIngredient ?? '';
                input.unit.text = _resolveSelectedUnit(selected.unit);
              },
      );
    }

    Widget buildActions() {
      final canReorder = onMoveUp != null || onMoveDown != null;
      if (!canReorder && onRemove == null) {
        return const SizedBox.shrink();
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canReorder)
            IconButton(
              tooltip: 'Subir',
              onPressed: onMoveUp,
              iconSize: 26,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward),
            ),
          const SizedBox(width: 4),
          if (canReorder)
            IconButton(
              tooltip: 'Bajar',
              onPressed: onMoveDown,
              iconSize: 26,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_downward),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: onRemove,
            iconSize: 26,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: buildProductField()),
                    const SizedBox(width: 8),
                    buildActions(),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SizedBox(
                      width: compact ? 110 : 130,
                      child: TextFormField(
                        controller: input.unit,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Unidad',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.fromLTRB(10, 12, 10, 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: compact ? 130 : 160,
                      child: TextFormField(
                        controller: input.dose,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Dosis',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.fromLTRB(10, 12, 10, 10),
                        ),
                      ),
                    ),
                    if (!compact) const Spacer(),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _resolveSelectedUnit(String raw) {
    final normalized = raw.trim();
    if (normalized == 'Kg.' || normalized == 'Lt.') {
      return normalized;
    }
    return 'Lt.';
  }

  Future<_ProductPickerResult?> _pickSupplyWithSearch(
    BuildContext context,
    List<SupplyRegistryItem> options, {
    required String? selectedSupplyId,
  }) async {
    final suppliesWithId = options
        .where((item) => (item.id ?? '').isNotEmpty)
        .toList(growable: false);
    if (suppliesWithId.isEmpty) {
      return null;
    }

    final searchController = TextEditingController();
    var query = '';
    final result = await showDialog<_ProductPickerResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final normalizedQuery = query.trim().toLowerCase();
            final filtered = suppliesWithId
                .where((item) {
                  if (normalizedQuery.isEmpty) {
                    return true;
                  }
                  final commercial = item.commercialName.trim().toLowerCase();
                  final ingredient = (item.activeIngredient ?? '')
                      .trim()
                      .toLowerCase();
                  return commercial.contains(normalizedQuery) ||
                      ingredient.contains(normalizedQuery);
                })
                .toList(growable: false);

            return AlertDialog(
              title: const Text('Seleccionar producto comercial'),
              content: SizedBox(
                width: 560,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Buscar producto',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          query = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView(
                        children: [
                          if (selectedSupplyId != null &&
                              selectedSupplyId.trim().isNotEmpty)
                            ListTile(
                              leading: const Icon(Icons.clear),
                              title: const Text('Quitar producto seleccionado'),
                              onTap: () => Navigator.of(
                                dialogContext,
                              ).pop(const _ProductPickerResult.cleared()),
                            ),
                          if (filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(14),
                              child: Text('Sin resultados para la busqueda.'),
                            )
                          else
                            ...filtered.map((item) {
                              final isSelected = item.id == selectedSupplyId;
                              final subtitle = (item.activeIngredient ?? '')
                                  .trim();
                              return ListTile(
                                title: Text(item.commercialName),
                                subtitle: subtitle.isEmpty
                                    ? Text('Unidad: ${item.unit}')
                                    : Text('$subtitle | Unidad: ${item.unit}'),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle)
                                    : null,
                                onTap: () => Navigator.of(
                                  dialogContext,
                                ).pop(_ProductPickerResult.selected(item)),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
    searchController.dispose();
    return result;
  }
}

class _ProductPickerResult {
  const _ProductPickerResult.selected(this.supply) : cleared = false;

  const _ProductPickerResult.cleared() : supply = null, cleared = true;

  final SupplyRegistryItem? supply;
  final bool cleared;
}

class _DoseLineInput {
  _DoseLineInput({
    required this.productName,
    required this.activeIngredient,
    required this.dose,
    required this.unit,
    this.selectedSupplyId,
  });

  final TextEditingController productName;
  final TextEditingController activeIngredient;
  final TextEditingController dose;
  final TextEditingController unit;
  String? selectedSupplyId;

  factory _DoseLineInput.empty() {
    return _DoseLineInput(
      productName: TextEditingController(),
      activeIngredient: TextEditingController(),
      dose: TextEditingController(),
      unit: TextEditingController(text: 'Lt.'),
      selectedSupplyId: null,
    );
  }

  factory _DoseLineInput.fromLine(DoseLine line) {
    final normalizedUnit = line.unit.trim();
    return _DoseLineInput(
      productName: TextEditingController(text: line.productName),
      activeIngredient: TextEditingController(
        text: line.activeIngredient ?? '',
      ),
      dose: TextEditingController(text: line.dose.toString()),
      unit: TextEditingController(
        text: normalizedUnit == 'Kg.' || normalizedUnit == 'Lt.'
            ? normalizedUnit
            : 'Lt.',
      ),
      selectedSupplyId: null,
    );
  }

  DoseLine? toDoseLine() {
    final product = productName.text.trim();
    if (product.isEmpty) {
      return null;
    }
    final active = activeIngredient.text.trim();
    return DoseLine(
      productName: product,
      activeIngredient: active.isEmpty ? null : active,
      dose: parseFlexibleDouble(dose.text.trim()),
      unit: unit.text.trim().isEmpty ? 'Lt.' : unit.text.trim(),
      functionName: '',
    );
  }

  void dispose() {
    productName.dispose();
    activeIngredient.dispose();
    dose.dispose();
    unit.dispose();
  }
}
