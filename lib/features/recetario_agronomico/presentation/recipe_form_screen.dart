import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/recetario_repo.dart';
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

  final _titleController = TextEditingController();
  final _objectiveController = TextEditingController();
  final _cropController = TextEditingController();
  final _stageController = TextEditingController();
  final _waterVolumeController = TextEditingController();
  final _warningsController = TextEditingController();
  final _notesController = TextEditingController();

  final List<_DoseLineInput> _doseLineInputs = [];
  final List<TextEditingController> _mixOrderControllers = [];

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
    _populateForm(widget.recipe);
  }

  void _populateForm(Recipe? recipe) {
    if (recipe == null) {
      _doseLineInputs.add(_DoseLineInput.empty());
      _mixOrderControllers.add(TextEditingController());
      return;
    }

    _titleController.text = recipe.title;
    _objectiveController.text = recipe.objective;
    _cropController.text = recipe.crop;
    _stageController.text = recipe.stage;
    _waterVolumeController.text = recipe.waterVolumeLHa.toString();
    _warningsController.text = recipe.warnings;
    _notesController.text = recipe.notes;

    if (recipe.doseLines.isEmpty) {
      _doseLineInputs.add(_DoseLineInput.empty());
    } else {
      for (final line in recipe.doseLines) {
        _doseLineInputs.add(_DoseLineInput.fromLine(line));
      }
    }

    if (recipe.mixOrder.isEmpty) {
      _mixOrderControllers.add(TextEditingController());
    } else {
      for (final item in recipe.mixOrder) {
        _mixOrderControllers.add(TextEditingController(text: item));
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
    _warningsController.dispose();
    _notesController.dispose();
    for (final row in _doseLineInputs) {
      row.dispose();
    }
    for (final step in _mixOrderControllers) {
      step.dispose();
    }
    super.dispose();
  }

  Future<void> _saveRecipe({required String status}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!widget.session.access.canEditRecetario) {
      _showSnack('Sin permisos para editar recetas.');
      return;
    }

    final doseLines = _doseLineInputs
        .map((input) => input.toDoseLine())
        .where((line) => line != null)
        .cast<DoseLine>()
        .toList(growable: false);

    final mixOrder = _mixOrderControllers
        .map((controller) => controller.text.trim())
        .where((step) => step.isNotEmpty)
        .toList(growable: false);

    final baseRecipe = Recipe(
      id: widget.recipe?.id,
      title: _titleController.text.trim(),
      objective: _objectiveController.text.trim(),
      crop: _cropController.text.trim(),
      stage: _stageController.text.trim(),
      doseLines: doseLines,
      waterVolumeLHa: parseFlexibleDouble(_waterVolumeController.text.trim()),
      mixOrder: mixOrder,
      warnings: _warningsController.text.trim(),
      notes: _notesController.text.trim(),
      status: status,
      createdBy: widget.recipe?.createdBy ?? widget.session.uid,
      createdAt: widget.recipe?.createdAt ?? DateTime.now(),
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
      _showSnack('Receta guardada ($status).');
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
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titulo',
                    border: OutlineInputBorder(),
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
                const SizedBox(height: 18),
                _buildDoseLinesEditor(),
                const SizedBox(height: 18),
                _buildMixOrderEditor(),
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
                      label: const Text('Guardar draft'),
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
        for (var index = 0; index < _doseLineInputs.length; index++) ...[
          _DoseLineEditorRow(
            key: ValueKey('dose_$index'),
            input: _doseLineInputs[index],
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

  Widget _buildMixOrderEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Checklist / orden de carga',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(
                () => _mixOrderControllers.add(TextEditingController()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Agregar paso'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < _mixOrderControllers.length; index++) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TextFormField(
                      controller: _mixOrderControllers[index],
                      decoration: InputDecoration(
                        labelText: 'Paso ${index + 1}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    IconButton(
                      onPressed: _mixOrderControllers.length == 1
                          ? null
                          : () {
                              setState(() {
                                _mixOrderControllers.removeAt(index).dispose();
                              });
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _mixOrderControllers[index],
                      decoration: InputDecoration(
                        labelText: 'Paso ${index + 1}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _mixOrderControllers.length == 1
                        ? null
                        : () {
                            setState(() {
                              _mixOrderControllers.removeAt(index).dispose();
                            });
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              );
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
}

class _DoseLineEditorRow extends StatelessWidget {
  const _DoseLineEditorRow({super.key, required this.input, this.onRemove});

  final _DoseLineInput input;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: input.productName,
                        decoration: const InputDecoration(
                          labelText: 'Producto comercial',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (compact) ...[
                  TextFormField(
                    controller: input.activeIngredient,
                    decoration: const InputDecoration(
                      labelText: 'Principio activo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: input.dose,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Dosis',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: input.activeIngredient,
                          decoration: const InputDecoration(
                            labelText: 'Principio activo',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          controller: input.dose,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Dosis',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                if (compact) ...[
                  TextFormField(
                    controller: input.unit,
                    decoration: const InputDecoration(
                      labelText: 'Unidad',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: input.functionName,
                    decoration: const InputDecoration(
                      labelText: 'Funcion',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: input.unit,
                          decoration: const InputDecoration(
                            labelText: 'Unidad',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: input.functionName,
                          decoration: const InputDecoration(
                            labelText: 'Funcion',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DoseLineInput {
  _DoseLineInput({
    required this.productName,
    required this.activeIngredient,
    required this.dose,
    required this.unit,
    required this.functionName,
  });

  final TextEditingController productName;
  final TextEditingController activeIngredient;
  final TextEditingController dose;
  final TextEditingController unit;
  final TextEditingController functionName;

  factory _DoseLineInput.empty() {
    return _DoseLineInput(
      productName: TextEditingController(),
      activeIngredient: TextEditingController(),
      dose: TextEditingController(),
      unit: TextEditingController(),
      functionName: TextEditingController(),
    );
  }

  factory _DoseLineInput.fromLine(DoseLine line) {
    return _DoseLineInput(
      productName: TextEditingController(text: line.productName),
      activeIngredient: TextEditingController(
        text: line.activeIngredient ?? '',
      ),
      dose: TextEditingController(text: line.dose.toString()),
      unit: TextEditingController(text: line.unit),
      functionName: TextEditingController(text: line.functionName),
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
      unit: unit.text.trim(),
      functionName: functionName.text.trim(),
    );
  }

  void dispose() {
    productName.dispose();
    activeIngredient.dispose();
    dose.dispose();
    unit.dispose();
    functionName.dispose();
  }
}
