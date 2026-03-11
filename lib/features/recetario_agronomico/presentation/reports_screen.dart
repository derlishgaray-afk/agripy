import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/services/access_controller.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/recetario_repo.dart';
import '../domain/models.dart';
import '../services/recetario_share.dart';
import '../services/reports_export_service.dart';

enum _ReportPeriodPreset { all, today, last7Days, last30Days, custom }

enum _ExecutionStatusFilter { all, pending, completed }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final RecetarioRepo _repo;
  late final ReportsExportService _exportService;
  late final RecetarioShareService _shareService;
  StreamSubscription<List<Recipe>>? _emittedRecipesSub;

  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat _dayFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _fileStampFormat = DateFormat('yyyyMMdd_HHmm');

  _ReportPeriodPreset _periodPreset = _ReportPeriodPreset.last30Days;
  DateTime? _customFrom;
  DateTime? _customTo;
  String? _selectedField;
  Set<String> _selectedPlots = <String>{};
  String? _selectedOperator;
  String? _selectedResponsible;
  _ExecutionStatusFilter _executionStatusFilter = _ExecutionStatusFilter.all;
  bool _exportingExcel = false;
  bool _exportingPdf = false;
  bool _loadingEmittedRecipes = true;
  List<Recipe> _emittedRecipes = const [];

  bool get _isSecondaryUser {
    return widget.session.uid.trim() != widget.session.tenantId.trim() &&
        widget.session.access.role == TenantRole.operator;
  }

  String _normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isOrderFromCurrentUserActivity(ApplicationOrder order) {
    final uid = widget.session.uid.trim();
    final currentName = _normalizeName(widget.session.access.displayName);
    if (uid.isEmpty) {
      return false;
    }
    if (order.assignedToUid.trim() == uid) {
      return true;
    }
    if ((order.execution.operatorUid ?? '').trim() == uid) {
      return true;
    }
    for (final entry in order.execution.tankApplications) {
      if (entry.operatorUid.trim() == uid) {
        return true;
      }
    }
    if (currentName.isNotEmpty) {
      final operatorName = _normalizeName(order.operatorName);
      final engineerName = _normalizeName(order.engineerName);
      if (operatorName == currentName || engineerName == currentName) {
        return true;
      }
    }
    return false;
  }

  List<ApplicationOrder> _ordersVisibleForCurrentUser(
    List<ApplicationOrder> orders,
  ) {
    if (!_isSecondaryUser) {
      return orders;
    }
    return orders
        .where(_isOrderFromCurrentUserActivity)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _repo = RecetarioRepo(
      firestore: FirebaseFirestore.instance,
      tenantId: widget.session.tenantId,
      currentUid: widget.session.uid,
      access: widget.session.access,
    );
    _exportService = ReportsExportService();
    _shareService = RecetarioShareService();
    _emittedRecipesSub = _repo
        .watchRecipes(status: 'emitted')
        .listen(
          (items) {
            if (!mounted) {
              return;
            }
            setState(() {
              _emittedRecipes = items;
              _loadingEmittedRecipes = false;
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _loadingEmittedRecipes = false;
            });
          },
        );
  }

  @override
  void dispose() {
    _emittedRecipesSub?.cancel();
    super.dispose();
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  String _cleanLabel(String value, {required String fallback}) {
    final cleaned = value.trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  List<String> _splitUniquePlots(String raw) {
    final cleanedRaw = raw.trim();
    if (cleanedRaw.isEmpty) {
      return const ['Sin lote'];
    }
    final tokens = <String>{};
    for (final part in cleanedRaw.split(RegExp(r'[,;|/]+'))) {
      final token = part.trim();
      if (token.isEmpty) {
        continue;
      }
      tokens.add(token);
    }
    if (tokens.isEmpty) {
      return const ['Sin lote'];
    }
    return tokens.toList(growable: false);
  }

  bool _matchesSelectedPlots(
    ApplicationOrder order,
    Set<String> selectedPlots,
  ) {
    if (selectedPlots.isEmpty) {
      return true;
    }
    final selected = selectedPlots
        .map((value) => value.trim().toLowerCase())
        .toSet();
    for (final plot in _splitUniquePlots(order.plotName)) {
      if (selected.contains(plot.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  String _normalizedExecutionStatus(ApplicationOrder order) {
    if (order.execution.done ||
        order.status.trim().toLowerCase() == 'completed') {
      return 'completed';
    }
    return 'pending';
  }

  String _executionStatusText(ApplicationOrder order) {
    return _normalizedExecutionStatus(order) == 'completed'
        ? 'Completado'
        : 'Pendiente';
  }

  String _executionStatusFilterText(_ExecutionStatusFilter value) {
    switch (value) {
      case _ExecutionStatusFilter.all:
        return 'Todos';
      case _ExecutionStatusFilter.pending:
        return 'Pendientes';
      case _ExecutionStatusFilter.completed:
        return 'Completados';
    }
  }

  String _periodText() {
    switch (_periodPreset) {
      case _ReportPeriodPreset.today:
        return 'Hoy';
      case _ReportPeriodPreset.last7Days:
        return 'Ultimos 7 dias';
      case _ReportPeriodPreset.last30Days:
        return 'Ultimos 30 dias';
      case _ReportPeriodPreset.all:
        return 'Todo';
      case _ReportPeriodPreset.custom:
        final fromText = _customFrom == null
            ? '-'
            : _dayFormat.format(_customFrom!);
        final toText = _customTo == null ? '-' : _dayFormat.format(_customTo!);
        return 'Personalizado ($fromText a $toText)';
    }
  }

  String _activeFiltersSummary({
    required String? selectedField,
    required Set<String> selectedPlots,
    required String? selectedOperator,
    required String? selectedResponsible,
  }) {
    final parts = <String>[
      'Periodo: ${_periodText()}',
      'Campo: ${selectedField ?? "Todos"}',
      'Lotes: ${selectedPlots.isEmpty ? "Todos" : selectedPlots.join(" | ")}',
      'Operador: ${selectedOperator ?? "Todos"}',
      'Responsable: ${selectedResponsible ?? "Todos"}',
      'Estado: ${_executionStatusFilterText(_executionStatusFilter)}',
    ];
    return parts.join(' | ');
  }

  bool _withinPeriod(DateTime issuedAt) {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;
    switch (_periodPreset) {
      case _ReportPeriodPreset.all:
        from = null;
        to = null;
        break;
      case _ReportPeriodPreset.today:
        from = _startOfDay(now);
        to = _endOfDay(now);
        break;
      case _ReportPeriodPreset.last7Days:
        from = _startOfDay(now.subtract(const Duration(days: 6)));
        to = _endOfDay(now);
        break;
      case _ReportPeriodPreset.last30Days:
        from = _startOfDay(now.subtract(const Duration(days: 29)));
        to = _endOfDay(now);
        break;
      case _ReportPeriodPreset.custom:
        from = _customFrom;
        to = _customTo;
        break;
    }
    if (from != null && issuedAt.isBefore(from)) {
      return false;
    }
    if (to != null && issuedAt.isAfter(to)) {
      return false;
    }
    return true;
  }

  List<ApplicationOrder> _applyLocationFilters(
    List<ApplicationOrder> orders, {
    required String? selectedField,
    required Set<String> selectedPlots,
  }) {
    return orders
        .where((order) {
          if (!_withinPeriod(order.issuedAt)) {
            return false;
          }
          final farmName = _cleanLabel(order.farmName, fallback: 'Sin campo');
          if (selectedField != null && selectedField != farmName) {
            return false;
          }
          if (!_matchesSelectedPlots(order, selectedPlots)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  List<ApplicationOrder> _applyFinalFilters(
    List<ApplicationOrder> orders, {
    required String? selectedOperator,
    required String? selectedResponsible,
  }) {
    return orders
        .where((order) {
          final operator = _cleanLabel(
            order.operatorName,
            fallback: 'Sin operador',
          );
          final responsible = _cleanLabel(
            order.engineerName,
            fallback: 'Sin responsable',
          );
          if (selectedOperator != null && selectedOperator != operator) {
            return false;
          }
          if (selectedResponsible != null &&
              selectedResponsible != responsible) {
            return false;
          }
          final status = _normalizedExecutionStatus(order);
          if (_executionStatusFilter == _ExecutionStatusFilter.pending &&
              status != 'pending') {
            return false;
          }
          if (_executionStatusFilter == _ExecutionStatusFilter.completed &&
              status != 'completed') {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  List<String> _collectFieldNames(List<ApplicationOrder> orders) {
    final result = <String>{};
    for (final order in orders) {
      result.add(_cleanLabel(order.farmName, fallback: 'Sin campo'));
    }
    final sorted = result.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  List<String> _collectPlotNames(
    List<ApplicationOrder> orders, {
    String? selectedField,
  }) {
    final result = <String>{};
    for (final order in orders) {
      final field = _cleanLabel(order.farmName, fallback: 'Sin campo');
      if (selectedField != null && selectedField != field) {
        continue;
      }
      result.addAll(_splitUniquePlots(order.plotName));
    }
    final sorted = result.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  List<String> _collectOperatorNames(List<ApplicationOrder> orders) {
    final result = <String>{};
    for (final order in orders) {
      result.add(_cleanLabel(order.operatorName, fallback: 'Sin operador'));
    }
    final sorted = result.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  List<String> _collectResponsibleNames(List<ApplicationOrder> orders) {
    final result = <String>{};
    for (final order in orders) {
      result.add(_cleanLabel(order.engineerName, fallback: 'Sin responsable'));
    }
    final sorted = result.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  Future<void> _pickCustomFrom() async {
    final now = DateTime.now();
    final initialDate = _customFrom ?? _startOfDay(now);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      initialDate: initialDate,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _periodPreset = _ReportPeriodPreset.custom;
      _customFrom = _startOfDay(picked);
      if (_customTo != null && _customTo!.isBefore(_customFrom!)) {
        _customTo = _endOfDay(_customFrom!);
      }
    });
  }

  Future<void> _pickCustomTo() async {
    final now = DateTime.now();
    final initialDate = _customTo ?? _endOfDay(now);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      initialDate: initialDate,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _periodPreset = _ReportPeriodPreset.custom;
      _customTo = _endOfDay(picked);
      if (_customFrom != null && _customTo!.isBefore(_customFrom!)) {
        _customFrom = _startOfDay(_customTo!);
      }
    });
  }

  Future<void> _pickPlots(List<String> availablePlots) async {
    if (availablePlots.isEmpty) {
      return;
    }
    final preselected = _selectedPlots.intersection(availablePlots.toSet());
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        final selected = preselected.toSet();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filtrar por lote(s)'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selected.length == availablePlots.length,
                        title: const Text('Seleccionar todos'),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selected
                                ..clear()
                                ..addAll(availablePlots);
                            } else {
                              selected.clear();
                            }
                          });
                        },
                      ),
                      const Divider(height: 8),
                      ...availablePlots.map((plot) {
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(plot),
                          title: Text(plot),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selected.add(plot);
                              } else {
                                selected.remove(plot);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(<String>{}),
                  child: const Text('Limpiar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(selected),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _selectedPlots = result;
    });
  }

  Future<void> _exportExcel({
    required List<ReportProductItem> items,
    required String filtersSummary,
  }) async {
    if (items.isEmpty || _exportingExcel || _exportingPdf) {
      return;
    }
    final now = DateTime.now();
    setState(() {
      _exportingExcel = true;
    });
    try {
      final excel = _exportService.buildExcel(
        tenantName: widget.session.tenantName,
        generatedAt: now,
        filtersSummary: filtersSummary,
        items: items,
      );
      final file = await _shareService.saveExcelTemp(
        excel,
        'informe_productos_recetados_${_fileStampFormat.format(now)}.xlsx',
      );
      await _shareService.shareExcel(
        file,
        'Informe de productos recetados (${items.length} registros) en Excel.',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel generado y compartido.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar Excel: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingExcel = false;
        });
      }
    }
  }

  Future<void> _exportPdf({
    required List<ReportProductItem> items,
    required String filtersSummary,
  }) async {
    if (items.isEmpty || _exportingExcel || _exportingPdf) {
      return;
    }
    final now = DateTime.now();
    setState(() {
      _exportingPdf = true;
    });
    try {
      final pdf = await _exportService.buildPdf(
        tenantName: widget.session.tenantName,
        generatedAt: now,
        filtersSummary: filtersSummary,
        items: items,
      );
      final file = await _shareService.savePdfTemp(
        pdf,
        'informe_productos_recetados_${_fileStampFormat.format(now)}.pdf',
      );
      await _shareService.sharePdf(
        file,
        'Informe de productos recetados (${items.length} registros) en PDF.',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF generado y compartido.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar PDF: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingPdf = false;
        });
      }
    }
  }

  _KpiData _calculateKpi(
    List<ApplicationOrder> filtered,
    List<_ProductReportRow> productRows,
  ) {
    var affectedArea = 0.0;
    var totalTanks = 0.0;
    final fields = <String>{};
    final plots = <String>{};
    final operators = <String>{};
    final responsibles = <String>{};
    final products = <String>{};
    for (final order in filtered) {
      affectedArea += order.affectedAreaHa;
      totalTanks += order.tankCount;
      fields.add(_cleanLabel(order.farmName, fallback: 'Sin campo'));
      plots.add(_cleanLabel(order.plotName, fallback: 'Sin lote'));
      operators.add(_cleanLabel(order.operatorName, fallback: 'Sin operador'));
      responsibles.add(
        _cleanLabel(order.engineerName, fallback: 'Sin responsable'),
      );
    }
    for (final row in productRows) {
      products.add(row.productName.toLowerCase());
    }
    return _KpiData(
      totalOrders: filtered.length,
      totalAffectedArea: affectedArea,
      totalTanks: totalTanks,
      distinctFields: fields.length,
      distinctPlots: plots.length,
      distinctOperators: operators.length,
      distinctResponsibles: responsibles.length,
      distinctProducts: products.length,
    );
  }

  List<_DayAggregate> _aggregateByDay(List<ApplicationOrder> filtered) {
    final map = <DateTime, _Counter>{};
    for (final order in filtered) {
      final day = _startOfDay(order.issuedAt);
      final counter = map.putIfAbsent(day, _Counter.new);
      counter.add(order);
    }
    final rows =
        map.entries
            .map(
              (entry) => _DayAggregate(
                date: entry.key,
                count: entry.value.count,
                affectedArea: entry.value.affectedArea,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  List<_GroupAggregate> _aggregateByField(List<ApplicationOrder> filtered) {
    final map = <String, _Counter>{};
    for (final order in filtered) {
      final field = _cleanLabel(order.farmName, fallback: 'Sin campo');
      final counter = map.putIfAbsent(field, _Counter.new);
      counter.add(order);
    }
    return map.entries
        .map(
          (entry) => _GroupAggregate(
            label: entry.key,
            count: entry.value.count,
            affectedArea: entry.value.affectedArea,
          ),
        )
        .toList(growable: false)
      ..sort(_sortAggregateRows);
  }

  List<_PlotAggregate> _aggregateByPlot(List<ApplicationOrder> filtered) {
    final map = <String, _PlotCounter>{};
    for (final order in filtered) {
      final field = _cleanLabel(order.farmName, fallback: 'Sin campo');
      final plots = _splitUniquePlots(order.plotName);
      for (final plot in plots) {
        final key = '$field||$plot';
        final counter = map.putIfAbsent(
          key,
          () => _PlotCounter(fieldLabel: field, plotLabel: plot),
        );
        counter.addSplit(order, splitCount: plots.length);
      }
    }
    return map.values
        .map(
          (item) => _PlotAggregate(
            fieldLabel: item.fieldLabel,
            plotLabel: item.plotLabel,
            count: item.count,
            affectedArea: item.affectedArea,
          ),
        )
        .toList(growable: false)
      ..sort((a, b) {
        final cmpCount = b.count.compareTo(a.count);
        if (cmpCount != 0) {
          return cmpCount;
        }
        final cmpArea = b.affectedArea.compareTo(a.affectedArea);
        if (cmpArea != 0) {
          return cmpArea;
        }
        return '${a.fieldLabel}/${a.plotLabel}'.toLowerCase().compareTo(
          '${b.fieldLabel}/${b.plotLabel}'.toLowerCase(),
        );
      });
  }

  List<_GroupAggregate> _aggregateByStatus(List<ApplicationOrder> filtered) {
    final map = <String, _Counter>{};
    for (final order in filtered) {
      final status = _executionStatusText(order);
      final counter = map.putIfAbsent(status, _Counter.new);
      counter.add(order);
    }
    return map.entries
        .map(
          (entry) => _GroupAggregate(
            label: entry.key,
            count: entry.value.count,
            affectedArea: entry.value.affectedArea,
          ),
        )
        .toList(growable: false)
      ..sort(_sortAggregateRows);
  }

  List<_ProductReportRow> _buildProductRows(
    List<ApplicationOrder> filteredOrders,
    Map<String, Recipe> recipeById,
  ) {
    final rows = <_ProductReportRow>[];
    for (final order in filteredOrders) {
      final recipe = recipeById[order.recipeId];
      if (recipe == null) {
        continue;
      }
      final fieldLabel = _cleanLabel(order.farmName, fallback: 'Sin campo');
      final plotLabel = _splitUniquePlots(order.plotName).join(', ');
      final operatorLabel = _cleanLabel(
        order.operatorName,
        fallback: 'Sin operador',
      );
      final responsibleLabel = _cleanLabel(
        order.engineerName,
        fallback: 'Sin responsable',
      );
      final statusLabel = _executionStatusText(order);
      for (final line in recipe.doseLines) {
        final productName = _cleanLabel(
          line.productName,
          fallback: 'Sin producto',
        );
        rows.add(
          _ProductReportRow(
            orderCode: order.code,
            issuedAt: order.issuedAt,
            fieldName: fieldLabel,
            plotName: plotLabel,
            productName: productName,
            activeIngredient: _cleanLabel(
              line.activeIngredient ?? '',
              fallback: '-',
            ),
            dose: line.dose,
            unit: _cleanLabel(line.unit, fallback: '-'),
            functionName: _cleanLabel(line.functionName, fallback: '-'),
            crop: _cleanLabel(recipe.crop, fallback: '-'),
            stage: _cleanLabel(recipe.stage, fallback: '-'),
            objective: _cleanLabel(recipe.objective, fallback: '-'),
            responsibleName: responsibleLabel,
            operatorName: operatorLabel,
            emissionStatus: statusLabel,
            affectedAreaHa: order.affectedAreaHa,
          ),
        );
      }
    }
    rows.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return rows;
  }

  List<_ProductAggregate> _aggregateByProduct(List<_ProductReportRow> rows) {
    final map = <String, _ProductCounter>{};
    for (final row in rows) {
      final key = '${row.productName.toLowerCase()}|${row.unit.toLowerCase()}';
      final counter = map.putIfAbsent(
        key,
        () => _ProductCounter(productName: row.productName, unit: row.unit),
      );
      counter.add(row);
    }
    return map.values
        .map(
          (item) => _ProductAggregate(
            productName: item.productName,
            unit: item.unit,
            prescriptions: item.prescriptions,
            emissions: item.orderCodes.length,
            affectedArea: item.affectedArea,
          ),
        )
        .toList(growable: false)
      ..sort((a, b) {
        final cmpCount = b.prescriptions.compareTo(a.prescriptions);
        if (cmpCount != 0) {
          return cmpCount;
        }
        return a.productName.toLowerCase().compareTo(
          b.productName.toLowerCase(),
        );
      });
  }

  List<ReportProductItem> _toExportItems(List<_ProductReportRow> rows) {
    return rows
        .map(
          (row) => ReportProductItem(
            orderCode: row.orderCode,
            issuedAt: row.issuedAt,
            fieldName: row.fieldName,
            plotName: row.plotName,
            productName: row.productName,
            activeIngredient: row.activeIngredient,
            dose: row.dose,
            unit: row.unit,
            functionName: row.functionName,
            crop: row.crop,
            stage: row.stage,
            objective: row.objective,
            responsibleName: row.responsibleName,
            operatorName: row.operatorName,
            emissionStatus: row.emissionStatus,
            affectedAreaHa: row.affectedAreaHa,
          ),
        )
        .toList(growable: false);
  }

  int _sortAggregateRows(_GroupAggregate a, _GroupAggregate b) {
    final cmpCount = b.count.compareTo(a.count);
    if (cmpCount != 0) {
      return cmpCount;
    }
    final cmpArea = b.affectedArea.compareTo(a.affectedArea);
    if (cmpArea != 0) {
      return cmpArea;
    }
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informes')),
      body: StreamBuilder<List<ApplicationOrder>>(
        stream: _repo.watchApplicationOrders(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allOrders = _ordersVisibleForCurrentUser(snapshot.data!);
          final fields = _collectFieldNames(allOrders);
          final selectedField = fields.contains(_selectedField)
              ? _selectedField
              : null;
          final availablePlots = _collectPlotNames(
            allOrders,
            selectedField: selectedField,
          );
          final selectedPlots = _selectedPlots.intersection(
            availablePlots.toSet(),
          );
          final locationFiltered = _applyLocationFilters(
            allOrders,
            selectedField: selectedField,
            selectedPlots: selectedPlots,
          );

          final operators = _collectOperatorNames(locationFiltered);
          final responsibles = _collectResponsibleNames(locationFiltered);
          final selectedOperator = operators.contains(_selectedOperator)
              ? _selectedOperator
              : null;
          final selectedResponsible =
              responsibles.contains(_selectedResponsible)
              ? _selectedResponsible
              : null;

          final filtered = _applyFinalFilters(
            locationFiltered,
            selectedOperator: selectedOperator,
            selectedResponsible: selectedResponsible,
          );

          final hasFilters =
              _periodPreset != _ReportPeriodPreset.last30Days ||
              selectedField != null ||
              selectedPlots.isNotEmpty ||
              selectedOperator != null ||
              selectedResponsible != null ||
              _executionStatusFilter != _ExecutionStatusFilter.all ||
              _customFrom != null ||
              _customTo != null;

          final filtersSummary = _activeFiltersSummary(
            selectedField: selectedField,
            selectedPlots: selectedPlots,
            selectedOperator: selectedOperator,
            selectedResponsible: selectedResponsible,
          );
          final exporting = _exportingExcel || _exportingPdf;
          final recipeById = <String, Recipe>{};
          for (final recipe in _emittedRecipes) {
            final id = recipe.id;
            if (id == null || id.isEmpty) {
              continue;
            }
            recipeById[id] = recipe;
          }
          final productRows = _buildProductRows(filtered, recipeById);
          final exportItems = _toExportItems(productRows);

          final kpi = _calculateKpi(filtered, productRows);
          final byDay = _aggregateByDay(filtered);
          final byField = _aggregateByField(filtered);
          final byPlot = _aggregateByPlot(filtered);
          final byStatus = _aggregateByStatus(filtered);
          final byProduct = _aggregateByProduct(productRows);

          return ResponsivePage(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emitidos - ${widget.session.tenantName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Filtros activos: $filtersSummary',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PeriodChip(
                            label: 'Hoy',
                            selected:
                                _periodPreset == _ReportPeriodPreset.today,
                            onTap: () => setState(
                              () => _periodPreset = _ReportPeriodPreset.today,
                            ),
                          ),
                          _PeriodChip(
                            label: 'Ultimos 7 dias',
                            selected:
                                _periodPreset == _ReportPeriodPreset.last7Days,
                            onTap: () => setState(
                              () =>
                                  _periodPreset = _ReportPeriodPreset.last7Days,
                            ),
                          ),
                          _PeriodChip(
                            label: 'Ultimos 30 dias',
                            selected:
                                _periodPreset == _ReportPeriodPreset.last30Days,
                            onTap: () => setState(
                              () => _periodPreset =
                                  _ReportPeriodPreset.last30Days,
                            ),
                          ),
                          _PeriodChip(
                            label: 'Todo',
                            selected: _periodPreset == _ReportPeriodPreset.all,
                            onTap: () => setState(
                              () => _periodPreset = _ReportPeriodPreset.all,
                            ),
                          ),
                          _PeriodChip(
                            label: 'Personalizado',
                            selected:
                                _periodPreset == _ReportPeriodPreset.custom,
                            onTap: () => setState(
                              () => _periodPreset = _ReportPeriodPreset.custom,
                            ),
                          ),
                        ],
                      ),
                      if (_periodPreset == _ReportPeriodPreset.custom) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickCustomFrom,
                              icon: const Icon(Icons.date_range_outlined),
                              label: Text(
                                _customFrom == null
                                    ? 'Desde'
                                    : 'Desde ${_dayFormat.format(_customFrom!)}',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickCustomTo,
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                _customTo == null
                                    ? 'Hasta'
                                    : 'Hasta ${_dayFormat.format(_customTo!)}',
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: selectedField,
                        decoration: const InputDecoration(
                          labelText: 'Campo',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todos los campos'),
                          ),
                          ...fields.map((field) {
                            return DropdownMenuItem<String?>(
                              value: field,
                              child: Text(field),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedField = value;
                            _selectedPlots = <String>{};
                            _selectedOperator = null;
                            _selectedResponsible = null;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: availablePlots.isEmpty
                                ? null
                                : () => _pickPlots(availablePlots),
                            icon: const Icon(Icons.filter_alt_outlined),
                            label: Text(
                              selectedPlots.isEmpty
                                  ? 'Lote(s)'
                                  : 'Lote(s): ${selectedPlots.length}',
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child:
                                DropdownButtonFormField<_ExecutionStatusFilter>(
                                  initialValue: _executionStatusFilter,
                                  decoration: const InputDecoration(
                                    labelText: 'Estado',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _ExecutionStatusFilter.values
                                      .map((value) {
                                        return DropdownMenuItem<
                                          _ExecutionStatusFilter
                                        >(
                                          value: value,
                                          child: Text(
                                            _executionStatusFilterText(value),
                                          ),
                                        );
                                      })
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() {
                                      _executionStatusFilter = value;
                                    });
                                  },
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<String?>(
                              initialValue: selectedOperator,
                              decoration: const InputDecoration(
                                labelText: 'Operador',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Todos los operadores'),
                                ),
                                ...operators.map((operator) {
                                  return DropdownMenuItem<String?>(
                                    value: operator,
                                    child: Text(operator),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedOperator = value;
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<String?>(
                              initialValue: selectedResponsible,
                              decoration: const InputDecoration(
                                labelText: 'Responsable',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Todos los responsables'),
                                ),
                                ...responsibles.map((responsible) {
                                  return DropdownMenuItem<String?>(
                                    value: responsible,
                                    child: Text(responsible),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedResponsible = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: exportItems.isEmpty || exporting
                                ? null
                                : () => _exportExcel(
                                    items: exportItems,
                                    filtersSummary: filtersSummary,
                                  ),
                            icon: const Icon(Icons.table_view_outlined),
                            label: Text(
                              _exportingExcel
                                  ? 'Exportando Excel...'
                                  : 'Exportar Excel',
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: exportItems.isEmpty || exporting
                                ? null
                                : () => _exportPdf(
                                    items: exportItems,
                                    filtersSummary: filtersSummary,
                                  ),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: Text(
                              _exportingPdf
                                  ? 'Exportando PDF...'
                                  : 'Exportar PDF',
                            ),
                          ),
                          if (hasFilters)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _periodPreset =
                                      _ReportPeriodPreset.last30Days;
                                  _customFrom = null;
                                  _customTo = null;
                                  _selectedField = null;
                                  _selectedPlots = <String>{};
                                  _selectedOperator = null;
                                  _selectedResponsible = null;
                                  _executionStatusFilter =
                                      _ExecutionStatusFilter.all;
                                });
                              },
                              child: const Text('Limpiar filtros'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (_loadingEmittedRecipes)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Cargando vista preliminar del PDF...'),
                      ],
                    ),
                  )
                else if (exportItems.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'No hay datos para generar la vista preliminar del PDF con estos filtros.',
                    ),
                  )
                else
                  _PdfPreviewPanel(
                    tenantName: widget.session.tenantName,
                    generatedAt: DateTime.now(),
                    filtersSummary: filtersSummary,
                    kpi: kpi,
                    byDay: byDay,
                    byField: byField,
                    byPlot: byPlot,
                    byStatus: byStatus,
                    byProduct: byProduct,
                    rows: exportItems,
                    dateTimeFormat: _dateTimeFormat,
                    dayFormat: _dayFormat,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _PdfPreviewPanel extends StatelessWidget {
  const _PdfPreviewPanel({
    required this.tenantName,
    required this.generatedAt,
    required this.filtersSummary,
    required this.kpi,
    required this.byDay,
    required this.byField,
    required this.byPlot,
    required this.byStatus,
    required this.byProduct,
    required this.rows,
    required this.dateTimeFormat,
    required this.dayFormat,
  });

  final String tenantName;
  final DateTime generatedAt;
  final String filtersSummary;
  final _KpiData kpi;
  final List<_DayAggregate> byDay;
  final List<_GroupAggregate> byField;
  final List<_PlotAggregate> byPlot;
  final List<_GroupAggregate> byStatus;
  final List<_ProductAggregate> byProduct;
  final List<ReportProductItem> rows;
  final DateFormat dateTimeFormat;
  final DateFormat dayFormat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final previewRows = rows.take(40).toList(growable: false);
    var currentOrderCode = '';
    var codeGroupIndex = -1;
    final tableDataRows = <TableRow>[];
    for (final row in previewRows) {
      if (row.orderCode != currentOrderCode) {
        currentOrderCode = row.orderCode;
        codeGroupIndex += 1;
      }
      final rowColor = codeGroupIndex.isEven
          ? colorScheme.surfaceContainer
          : colorScheme.primaryContainer;
      tableDataRows.add(
        TableRow(
          decoration: BoxDecoration(color: rowColor),
          children: [
            _TableCell(dateTimeFormat.format(row.issuedAt)),
            _TableCell('${row.fieldName}/${row.plotName}'),
            _TableCell(row.productName),
            _TableCell('${row.dose.toStringAsFixed(2)} ${row.unit}'),
            _TableCell(row.orderCode),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.length > previewRows.length)
            Text(
              'Mostrando ${previewRows.length} de ${rows.length} fila(s).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder.all(color: colorScheme.outlineVariant),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                  ),
                  children: [
                    _TableCell('Fecha', header: true),
                    _TableCell('Campo/Lote', header: true),
                    _TableCell('Producto', header: true),
                    _TableCell('Dosis', header: true),
                    _TableCell('Codigo', header: true),
                  ],
                ),
                ...tableDataRows,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell(this.text, {this.header = false});

  final String text;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        style: header
            ? Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)
            : Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _KpiData {
  const _KpiData({
    required this.totalOrders,
    required this.totalAffectedArea,
    required this.totalTanks,
    required this.distinctFields,
    required this.distinctPlots,
    required this.distinctOperators,
    required this.distinctResponsibles,
    required this.distinctProducts,
  });

  final int totalOrders;
  final double totalAffectedArea;
  final double totalTanks;
  final int distinctFields;
  final int distinctPlots;
  final int distinctOperators;
  final int distinctResponsibles;
  final int distinctProducts;
}

class _Counter {
  int count = 0;
  double affectedArea = 0;

  void add(ApplicationOrder order) {
    count += 1;
    affectedArea += order.affectedAreaHa;
  }
}

class _DayAggregate {
  const _DayAggregate({
    required this.date,
    required this.count,
    required this.affectedArea,
  });

  final DateTime date;
  final int count;
  final double affectedArea;
}

class _GroupAggregate {
  const _GroupAggregate({
    required this.label,
    required this.count,
    required this.affectedArea,
  });

  final String label;
  final int count;
  final double affectedArea;
}

class _PlotCounter extends _Counter {
  _PlotCounter({required this.fieldLabel, required this.plotLabel});

  final String fieldLabel;
  final String plotLabel;

  void addSplit(ApplicationOrder order, {required int splitCount}) {
    final divisor = splitCount <= 0 ? 1 : splitCount;
    add(order);
    if (divisor > 1) {
      affectedArea -= order.affectedAreaHa * (divisor - 1) / divisor;
    }
  }
}

class _PlotAggregate {
  const _PlotAggregate({
    required this.fieldLabel,
    required this.plotLabel,
    required this.count,
    required this.affectedArea,
  });

  final String fieldLabel;
  final String plotLabel;
  final int count;
  final double affectedArea;
}

class _ProductReportRow {
  const _ProductReportRow({
    required this.orderCode,
    required this.issuedAt,
    required this.fieldName,
    required this.plotName,
    required this.productName,
    required this.activeIngredient,
    required this.dose,
    required this.unit,
    required this.functionName,
    required this.crop,
    required this.stage,
    required this.objective,
    required this.responsibleName,
    required this.operatorName,
    required this.emissionStatus,
    required this.affectedAreaHa,
  });

  final String orderCode;
  final DateTime issuedAt;
  final String fieldName;
  final String plotName;
  final String productName;
  final String activeIngredient;
  final double dose;
  final String unit;
  final String functionName;
  final String crop;
  final String stage;
  final String objective;
  final String responsibleName;
  final String operatorName;
  final String emissionStatus;
  final double affectedAreaHa;
}

class _ProductCounter {
  _ProductCounter({required this.productName, required this.unit});

  final String productName;
  final String unit;
  int prescriptions = 0;
  double affectedArea = 0;
  final Set<String> orderCodes = <String>{};

  void add(_ProductReportRow row) {
    prescriptions += 1;
    affectedArea += row.affectedAreaHa;
    orderCodes.add(row.orderCode);
  }
}

class _ProductAggregate {
  const _ProductAggregate({
    required this.productName,
    required this.unit,
    required this.prescriptions,
    required this.emissions,
    required this.affectedArea,
  });

  final String productName;
  final String unit;
  final int prescriptions;
  final int emissions;
  final double affectedArea;
}
