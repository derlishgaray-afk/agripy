import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/router.dart';
import '../../../core/services/access_controller.dart';
import '../../../core/services/tenant_path.dart';
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
  final Map<String, Map<String, double>> _fieldLotAreaCache =
      <String, Map<String, double>>{};
  String _statusFilter = 'all';
  String _emittedStateFilter = 'all';
  String? _sharingRecipeId;

  @override
  void initState() {
    super.initState();
    if (_isOperator) {
      _statusFilter = 'emitted';
      _emittedStateFilter = 'pending';
    }
    _repo = RecetarioRepo(
      firestore: FirebaseFirestore.instance,
      tenantId: widget.session.tenantId,
      currentUid: widget.session.uid,
      access: widget.session.access,
    );
  }

  bool get _canEdit => widget.session.access.canEditRecetario;

  bool get _isOperator => widget.session.access.role == TenantRole.operator;

  bool get _canEmit {
    final role = widget.session.access.role;
    return role == TenantRole.admin || role == TenantRole.engineer;
  }

  bool get _canUpdateApplications => _canEmit || _isOperator;

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

  String? get _effectiveStatusFilter {
    if (_isOperator) {
      return 'emitted';
    }
    return _statusFilter == 'all' ? null : _statusFilter;
  }

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
    if (normalized == 'annulled' || normalized == 'anulado') {
      return 'Anulado';
    }
    if (normalized == 'completed' || normalized == 'completado') {
      return 'Completado';
    }
    if (normalized == 'emitted') {
      return 'Emitido';
    }
    if (normalized == 'published') {
      return 'Publicado';
    }
    return 'Borrador';
  }

  String _emittedStateFilterLabel(String value) {
    switch (value) {
      case 'pending':
        return 'Pendiente';
      case 'completed':
        return 'Completado';
      case 'annulled':
        return 'Anulado';
      default:
        return 'Todos';
    }
  }

  String _statusFilterLabel(String value) {
    switch (value) {
      case 'draft':
        return 'Borrador';
      case 'published':
        return 'Publicado';
      case 'emitted':
        return 'Emitido';
      default:
        return 'Todos';
    }
  }

  bool get _showFilterSummary {
    if (_isOperator) {
      return true;
    }
    return _statusFilter != 'all';
  }

  String get _activeFilterSummary {
    final statusLabel = _isOperator
        ? 'Emitido'
        : _statusFilterLabel(_statusFilter);
    if (_isOperator || _statusFilter == 'emitted') {
      return '$statusLabel - ${_emittedStateFilterLabel(_emittedStateFilter)}';
    }
    return statusLabel;
  }

  String _orderStateKey(ApplicationOrder? order) {
    if (order == null) {
      return 'pending';
    }
    final raw = order.status.trim().toLowerCase();
    if (raw == 'annulled' || raw == 'anulado' || raw == 'cancelled') {
      return 'annulled';
    }
    if (raw == 'completed' || order.execution.done) {
      return 'completed';
    }
    return 'pending';
  }

  String _orderStateLabel(ApplicationOrder? order) {
    final key = _orderStateKey(order);
    if (key == 'completed') {
      return 'Completado';
    }
    if (key == 'annulled') {
      return 'Anulado';
    }
    return 'Emitido';
  }

  bool _orderBelongsToCurrentOperator(ApplicationOrder order) {
    final assignedUid = order.assignedToUid.trim();
    if (assignedUid.isNotEmpty && assignedUid == widget.session.uid) {
      return true;
    }
    if (!_isOperator) {
      return false;
    }
    final operatorName = _normalizeOperatorName(order.operatorName);
    final currentName = _normalizeOperatorName(
      widget.session.access.displayName,
    );
    return operatorName.isNotEmpty && operatorName == currentName;
  }

  String _normalizeOperatorName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  List<String> _splitUniquePlots(String raw) {
    final cleanedRaw = raw.trim();
    if (cleanedRaw.isEmpty) {
      return const ['Sin lote'];
    }
    final tokens = <String>{};
    for (final part in cleanedRaw.split(RegExp(r'[,;|/]+'))) {
      final token = part.trim();
      if (token.isNotEmpty) {
        tokens.add(token);
      }
    }
    if (tokens.isEmpty) {
      return const ['Sin lote'];
    }
    return tokens.toList(growable: false);
  }

  String _normalizePlotKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<Map<String, double>> _loadFieldLotAreasForFarm(String farmName) async {
    final farmKey = _normalizePlotKey(farmName);
    if (farmKey.isEmpty) {
      return const <String, double>{};
    }
    final cached = _fieldLotAreaCache[farmKey];
    if (cached != null) {
      return cached;
    }

    final result = <String, double>{};
    try {
      final snapshot = await TenantPath.fieldsRef(
        FirebaseFirestore.instance,
        widget.session.tenantId,
      ).get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = _normalizePlotKey((data['name'] as String? ?? ''));
        if (name != farmKey) {
          continue;
        }
        final lotsRaw = data['lots'];
        if (lotsRaw is! List) {
          continue;
        }
        for (final item in lotsRaw) {
          if (item is! Map) {
            continue;
          }
          final lotName = _normalizePlotKey(item['name'] as String? ?? '');
          if (lotName.isEmpty) {
            continue;
          }
          final area = parseFlexibleDouble(item['areaHa']);
          if (area > 0) {
            result[lotName] = area;
          }
        }
        break;
      }
    } catch (_) {}

    final immutable = Map<String, double>.unmodifiable(result);
    _fieldLotAreaCache[farmKey] = immutable;
    return immutable;
  }

  Future<Map<String, double>> _resolveOrderPlotAreas(ApplicationOrder order) async {
    final plots = _splitUniquePlots(order.plotName);
    final knownByField = await _loadFieldLotAreasForFarm(order.farmName);
    final result = <String, double>{};
    var knownTotal = 0.0;
    final unresolved = <String>[];

    for (final plot in plots) {
      final key = _normalizePlotKey(plot);
      final area = knownByField[key] ?? 0;
      if (area > 0) {
        result[plot] = area;
        knownTotal += area;
      } else {
        unresolved.add(plot);
      }
    }

    if (unresolved.isNotEmpty) {
      final baseArea = order.areaHa > 0
          ? order.areaHa
          : (order.affectedAreaHa > 0 ? order.affectedAreaHa : plots.length.toDouble());
      final remaining = (baseArea - knownTotal).clamp(0, baseArea).toDouble();
      final fallbackArea = remaining > 0
          ? remaining / unresolved.length
          : (baseArea / plots.length);
      for (final plot in unresolved) {
        result[plot] = fallbackArea;
      }
    }

    return Map<String, double>.unmodifiable(result);
  }

  double _appliedEntryTankEquivalent(
    TankApplicationEntry entry,
    ApplicationOrder order,
  ) {
    if (entry.appliedTankEquivalent > 0) {
      return entry.appliedTankEquivalent;
    }
    if (entry.appliedVolumeLt > 0 && order.tankCapacityLt > 0) {
      return entry.appliedVolumeLt / order.tankCapacityLt;
    }
    if (entry.tankCapacityLt > 0 && order.tankCapacityLt > 0) {
      return entry.tankCount * (entry.tankCapacityLt / order.tankCapacityLt);
    }
    return entry.tankCount;
  }

  double _selectedPlotsAreaHa(
    Set<String> selectedPlots,
    Map<String, double> plotAreaByName,
  ) {
    var total = 0.0;
    for (final plot in selectedPlots) {
      total += plotAreaByName[plot] ?? 0;
    }
    return total;
  }

  double _selectedPlotsPendingTankCount({
    required ApplicationOrder order,
    required List<String> allPlots,
    required Set<String> selectedPlots,
    required Map<String, double> plotAreaByName,
  }) {
    if (allPlots.isEmpty || selectedPlots.isEmpty) {
      return 0;
    }
    final totalArea = _selectedPlotsAreaHa(allPlots.toSet(), plotAreaByName);
    if (totalArea <= 0 || order.tankCount <= 0) {
      return 0;
    }
    final selectedArea = _selectedPlotsAreaHa(selectedPlots, plotAreaByName);
    if (selectedArea <= 0) {
      return 0;
    }
    final selectedShare = (selectedArea / totalArea).clamp(0, 1).toDouble();
    final selectedPlannedTanks = order.tankCount * selectedShare;

    final selectedKeys = selectedPlots.map(_normalizePlotKey).toSet();
    final orderPlotKeys = allPlots.map(_normalizePlotKey).toList(growable: false);
    var selectedAppliedTanks = 0.0;
    for (final entry in order.execution.tankApplications) {
      final entryPlots = _splitUniquePlots(entry.plotName)
          .map(_normalizePlotKey)
          .where((value) => value.isNotEmpty)
          .toSet();
      final effectiveEntryPlots = entryPlots.isEmpty
          ? orderPlotKeys.toSet()
          : entryPlots;
      if (effectiveEntryPlots.isEmpty) {
        continue;
      }
      var selectedIntersection = 0;
      for (final key in effectiveEntryPlots) {
        if (selectedKeys.contains(key)) {
          selectedIntersection += 1;
        }
      }
      if (selectedIntersection <= 0) {
        continue;
      }
      final equivalent = _appliedEntryTankEquivalent(entry, order);
      selectedAppliedTanks +=
          equivalent * (selectedIntersection / effectiveEntryPlots.length);
    }

    final pending = selectedPlannedTanks - selectedAppliedTanks;
    if (pending <= 0) {
      return 0;
    }
    return pending;
  }

  double _plannedTankCount(ApplicationOrder? order) {
    if (order == null || order.tankCount <= 0) {
      return 0;
    }
    return order.tankCount;
  }

  double _appliedTankCount(ApplicationOrder? order) {
    if (order == null) {
      return 0;
    }
    final planned = _plannedTankCount(order);
    final applied = order.execution.appliedTankCount;
    if (applied > 0) {
      if (planned <= 0) {
        return applied;
      }
      return applied.clamp(0, planned).toDouble();
    }
    if (_orderStateKey(order) == 'completed') {
      return planned;
    }
    return 0;
  }

  double _pendingTankCount(ApplicationOrder? order) {
    final planned = _plannedTankCount(order);
    if (planned <= 0) {
      return 0;
    }
    final pending = planned - _appliedTankCount(order);
    if (pending <= 0) {
      return 0;
    }
    return pending;
  }

  String _orderStateDetail(ApplicationOrder? order) {
    final key = _orderStateKey(order);
    final planned = _plannedTankCount(order);
    final applied = _appliedTankCount(order);
    final pending = _pendingTankCount(order);
    final hasProgress = planned > 0;
    final progressText = hasProgress
        ? ' | Tanques ${applied.toStringAsFixed(2)}/${planned.toStringAsFixed(2)}'
              ' (pendiente ${pending.toStringAsFixed(2)})'
        : '';
    if (key == 'completed') {
      final doneAt = order?.execution.doneAt;
      if (doneAt == null) {
        return 'Actualizacion: Completado$progressText';
      }
      return 'Actualizacion: Completado el ${_formatDateTime(doneAt)}$progressText';
    }
    if (key == 'annulled') {
      return 'Actualizacion: Anulado';
    }
    return 'Actualizacion: Pendiente$progressText';
  }

  Future<DateTime?> _pickDateTime({DateTime? initialDateTime}) async {
    final now = DateTime.now();
    final initial = initialDateTime ?? now;
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 3),
      initialDate: initial,
    );
    if (pickedDate == null || !mounted) {
      return null;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) {
      return null;
    }
    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<_TankApplicationInput?> _collectTankApplicationInput({
    required ApplicationOrder order,
  }) async {
    final formKey = GlobalKey<FormState>();
    final tankCountController = TextEditingController();
    final tankCapacityController = TextEditingController(
      text: _formatTankCapacityInt(order.tankCapacityLt),
    );
    var appliedAt = DateTime.now();
    final availablePlots = _splitUniquePlots(order.plotName);
    final plotAreaByName = await _resolveOrderPlotAreas(order);
    if (!mounted) {
      return null;
    }
    var selectedPlots = availablePlots.toSet();
    var selectedPending = _selectedPlotsPendingTankCount(
      order: order,
      allPlots: availablePlots,
      selectedPlots: selectedPlots,
      plotAreaByName: plotAreaByName,
    );
    if (selectedPending > 0) {
      tankCountController.text = selectedPending.toStringAsFixed(2);
    }

    final result = await showDialog<_TankApplicationInput>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedAreaHa = _selectedPlotsAreaHa(
              selectedPlots,
              plotAreaByName,
            );
            selectedPending = _selectedPlotsPendingTankCount(
              order: order,
              allPlots: availablePlots,
              selectedPlots: selectedPlots,
              plotAreaByName: plotAreaByName,
            );
            return AlertDialog(
              title: const Text('Registrar aplicacion por tanque'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FormField<Set<String>>(
                      initialValue: selectedPlots,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Selecciona al menos un lote aplicado.';
                        }
                        return null;
                      },
                      builder: (fieldState) {
                        return InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Lote(s) aplicado(s)',
                            border: const OutlineInputBorder(),
                            errorText: fieldState.errorText,
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: availablePlots.map((plot) {
                              return FilterChip(
                                label: Text(plot),
                                selected: selectedPlots.contains(plot),
                                onSelected: (checked) {
                                  setDialogState(() {
                                    if (checked) {
                                      selectedPlots.add(plot);
                                    } else {
                                      selectedPlots.remove(plot);
                                    }
                                    fieldState.didChange(
                                      selectedPlots.toSet(),
                                    );
                                    final suggested =
                                        _selectedPlotsPendingTankCount(
                                          order: order,
                                          allPlots: availablePlots,
                                          selectedPlots: selectedPlots,
                                          plotAreaByName: plotAreaByName,
                                        );
                                    tankCountController.text = suggested > 0
                                        ? suggested.toStringAsFixed(2)
                                        : '';
                                  });
                                },
                              );
                            }).toList(growable: false),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Superficie seleccionada: ${selectedAreaHa.toStringAsFixed(2)} ha',
                    ),
                    Text(
                      'Tanques pendientes (lotes seleccionados): ${selectedPending.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: tankCountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad de tanques aplicados',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (selectedPlots.isEmpty) {
                          return 'Selecciona al menos un lote aplicado.';
                        }
                        final number = parseFlexibleDouble(value?.trim());
                        if (number <= 0) {
                          return 'Ingresa una cantidad mayor a cero.';
                        }
                        final capacity = _parseTankCapacityInt(
                          tankCapacityController.text,
                        );
                        if (capacity > 0 && order.tankCapacityLt > 0) {
                          final equivalent =
                              number * (capacity / order.tankCapacityLt);
                          if (equivalent > selectedPending + 0.000001) {
                            return 'Excede los tanques pendientes (${selectedPending.toStringAsFixed(2)}).';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: tankCapacityController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        const _ThousandsIntInputFormatter(),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Capacidad del tanque (Lt)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (selectedPlots.isEmpty) {
                          return 'Selecciona al menos un lote aplicado.';
                        }
                        final number = _parseTankCapacityInt(value);
                        if (number <= 0) {
                          return 'Ingresa una capacidad valida.';
                        }
                        final tankCount = parseFlexibleDouble(
                          tankCountController.text.trim(),
                        );
                        if (tankCount > 0 && order.tankCapacityLt > 0) {
                          final equivalent =
                              tankCount * (number / order.tankCapacityLt);
                          if (equivalent > selectedPending + 0.000001) {
                            return 'Excede los tanques pendientes (${selectedPending.toStringAsFixed(2)}).';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await _pickDateTime(
                          initialDateTime: appliedAt,
                        );
                        if (picked == null || !mounted) {
                          return;
                        }
                        if (!dialogContext.mounted) {
                          return;
                        }
                        setDialogState(() {
                          appliedAt = picked;
                        });
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        'Fecha y hora: ${_formatDateTime(appliedAt)}',
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
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) {
                      return;
                    }
                    final orderedSelection = availablePlots
                        .where((plot) => selectedPlots.contains(plot))
                        .toList(growable: false);
                    if (orderedSelection.isEmpty) {
                      return;
                    }
                    final tankCount = parseFlexibleDouble(
                      tankCountController.text.trim(),
                    );
                    final tankCapacity = _parseTankCapacityInt(
                      tankCapacityController.text,
                    );
                    Navigator.of(dialogContext).pop(
                      _TankApplicationInput(
                        appliedAt: appliedAt,
                        tankCount: tankCount,
                        tankCapacityLt: tankCapacity,
                        plotName: orderedSelection.join(', '),
                      ),
                    );
                  },
                  child: const Text('Registrar'),
                ),
              ],
            );
          },
        );
      },
    );

    return result;
  }

  Future<void> _showEmissionUpdateDialog({
    required Recipe recipe,
    required ApplicationOrder order,
  }) async {
    if (_isOperator && !_orderBelongsToCurrentOperator(order)) {
      _showSnack('Solo puedes actualizar emitidos asignados a tu usuario.');
      return;
    }
    final orderId = order.id;
    if (orderId == null || orderId.isEmpty) {
      _showSnack('No se pudo actualizar: orden sin identificador.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var submitting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final plannedTankCount = _plannedTankCount(order);
            final appliedTankCount = _appliedTankCount(order);
            final pendingTankCount = _pendingTankCount(order);
            final isAnnulled = _orderStateKey(order) == 'annulled';
            final canManageOrder = _canEmit;
            final canRegisterProgress =
                _canUpdateApplications && !isAnnulled && pendingTankCount > 0;
            return AlertDialog(
              title: const Text('Actualizacion de emitido'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recetario: ${recipe.title}\nCodigo: ${order.code}\nEstado actual: ${_orderStateLabel(order)}',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Volumen de agua: ${recipe.waterVolumeLHa.toStringAsFixed(2)} L/ha',
                  ),
                  Text(
                    'Tanques total previsto: ${plannedTankCount.toStringAsFixed(2)}',
                  ),
                  Text(
                    'Tanques realizado: ${appliedTankCount.toStringAsFixed(2)}',
                  ),
                  Text(
                    'Tanques pendiente: ${pendingTankCount.toStringAsFixed(2)}',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cerrar'),
                ),
                OutlinedButton(
                  onPressed: submitting || !canRegisterProgress
                      ? null
                      : () async {
                          final input = await _collectTankApplicationInput(
                            order: order,
                          );
                          if (input == null) {
                            return;
                          }
                          setDialogState(() {
                            submitting = true;
                          });
                          try {
                            await _repo.registerOrderTankApplication(
                              orderId: orderId,
                              appliedAt: input.appliedAt,
                              appliedTankCount: input.tankCount,
                              tankCapacityLt: input.tankCapacityLt,
                              plotName: input.plotName,
                            );
                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            _showSnack(
                              'Aplicacion registrada: ${input.tankCount.toStringAsFixed(2)} tanque(s) '
                              'de ${_formatTankCapacityInt(input.tankCapacityLt)} Lt en lote(s) ${input.plotName}.',
                            );
                          } catch (error) {
                            if (!mounted) {
                              return;
                            }
                            _showSnack(
                              'No se pudo actualizar: ${_friendlyUpdateError(error)}',
                            );
                            setDialogState(() {
                              submitting = false;
                            });
                          }
                        },
                  child: const Text('Registrar aplicacion'),
                ),
                if (canManageOrder && !isAnnulled)
                  FilledButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  title: const Text('Anular emitido'),
                                  content: const Text(
                                    'Esta accion marcara el emitido como anulado.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Anular'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (confirm != true) {
                              return;
                            }
                            setDialogState(() {
                              submitting = true;
                            });
                            try {
                              await _repo.markOrderAnnulled(orderId: orderId);
                              if (!mounted || !dialogContext.mounted) {
                                return;
                              }
                              Navigator.of(dialogContext).pop();
                              _showSnack('Emitido actualizado a anulado.');
                            } catch (error) {
                              if (!mounted) {
                                return;
                              }
                              _showSnack('No se pudo anular: $error');
                              setDialogState(() {
                                submitting = false;
                              });
                            }
                          },
                    child: const Text('Anular'),
                  )
                else if (canManageOrder)
                  FilledButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            final recipeId = recipe.id;
                            if (recipeId == null || recipeId.trim().isEmpty) {
                              _showSnack(
                                'No se puede eliminar: receta emitida sin id.',
                              );
                              return;
                            }
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  title: const Text('Eliminar emitido anulado'),
                                  content: const Text(
                                    'Se eliminara la orden anulada y el recetario emitido asociado.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Eliminar'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (confirm != true) {
                              return;
                            }
                            setDialogState(() {
                              submitting = true;
                            });
                            try {
                              await _repo.deleteAnnulledOrderAndRecipe(
                                orderId: orderId,
                                recipeId: recipeId,
                              );
                              if (!mounted || !dialogContext.mounted) {
                                return;
                              }
                              Navigator.of(dialogContext).pop();
                              _showSnack('Emitido anulado eliminado.');
                            } catch (error) {
                              if (!mounted) {
                                return;
                              }
                              _showSnack('No se pudo eliminar: $error');
                              setDialogState(() {
                                submitting = false;
                              });
                            }
                          },
                    child: const Text('Eliminar'),
                  ),
              ],
            );
          },
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

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _friendlyUpdateError(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Permiso denegado por reglas de seguridad.';
      }
      if (error.code == 'unavailable') {
        return 'Servicio no disponible temporalmente. Intenta de nuevo.';
      }
      return error.message ?? 'Error de Firebase.';
    }
    if (error is StateError) {
      return error.message;
    }
    final raw = error.toString();
    if (raw.contains('TimeoutException')) {
      return 'Tiempo de espera agotado al guardar. Reintenta con buena conexion.';
    }
    return raw;
  }

  String _formatTankCapacityInt(num value) {
    final asInt = value.round();
    final digits = asInt.toString();
    return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  }

  double _parseTankCapacityInt(String? value) {
    final digitsOnly = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return 0;
    }
    return double.tryParse(digitsOnly) ?? 0;
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
        bottom: _showFilterSummary
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Filtro: $_activeFilterSummary',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          if (!_isOperator)
            if (compact)
              PopupMenuButton<String>(
                tooltip: 'Filtrar estado',
                initialValue: _statusFilter,
                icon: const Icon(Icons.filter_list),
                onSelected: (value) => setState(() => _statusFilter = value),
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(value: 'all', child: Text('Todos')),
                  PopupMenuItem<String>(
                    value: 'draft',
                    child: Text('Borrador'),
                  ),
                  PopupMenuItem<String>(
                    value: 'published',
                    child: Text('Publicado'),
                  ),
                  PopupMenuItem<String>(
                    value: 'emitted',
                    child: Text('Emitido'),
                  ),
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
                    DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('Todos'),
                    ),
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
          if (_statusFilter == 'emitted' || _isOperator)
            if (compact)
              PopupMenuButton<String>(
                tooltip:
                    'Filtrar emitidos: ${_emittedStateFilterLabel(_emittedStateFilter)}',
                initialValue: _emittedStateFilter,
                icon: const Icon(Icons.fact_check_outlined),
                onSelected: (value) =>
                    setState(() => _emittedStateFilter = value),
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: 'all',
                    child: Text('Todos'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'pending',
                    child: Text('Pendiente'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'completed',
                    child: Text('Completado'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'annulled',
                    child: Text('Anulado'),
                  ),
                ],
              )
            else
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _emittedStateFilter,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _emittedStateFilter = value);
                  },
                  items: const [
                    DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('Todos'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'pending',
                      child: Text('Pendiente'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'completed',
                      child: Text('Completado'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'annulled',
                      child: Text('Anulado'),
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
            return Center(
              child: Text(
                _isOperator
                    ? 'Sin emitidos asignados a este operador.'
                    : 'Sin recetas cargadas.',
              ),
            );
          }

          return StreamBuilder<List<ApplicationOrder>>(
            stream: _repo.watchApplicationOrders(),
            builder: (context, ordersSnapshot) {
              if (ordersSnapshot.hasError) {
                return Center(child: Text('Error: ${ordersSnapshot.error}'));
              }
              final orderByRecipeId = <String, ApplicationOrder>{};
              if (ordersSnapshot.hasData) {
                for (final order in ordersSnapshot.data!) {
                  if (_isOperator && !_orderBelongsToCurrentOperator(order)) {
                    continue;
                  }
                  final recipeId = order.recipeId.trim();
                  if (recipeId.isEmpty ||
                      orderByRecipeId.containsKey(recipeId)) {
                    continue;
                  }
                  orderByRecipeId[recipeId] = order;
                }
              }
              var filteredRecipes = recipes;
              if (_isOperator) {
                filteredRecipes = recipes
                    .where((recipe) {
                      final recipeId = recipe.id;
                      if (recipeId == null || recipeId.isEmpty) {
                        return false;
                      }
                      return orderByRecipeId.containsKey(recipeId);
                    })
                    .toList(growable: false);
              }
              if ((_statusFilter == 'emitted' || _isOperator) &&
                  _emittedStateFilter != 'all') {
                filteredRecipes = filteredRecipes
                    .where((recipe) {
                      final recipeId = recipe.id;
                      if (recipeId == null || recipeId.isEmpty) {
                        return false;
                      }
                      final order = orderByRecipeId[recipeId];
                      return _orderStateKey(order) == _emittedStateFilter;
                    })
                    .toList(growable: false);
              }
              if (filteredRecipes.isEmpty) {
                if (_isOperator) {
                  final suffix = _emittedStateFilter == 'all'
                      ? ''
                      : ' en estado ${_emittedStateFilterLabel(_emittedStateFilter).toLowerCase()}';
                  return Center(child: Text('Sin emitidos asignados$suffix.'));
                }
                if (_effectiveStatusFilter == 'emitted') {
                  return Center(
                    child: Text(
                      'Sin emitidos en estado ${_emittedStateFilterLabel(_emittedStateFilter).toLowerCase()}.',
                    ),
                  );
                }
                if (_effectiveStatusFilter == 'published') {
                  return const Center(
                    child: Text('Sin recetarios publicados.'),
                  );
                }
                if (_effectiveStatusFilter == 'draft') {
                  return const Center(
                    child: Text('Sin recetarios en borrador.'),
                  );
                }
                return Center(child: const Text('Sin recetas cargadas.'));
              }
              return ResponsivePage(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: filteredRecipes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final recipe = filteredRecipes[index];
                    final normalizedStatus = recipe.status.trim().toLowerCase();
                    final isEmitted = normalizedStatus == 'emitted';
                    final isPublished = normalizedStatus == 'published';
                    final emission = recipe.lastEmission;
                    final order = isEmitted && recipe.id != null
                        ? orderByRecipeId[recipe.id!]
                        : null;
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                _StatusChip(
                                  status: isEmitted
                                      ? _orderStateLabel(order)
                                      : _statusLabel(recipe.status),
                                ),
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
                              const SizedBox(height: 4),
                              Text(_orderStateDetail(order)),
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
                                    onPressed: () =>
                                        _viewRequiredProducts(recipe),
                                    icon: const Icon(Icons.calculate_outlined),
                                    label: const Text('Productos'),
                                  ),
                                if (_canUpdateApplications &&
                                    isEmitted &&
                                    order != null &&
                                    (!_isOperator ||
                                        _orderBelongsToCurrentOperator(order)))
                                  OutlinedButton.icon(
                                    onPressed: () => _showEmissionUpdateDialog(
                                      recipe: recipe,
                                      order: order,
                                    ),
                                    icon: const Icon(Icons.event_note_outlined),
                                    label: const Text('Actualizar'),
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
          );
        },
      ),
    );
  }
}

