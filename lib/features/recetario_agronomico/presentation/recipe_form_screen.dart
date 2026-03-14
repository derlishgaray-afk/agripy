import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/catalog_repo.dart';
import '../data/recetario_repo.dart';
import '../domain/catalog_models.dart';
import '../domain/models.dart';
import '../services/funcion_priority.dart';
import '../services/mix_validation_service.dart';

String _normalizeCommercialNameText(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
}

String _stripFormulationSuffix(String value) {
  return value.replaceAll(RegExp(r'\s*\([^()]*\)\s*$'), '').trim();
}

String _normalizeFormulationText(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  return normalized;
}

String? _extractFormulationFromLabel(String value) {
  final match = RegExp(r'\(([^()]+)\)\s*$').firstMatch(value.trim());
  final formulation = _normalizeFormulationText(match?.group(1));
  if (formulation.isEmpty) {
    return null;
  }
  return formulation;
}

String _formatSupplyProductLabel(SupplyRegistryItem supply) {
  final commercialName = _normalizeCommercialNameText(supply.commercialName);
  final formulation = _normalizeFormulationText(supply.formulation);
  if (formulation.isEmpty) {
    return commercialName;
  }
  return '$commercialName ($formulation)';
}

class RecipeFormScreen extends StatefulWidget {
  const RecipeFormScreen({super.key, required this.session, this.recipe});

