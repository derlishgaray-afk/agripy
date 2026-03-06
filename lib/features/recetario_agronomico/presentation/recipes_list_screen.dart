import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/services/access_controller.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/recetario_repo.dart';
import '../domain/models.dart';
import '../services/recetario_png.dart';
import '../services/recetario_share.dart';

class RecipesListScreen extends StatefulWidget {
  const RecipesListScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<RecipesListScreen> createState() => _RecipesListScreenState();
}

class _RecipesListScreenState extends State<RecipesListScreen> {
  late final RecetarioRepo _repo;
  final RecetarioPngService _pngService = RecetarioPngService();
  final RecetarioShareService _shareService = RecetarioShareService();
  String _statusFilter = 'all';
  String? _sharingRecipeId;

  @override
  void initState() {
    super.initState();
    _repo = RecetarioRepo(
      firestore: FirebaseFirestore.instance,
      tenantId: widget.session.tenantId,
      currentUid: widget.session.uid,
      access: widget.session.access,
    );
  }

  bool get _canEdit => widget.session.access.canEditRecetario;

  bool get _canEmit {
    final role = widget.session.access.role;
    return role == TenantRole.admin || role == TenantRole.engineer;
  }

  Future<void> _openRecipeForm({Recipe? recipe}) async {
    await Navigator.of(
      context,
    ).pushNamed(AppRoutes.recipeForm, arguments: recipe);
  }

  Future<void> _openEmit(Recipe recipe) async {
    await Navigator.of(
      context,
    ).pushNamed(AppRoutes.emitOrder, arguments: recipe);
  }

  String? get _effectiveStatusFilter =>
      _statusFilter == 'all' ? null : _statusFilter;

  Future<void> _reshareAsPng(Recipe recipe) async {
    final recipeId = recipe.id;
    if (recipeId == null || recipeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receta sin identificador.')),
      );
      return;
    }

    setState(() {
      _sharingRecipeId = recipeId;
    });