class _TankApplicationInput {
  const _TankApplicationInput({
    required this.appliedAt,
    required this.tankCount,
    required this.tankCapacityLt,
    required this.plotName,
  });

  final DateTime appliedAt;
  final double tankCount;
  final double tankCapacityLt;
  final String plotName;
}

class _ThousandsIntInputFormatter extends TextInputFormatter {
  const _ThousandsIntInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final formatted = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final normalized = status.trim().toLowerCase();
    final isAnnulled =
        normalized == 'annulled' ||
        normalized == 'anulado' ||
        normalized == 'cancelled';
    final isCompleted = normalized == 'completed' || normalized == 'completado';
    final isPublished = normalized == 'published' || normalized == 'publicado';
    final isEmitted = normalized == 'emitted' || normalized == 'emitido';
    final backgroundColor = isAnnulled
        ? colorScheme.errorContainer
        : isCompleted
        ? colorScheme.tertiaryContainer
        : isEmitted
        ? colorScheme.secondaryContainer
        : isPublished
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHigh;
    final foregroundColor = isAnnulled
        ? colorScheme.onErrorContainer
        : isCompleted
        ? colorScheme.onTertiaryContainer
        : isEmitted
        ? colorScheme.onSecondaryContainer
        : isPublished
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    return Chip(
      label: Text(
        isAnnulled
            ? 'Anulado'
            : isCompleted
            ? 'Completado'
            : isEmitted
            ? 'Emitido'
            : isPublished
            ? 'Publicado'
            : 'Borrador',
        style: TextStyle(color: foregroundColor, fontWeight: FontWeight.w600),
      ),
      backgroundColor: backgroundColor,
      side: BorderSide.none,
    );
  }
}