  final AppSession session;
  final Recipe? recipe;

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

enum _UnsavedExitDecision { save, discard }

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final RecetarioRepo _repo;
  late final RecetarioCatalogRepo _catalogRepo;
  final MixValidationService _mixValidationService =
      const MixValidationService();

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
  bool _formulationOrderSuggested = false;
  String _initialFormSnapshot = '';
  bool _initialSnapshotSettled = false;

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
        if (!_initialSnapshotSettled) {
          if (!_hasUnsavedChanges()) {
            _initialFormSnapshot = _buildFormSnapshot();
          }
          _initialSnapshotSettled = true;
        }
      });
    });
    _populateForm(widget.recipe);
  }

  void _populateForm(Recipe? recipe) {
    if (recipe == null) {
      _doseLineInputs.add(_DoseLineInput.empty());
      _initialFormSnapshot = _buildFormSnapshot();
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
    _initialFormSnapshot = _buildFormSnapshot();
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
          line.formulation = _extractFormulationFromLabel(
            line.productName.text,
          );
          line.functionName = '';
          continue;
        }
        line.productName.text = _formatSupplyProductLabel(selectedSupply);
        line.activeIngredient.text = selectedSupply.activeIngredient ?? '';
        line.unit.text = _normalizeUnit(selectedSupply.unit);
        line.formulation = _normalizeFormulationText(
          selectedSupply.formulation,
        );
        line.functionName = normalizeFuncionKey(selectedSupply.funcion);
        continue;
      }
      final product = line.productName.text.trim();
      if (product.isEmpty) {
        line.formulation = null;
        line.functionName = '';
        continue;
      }
      final matched = _findSupplyByCommercialName(product);
      if (matched == null) {
        line.formulation = _extractFormulationFromLabel(product);
        line.functionName = '';
        continue;
      }
      line.selectedSupplyId = matched.id;
      line.productName.text = _formatSupplyProductLabel(matched);
      line.activeIngredient.text = matched.activeIngredient ?? '';
      line.unit.text = _normalizeUnit(matched.unit);
      line.formulation = _normalizeFormulationText(matched.formulation);
      line.functionName = normalizeFuncionKey(matched.funcion);
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
    final normalized = _stripFormulationSuffix(
      commercialName,
    ).trim().toLowerCase();
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
    var hasProductWithValidDose = false;
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
      hasProductWithValidDose = true;
    }
    if (!hasProductWithValidDose) {
      return 'Agrega al menos un producto comercial con dosis antes de publicar.';
    }
    return null;
  }

  List<String> _buildMixOrderFromDoseLines(List<DoseLine> doseLines) {
    return doseLines
        .map((line) => line.productName.trim())
        .where((step) => step.isNotEmpty)
        .toList(growable: false);
  }

  int _getFormulationPriority(String? formulation) {
    final normalized = (formulation ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'wp':
      case 'sp':
        return 1;
      case 'wg':
      case 'gr':
      case 'sg':
      case 'dt':
      case 'rb':
        return 2;
      case 'sc':
      case 'se':
      case 'od':
      case 'cs':
      case 'me':
      case 'fs':
        return 3;
      case 'ec':
      case 'ew':
        return 4;
      case 'sl':
        return 5;
      case 'coadyuvante':
        return 6;
      case 'aceite':
        return 7;
      case 'otro':
        return 8;
      default:
        return 999;
    }
  }

  int _getDoseLinePriority({
    required _DoseLineInput line,
    required SupplyRegistryItem? supply,
  }) {
    if (line.productName.text.trim().isEmpty) {
      return 999;
    }

    final functionKey = normalizeFuncionKey(supply?.funcion);
    final byFunction = funcionPriority(functionKey);
    if (byFunction == funcionPriorityHigh) {
      return byFunction;
    }

    final formulation =
        supply?.formulation ??
        line.formulation ??
        _extractFormulationFromLabel(line.productName.text);
    return _getFormulationPriority(formulation);
  }

  SupplyRegistryItem? _resolveSupplyForDoseLine(_DoseLineInput line) {
    final selectedId = line.selectedSupplyId;
    if (selectedId != null && selectedId.trim().isNotEmpty) {
      final byId = _findSupplyById(selectedId);
      if (byId != null) {
        return byId;
      }
    }
    final productName = line.productName.text.trim();
    if (productName.isEmpty) {
      return null;
    }
    return _findSupplyByCommercialName(productName);
  }

  List<String> _buildMixValidationWarnings() {
    final items = <MixValidationItem>[];
    for (final line in _doseLineInputs) {
      final supply = _resolveSupplyForDoseLine(line);
      final rawProductName = supply?.commercialName ?? line.productName.text;
      final productName = _stripFormulationSuffix(rawProductName).trim();
      if (productName.isEmpty) {
        continue;
      }
      final formulation = _normalizeFormulationText(
        supply?.formulation ??
            line.formulation ??
            _extractFormulationFromLabel(line.productName.text),
      );
      items.add(
        MixValidationItem(
          productName: _normalizeCommercialNameText(productName),
          formulation: formulation,
          type: supply?.type,
          funcion: supply?.funcion,
        ),
      );
    }
    return _mixValidationService.validateMix(items).warnings;
  }

  void _sortDoseLinesByFormulation() {
    if (_doseLineInputs.isEmpty) {
      return;
    }

    final sortable = <_DoseLineSortItem>[];
    for (var i = 0; i < _doseLineInputs.length; i++) {
      final line = _doseLineInputs[i];
      final hasProduct = line.productName.text.trim().isNotEmpty;
      final supply = _resolveSupplyForDoseLine(line);
      final priority = _getDoseLinePriority(line: line, supply: supply);
      sortable.add(
        _DoseLineSortItem(
          line: line,
          originalIndex: i,
          hasProduct: hasProduct,
          priority: priority,
        ),
      );
    }

    sortable.sort((a, b) {
      if (a.hasProduct != b.hasProduct) {
        return a.hasProduct ? -1 : 1;
      }
      final byPriority = a.priority.compareTo(b.priority);
      if (byPriority != 0) {
        return byPriority;
      }
      return a.originalIndex.compareTo(b.originalIndex);
    });

    setState(() {
      _doseLineInputs
        ..clear()
        ..addAll(sortable.map((entry) => entry.line));
      _formulationOrderSuggested = true;
    });

    _showSnack('Orden sugerido aplicado. Puede ajustarlo manualmente.');
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

  String _buildFormSnapshot() {
    final buffer = StringBuffer()
      ..writeln(_titleController.text.trim())
      ..writeln(_objectiveController.text.trim())
      ..writeln(_cropController.text.trim())
      ..writeln(_stageController.text.trim())
      ..writeln(_waterVolumeController.text.trim())
      ..writeln(_nozzleTypesController.text.trim())
      ..writeln(_warningsController.text.trim())
      ..writeln(_notesController.text.trim());

    for (final input in _doseLineInputs) {
      final product = _normalizeCommercialNameText(
        _stripFormulationSuffix(input.productName.text),
      );
      final active = input.activeIngredient.text.trim().toUpperCase();
      final dose = input.dose.text.trim();
      final unit = input.unit.text.trim();
      final formulation = _normalizeFormulationText(
        input.formulation ??
            _extractFormulationFromLabel(input.productName.text),
      );
      buffer.writeln('$product|$active|$dose|$unit|$formulation');
    }
    return buffer.toString();
  }

  bool _hasUnsavedChanges() {
    return _buildFormSnapshot() != _initialFormSnapshot;
  }

  String _normalizedOriginalStatus() {
    final raw = (widget.recipe?.status ?? '').trim().toLowerCase();
    if (raw == 'publicado') {
      return 'published';
    }
    if (raw == 'borrador') {
      return 'draft';
    }
    return raw;
  }

  bool get _saveAsPublishedOnExit => _normalizedOriginalStatus() == 'published';

  String get _unsavedExitSaveStatus =>
      _saveAsPublishedOnExit ? 'published' : 'draft';

  String get _unsavedExitSaveLabel =>
      _saveAsPublishedOnExit ? 'Publicar' : 'Guardar borrador';

  Future<bool> _confirmExitIfNeeded() async {
    if (_saving) {
      return false;
    }
    if (!_hasUnsavedChanges()) {
      return true;
    }
    final decision = await showDialog<_UnsavedExitDecision>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cambios sin guardar'),
          content: const Text('Hay cambios sin guardar. Que deseas hacer?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedExitDecision.discard),
              child: const Text('Salir sin guardar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedExitDecision.save),
              child: Text(_unsavedExitSaveLabel),
            ),
          ],
        );
      },
    );
    if (decision == _UnsavedExitDecision.discard) {
      return true;
    }
    if (decision == _UnsavedExitDecision.save) {
      await _saveRecipe(status: _unsavedExitSaveStatus);
      return false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.recipe != null;
    final hideDraftSaveButton =
        isEditing && _normalizedOriginalStatus() == 'published';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        final allowExit = await _confirmExitIfNeeded();
        if (!allowExit || !context.mounted) {
          return;
        }
        Navigator.of(context).pop(result);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? 'Editar receta' : 'Nueva receta'),
        ),
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
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
                      if (!hideDraftSaveButton)
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
                  labelText: 'Estado fenologico',
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
                  labelText: 'Estado fenologico',
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
    final mixWarnings = _buildMixValidationWarnings();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mezcla / dosis',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _sortDoseLinesByFormulation,
                        icon: const Icon(Icons.auto_fix_high_outlined),
                        label: const Text('Sugerir orden de carga'),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(
                          () => _doseLineInputs.add(_DoseLineInput.empty()),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar fila'),
                      ),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Text(
                  'Mezcla / dosis',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _sortDoseLinesByFormulation,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Sugerir orden de carga'),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: () => setState(
                    () => _doseLineInputs.add(_DoseLineInput.empty()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar fila'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          'El orden de los productos define el checklist / orden de carga.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Text(
          'Puede sugerir el orden de carga automaticamente segun funcion y formulacion, y luego ajustar manualmente.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_formulationOrderSuggested) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Orden sugerido aplicado. Puede ajustarlo manualmente.',
            ),
          ),
        ],
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
            onChanged: () => setState(() {}),
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
        if (mixWarnings.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Validacion de mezcla',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                ...mixWarnings.map(
                  (warning) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('- $warning'),
                  ),
                ),
              ],
            ),
          ),
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
    this.onChanged,
    this.onRemove,
  });

  final _DoseLineInput input;
  final int lineNumber;
  final List<SupplyRegistryItem> supplies;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    Color resolveCardBackground() {
      final brightness = Theme.of(context).brightness;
      final seed =
          '${input.selectedSupplyId ?? ''}|${input.productName.text.trim()}|$lineNumber';
      final hue = (seed.hashCode.abs() % 360).toDouble();
      final saturation = brightness == Brightness.dark ? 0.30 : 0.28;
      final lightness = brightness == Brightness.dark ? 0.26 : 0.90;
      return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
    }

    void notifyChanged() {
      onChanged?.call();
    }

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
                  input.formulation = null;
                  input.functionName = '';
                  input.productName.clear();
                  input.activeIngredient.clear();
                  input.dose.clear();
                  input.unit.text = 'Lt.';
                  notifyChanged();
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
                          input.formulation = null;
                          input.functionName = '';
                          input.productName.clear();
                          input.activeIngredient.clear();
                          input.dose.clear();
                          input.unit.text = 'Lt.';
                          notifyChanged();
                          return;
                        }
                        final selected = picked.supply;
                        if (selected == null) {
                          return;
                        }
                        input.selectedSupplyId = selected.id;
                        input.formulation = _normalizeFormulationText(
                          selected.formulation,
                        );
                        input.productName.text = _formatSupplyProductLabel(
                          selected,
                        );
                        input.activeIngredient.text =
                            selected.activeIngredient ?? '';
                        input.unit.text = _resolveSelectedUnit(selected.unit);
                        input.functionName = normalizeFuncionKey(
                          selected.funcion,
                        );
                        notifyChanged();
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
                  input.formulation = null;
                  input.functionName = '';
                  input.productName.clear();
                  input.activeIngredient.clear();
                  input.dose.clear();
                  input.unit.text = 'Lt.';
                  notifyChanged();
                  return;
                }
                final selected = picked.supply;
                if (selected == null) {
                  return;
                }
                input.selectedSupplyId = selected.id;
                input.formulation = _normalizeFormulationText(
                  selected.formulation,
                );
                input.productName.text = _formatSupplyProductLabel(selected);
                input.activeIngredient.text = selected.activeIngredient ?? '';
                input.unit.text = _resolveSelectedUnit(selected.unit);
                input.functionName = normalizeFuncionKey(selected.funcion);
                notifyChanged();
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
      color: resolveCardBackground(),
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
                    if (!compact) ...[const SizedBox(width: 8), buildActions()],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (compact) ...[
                      Expanded(
                        flex: 10,
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
                      Expanded(
                        flex: 12,
                        child: TextFormField(
                          controller: input.dose,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => notifyChanged(),
                          decoration: const InputDecoration(
                            labelText: 'Dosis',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.fromLTRB(10, 12, 10, 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      buildActions(),
                    ] else ...[
                      SizedBox(
                        width: 130,
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
                        width: 160,
                        child: TextFormField(
                          controller: input.dose,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => notifyChanged(),
                          decoration: const InputDecoration(
                            labelText: 'Dosis',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.fromLTRB(10, 12, 10, 10),
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
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
                                title: Text(_formatSupplyProductLabel(item)),
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

class _DoseLineSortItem {
  const _DoseLineSortItem({
    required this.line,
    required this.originalIndex,
    required this.hasProduct,
    required this.priority,
  });

  final _DoseLineInput line;
  final int originalIndex;
  final bool hasProduct;
  final int priority;
}

class _DoseLineInput {
  _DoseLineInput({
    required this.productName,
    required this.activeIngredient,
    required this.dose,
    required this.unit,
    this.formulation,
    this.functionName = '',
    this.selectedSupplyId,
  });

  final TextEditingController productName;
  final TextEditingController activeIngredient;
  final TextEditingController dose;
  final TextEditingController unit;
  String? formulation;
  String functionName;
  String? selectedSupplyId;

  factory _DoseLineInput.empty() {
    return _DoseLineInput(
      productName: TextEditingController(),
      activeIngredient: TextEditingController(),
      dose: TextEditingController(),
      unit: TextEditingController(text: 'Lt.'),
      formulation: null,
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
      formulation: _normalizeFormulationText(
        line.formulation ?? _extractFormulationFromLabel(line.productName),
      ),
      functionName: normalizeFuncionKey(line.functionName),
      selectedSupplyId: null,
    );
  }

  DoseLine? toDoseLine() {
    final product = productName.text.trim();
    if (product.isEmpty) {
      return null;
    }
    final active = activeIngredient.text.trim();
    final resolvedFormulation = _normalizeFormulationText(
      formulation ?? _extractFormulationFromLabel(product),
    );
    return DoseLine(
      productName: product,
      formulation: resolvedFormulation.isEmpty ? null : resolvedFormulation,
      activeIngredient: active.isEmpty ? null : active,
      dose: parseFlexibleDouble(dose.text.trim()),
      unit: unit.text.trim().isEmpty ? 'Lt.' : unit.text.trim(),
      functionName: normalizeFuncionKey(functionName),
    );
  }

  void dispose() {
    productName.dispose();
    activeIngredient.dispose();
    dose.dispose();
    unit.dispose();
  }
}