    try {
      final emission =
          recipe.lastEmission ?? await _repo.getLatestEmissionData(recipeId);
      if (emission == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay datos de emision guardados para compartir.'),
          ),
        );
        return;
      }

      final bytes = await _pngService.buildEmissionPng(
        tenantName: widget.session.tenantName,
        recipe: recipe,
        emission: emission,
      );
      final filenameCode = emission.code.isEmpty ? recipeId : emission.code;
      final file = await _shareService.savePngTemp(
        bytes,
        'recetario_$filenameCode.png',
      );
      final message =
          'Recetario ${emission.code} - ${emission.plotName} - ${recipe.crop} ${recipe.stage}. '
          'Objetivo: ${recipe.objective}.';
      await _shareService.sharePng(file, message);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PNG compartido.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo compartir PNG: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sharingRecipeId = null;
        });
      }
    }
  }

  Future<void> _viewEmittedRecipe(Recipe recipe) async {
    final recipeId = recipe.id;
    RecipeEmissionData? emission = recipe.lastEmission;
    final mixOrderSteps = _resolveMixOrderSteps(recipe);
    if ((emission == null) && recipeId != null && recipeId.isNotEmpty) {
      emission = await _repo.getLatestEmissionData(recipeId);
    }
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(recipe.title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Estado: ${_statusLabel(recipe.status)}'),
                  const SizedBox(height: 8),
                  Text('Cultivo: ${recipe.crop} - ${recipe.stage}'),
                  const SizedBox(height: 4),
                  Text('Objetivo: ${recipe.objective}'),
                  const SizedBox(height: 4),
                  Text('Volumen de agua: ${recipe.waterVolumeLHa} L/ha'),
                  if (recipe.nozzleTypes.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Tipo de pico/boquilla: ${recipe.nozzleTypes}'),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Mezcla / dosis',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  if (recipe.doseLines.isEmpty)
                    const Text('- Sin lineas')
                  else
                    ...recipe.doseLines.map((line) {
                      final perTank = emission == null
                          ? 0.0
                          : _calculatePerTankAmount(
                              dosePerHa: line.dose,
                              tankCapacityLt: emission.tankCapacityLt,
                              waterVolumeLHa: recipe.waterVolumeLHa,
                            );
                      return Text(
                        '- ${line.productName}: Unidad ${line.unit} | Dosis ${line.dose} | Por tanque ${perTank.toStringAsFixed(2)} ${line.unit}',
                      );
                    }),
                  const SizedBox(height: 12),
                  Text(
                    'Checklist / orden de carga',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  if (mixOrderSteps.isEmpty)
                    const Text('- Sin pasos')
                  else
                    ...mixOrderSteps.map((step) => Text('* $step')),
                  const SizedBox(height: 12),
                  if (emission != null) ...[
                    Text(
                      'Datos de emisión',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text('Código: ${emission.code}'),
                    Text('Campo: ${emission.farmName}'),
                    Text('Lote: ${emission.plotName}'),
                    Text('Superficie: ${emission.areaHa} ha'),
                    Text('Superficie afectada: ${emission.affectedAreaHa} ha'),
                    Text('Capacidad tanque: ${emission.tankCapacityLt} L'),
                    Text('Cantidad de tanque: ${emission.tankCount}'),
                    Text('Responsable: ${emission.engineerName}'),
                    Text('Operador: ${emission.operatorName}'),
                    Text(
                      'Fecha emisión: ${_formatDateTime(emission.issuedAt)}',
                    ),
                    Text(
                      'Fecha planificada: ${emission.plannedDate == null ? "No definida" : _formatDateTime(emission.plannedDate!)}',
                    ),
                  ] else
                    const Text('Sin datos de emisión guardados.'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _viewRequiredProducts(Recipe recipe) async {
    final messenger = ScaffoldMessenger.of(context);
    final recipeId = recipe.id;
    RecipeEmissionData? emission = recipe.lastEmission;
    if ((emission == null) && recipeId != null && recipeId.isNotEmpty) {
      emission = await _repo.getLatestEmissionData(recipeId);
    }
    if (!mounted) {
      return;
    }
    if (emission == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No hay datos de emision para calcular.')),
      );
      return;
    }
    final confirmedEmission = emission;

    final affectedAreaHa = confirmedEmission.affectedAreaHa;
    final lines = recipe.doseLines;
    await showDialog<void>(
      context: context,
      builder: (context) {
        var sharing = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Productos necesarios'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Campo: ${confirmedEmission.farmName}'),
                      const SizedBox(height: 4),
                      Text('Lotes: ${confirmedEmission.plotName}'),
                      const SizedBox(height: 4),
                      Text(
                        'Superficie afectada: ${affectedAreaHa.toStringAsFixed(2)} ha',
                      ),
                      const SizedBox(height: 10),
                      if (lines.isEmpty)
                        const Text('Sin lineas de mezcla.')
                      else
                        ...lines.map((line) {
                          final totalRequired = _calculateTotalRequiredAmount(
                            dosePerHa: line.dose,
                            affectedAreaHa: affectedAreaHa,
                          );
                          final perTank = _calculatePerTankAmount(
                            dosePerHa: line.dose,
                            tankCapacityLt: confirmedEmission.tankCapacityLt,
                            waterVolumeLHa: recipe.waterVolumeLHa,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '- ${line.productName}: '
                              '${totalRequired.toStringAsFixed(2)} ${line.unit} total '
                              '(por tanque: ${perTank.toStringAsFixed(2)} ${line.unit})',
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: sharing
                      ? null
                      : () async {
                          setDialogState(() {
                            sharing = true;
                          });
                          try {
                            await _shareRequiredProductsAsPng(
                              recipe: recipe,
                              emission: confirmedEmission,
                            );
                            if (!mounted) {
                              return;
                            }
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('PNG de productos compartido.'),
                              ),
                            );
                          } catch (error) {
                            if (!mounted) {
                              return;
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'No se pudo compartir PNG de productos: $error',
                                ),
                              ),
                            );
                          } finally {
                            if (context.mounted) {
                              setDialogState(() {
                                sharing = false;
                              });
                            }
                          }
                        },
                  icon: sharing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share_outlined),
                  label: const Text('Compartir PNG'),
                ),
                TextButton(
                  onPressed: sharing ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _shareRequiredProductsAsPng({
    required Recipe recipe,
    required RecipeEmissionData emission,
  }) async {
    final recipeId = recipe.id;
    final fallbackCode = (recipeId == null || recipeId.isEmpty)
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : recipeId;
    final filenameCode = emission.code.trim().isEmpty
        ? fallbackCode
        : emission.code.trim();
    final bytes = await _pngService.buildRequiredProductsPng(
      tenantName: widget.session.tenantName,
      recipe: recipe,
      emission: emission,
    );
    final file = await _shareService.savePngTemp(
      bytes,
      'productos_necesarios_$filenameCode.png',
    );
    final message =
        'Productos necesarios ${emission.code} - ${emission.plotName}. '
        'Superficie afectada: ${emission.affectedAreaHa.toStringAsFixed(2)} ha.';
    await _shareService.sharePng(file, message);
  }

  String _statusLabel(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'emitted') {
      return 'Emitido';
    }
    if (normalized == 'published') {
      return 'Publicado';
    }
    return 'Borrador';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  double _calculatePerTankAmount({
    required double dosePerHa,
    required double tankCapacityLt,
    required double waterVolumeLHa,
  }) {
    if (dosePerHa <= 0 || tankCapacityLt <= 0 || waterVolumeLHa <= 0) {
      return 0;
    }
    return dosePerHa * (tankCapacityLt / waterVolumeLHa);
  }

  double _calculateTotalRequiredAmount({
    required double dosePerHa,
    required double affectedAreaHa,
  }) {
    if (dosePerHa <= 0 || affectedAreaHa <= 0) {
      return 0;
    }
    return dosePerHa * affectedAreaHa;
  }

  List<String> _resolveMixOrderSteps(Recipe recipe) {
    final explicitSteps = recipe.mixOrder
        .map((step) => step.trim())
        .where((step) => step.isNotEmpty)
        .toList(growable: false);
    if (explicitSteps.isNotEmpty) {
      return explicitSteps;
    }
    return recipe.doseLines
        .map((line) => line.productName.trim())
        .where((step) => step.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompactWidth(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recetario Agronómico'),
        actions: [
          if (compact)
            PopupMenuButton<String>(
              tooltip: 'Filtrar estado',
              initialValue: _statusFilter,
              icon: const Icon(Icons.filter_list),
              onSelected: (value) => setState(() => _statusFilter = value),
              itemBuilder: (context) => const [
                PopupMenuItem<String>(value: 'all', child: Text('Todos')),
                PopupMenuItem<String>(value: 'draft', child: Text('Borrador')),
                PopupMenuItem<String>(
                  value: 'published',
                  child: Text('Publicado'),
                ),
                PopupMenuItem<String>(value: 'emitted', child: Text('Emitido')),
              ],
            )
          else
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _statusFilter,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _statusFilter = value);
                },
                items: const [
                  DropdownMenuItem<String>(value: 'all', child: Text('Todos')),
                  DropdownMenuItem<String>(
                    value: 'draft',
                    child: Text('Borrador'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'published',
                    child: Text('Publicado'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'emitted',
                    child: Text('Emitido'),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openRecipeForm(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva receta'),
            )
          : null,
      body: StreamBuilder<List<Recipe>>(
        stream: _repo.watchRecipes(status: _effectiveStatusFilter),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final recipes = snapshot.data!;
          if (recipes.isEmpty) {
            return const Center(child: Text('Sin recetas cargadas.'));
          }

          return ResponsivePage(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: recipes.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final recipe = recipes[index];
                final normalizedStatus = recipe.status.trim().toLowerCase();
                final isEmitted = normalizedStatus == 'emitted';
                final isPublished = normalizedStatus == 'published';
                final emission = recipe.lastEmission;
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
                                recipe.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            _StatusChip(status: recipe.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (isEmitted) ...[
                          Text(
                            'Fecha de emisión: ${emission == null ? "No definida" : _formatDateTime(emission.issuedAt)}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Campo: ${emission?.farmName ?? "-"}    Lote: ${emission?.plotName ?? "-"}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fecha planificada: ${emission?.plannedDate == null ? "No definida" : _formatDateTime(emission!.plannedDate!)}',
                          ),
                        ] else ...[
                          Text('Cultivo: ${recipe.crop} - ${recipe.stage}'),
                          const SizedBox(height: 4),
                          Text('Objetivo: ${recipe.objective}'),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_canEdit && !isEmitted)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _openRecipeForm(recipe: recipe),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Editar'),
                              ),
                            if (_canEmit && isPublished)
                              FilledButton.icon(
                                onPressed: () => _openEmit(recipe),
                                icon: const Icon(Icons.send_outlined),
                                label: const Text('Emitir recetario'),
                              ),
                            if (isEmitted)
                              OutlinedButton.icon(
                                onPressed: () => _viewEmittedRecipe(recipe),
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text('Ver'),
                              ),
                            if (isEmitted)
                              OutlinedButton.icon(
                                onPressed: () => _viewRequiredProducts(recipe),
                                icon: const Icon(Icons.calculate_outlined),
                                label: const Text('Productos'),
                              ),
                            if (_canEmit && isEmitted)
                              Tooltip(
                                message: 'Volver a compartir PNG',
                                child: FilledButton(
                                  onPressed: _sharingRecipeId == recipe.id
                                      ? null
                                      : () => _reshareAsPng(recipe),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(46, 40),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                  ),
                                  child: _sharingRecipeId == recipe.id
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                          ),
                                        )
                                      : const Icon(Icons.share_outlined),
                                ),
                              ),
                          ],
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final isPublished = normalized == 'published';
    final isEmitted = normalized == 'emitted';
    return Chip(
      label: Text(
        isEmitted
            ? 'Emitido'
            : isPublished
            ? 'Publicado'
            : 'Borrador',
      ),
      backgroundColor: isEmitted
          ? Colors.blue.shade100
          : isPublished
          ? Colors.green.shade100
          : Colors.orange.shade100,
    );
  }
}
