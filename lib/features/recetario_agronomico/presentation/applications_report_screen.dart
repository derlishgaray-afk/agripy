import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/services/access_controller.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/recetario_repo.dart';
import '../domain/models.dart';
import '../services/applications_report_export_service.dart';
import '../services/recetario_share.dart';

enum _ReportPeriodPreset { all, today, last7Days, last30Days, custom }

class ApplicationsReportScreen extends StatefulWidget {
  const ApplicationsReportScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<ApplicationsReportScreen> createState() =>
      _ApplicationsReportScreenState();
}

class _ApplicationsReportScreenState extends State<ApplicationsReportScreen> {
  late final RecetarioRepo _repo;
  late final ApplicationsReportExportService _exportService;
  late final RecetarioShareService _shareService;
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat _dayFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _fileStampFormat = DateFormat('yyyyMMdd_HHmm');

  _ReportPeriodPreset _periodPreset = _ReportPeriodPreset.last30Days;
  DateTime? _customFrom;
  DateTime? _customTo;
  String? _selectedField;
  Set<String> _selectedPlots = <String>{};
  String? _selectedOperator;
  bool _exportingExcel = false;
  bool _exportingPdf = false;

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
    _exportService = ApplicationsReportExportService();
    _shareService = RecetarioShareService();
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  List<_ApplicationRecord> _collectRecords(List<ApplicationOrder> orders) {
    final records = <_ApplicationRecord>[];
    for (final order in orders) {
      for (final application in order.execution.tankApplications) {
        records.add(_ApplicationRecord(order: order, application: application));
      }
    }
    records.sort(
      (a, b) => b.application.appliedAt.compareTo(a.application.appliedAt),
    );
    return List.unmodifiable(records);
  }

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
      if (token.isNotEmpty) {
        tokens.add(token);
      }
    }
    if (tokens.isEmpty) {
      return const ['Sin lote'];
    }
    return tokens.toList(growable: false);
  }

  bool _matchesSelectedPlots(
    _ApplicationRecord record,
    Set<String> selectedPlots,
  ) {
    if (selectedPlots.isEmpty) {
      return true;
    }
    final plotName = record.application.plotName.trim();
    final plots = plotName.isNotEmpty
        ? _splitUniquePlots(plotName)
        : _splitUniquePlots(record.order.plotName);
    final selected = selectedPlots
        .map((value) => value.trim().toLowerCase())
        .toSet();
    for (final plot in plots) {
      if (selected.contains(plot.toLowerCase())) {
        return true;
      }
    }
    return false;
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
  }) {
    final parts = <String>[
      'Periodo: ${_periodText()}',
      'Campo: ${selectedField ?? "Todos"}',
      'Lotes: ${selectedPlots.isEmpty ? "Todos" : selectedPlots.join(" | ")}',
      'Operador: ${selectedOperator ?? "Todos"}',
    ];
    return parts.join(' | ');
  }

  bool _withinPeriod(DateTime appliedAt) {
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
    if (from != null && appliedAt.isBefore(from)) {
      return false;
    }
    if (to != null && appliedAt.isAfter(to)) {
      return false;
    }
    return true;
  }

  List<_ApplicationRecord> _applyLocationFilters(
    List<_ApplicationRecord> records, {
    required String? selectedField,
    required Set<String> selectedPlots,
  }) {
    return records
        .where((item) {
          if (!_withinPeriod(item.application.appliedAt)) {
            return false;
          }
          final farmName = _cleanLabel(
            item.order.farmName,
            fallback: 'Sin campo',
          );
          if (selectedField != null && selectedField != farmName) {
            return false;
          }
          if (!_matchesSelectedPlots(item, selectedPlots)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  List<_ApplicationRecord> _applyFinalFilters(
    List<_ApplicationRecord> records, {
    required String? selectedOperator,
  }) {
    return records
        .where((item) {
          final operator = _cleanLabel(
            item.order.operatorName,
            fallback: 'Sin operador',
          );
          if (selectedOperator != null && selectedOperator != operator) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  List<String> _collectFieldNames(List<_ApplicationRecord> records) {
    final result = <String>{};
    for (final item in records) {
      result.add(_cleanLabel(item.order.farmName, fallback: 'Sin campo'));
    }
    final sorted = result.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  List<String> _collectPlotNames(
    List<_ApplicationRecord> records, {
    String? selectedField,
  }) {
    final result = <String>{};
    for (final item in records) {
      final field = _cleanLabel(item.order.farmName, fallback: 'Sin campo');
      if (selectedField != null && selectedField != field) {
        continue;
      }
      final applicationPlot = item.application.plotName.trim();
      if (applicationPlot.isNotEmpty) {
        result.addAll(_splitUniquePlots(applicationPlot));
      } else {
        result.addAll(_splitUniquePlots(item.order.plotName));
      }
    }
    final sorted = result.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  List<String> _collectOperatorNames(List<_ApplicationRecord> records) {
    final result = <String>{};
    for (final item in records) {
      result.add(
        _cleanLabel(item.order.operatorName, fallback: 'Sin operador'),
      );
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

  Widget _buildPeriodChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: selected,
      onSelected: (_) => setState(onTap),
    );
  }

  double _appliedTankEquivalent(_ApplicationRecord item) {
    final application = item.application;
    final order = item.order;
    if (application.appliedTankEquivalent > 0) {
      return application.appliedTankEquivalent;
    }
    if (application.appliedVolumeLt > 0 && order.tankCapacityLt > 0) {
      return application.appliedVolumeLt / order.tankCapacityLt;
    }
    if (application.tankCapacityLt > 0 && order.tankCapacityLt > 0) {
      return application.tankCount *
          (application.tankCapacityLt / order.tankCapacityLt);
    }
    return application.tankCount;
  }

  double _appliedAreaHa(_ApplicationRecord item) {
    final plannedTanks = item.order.tankCount;
    if (plannedTanks <= 0 || item.order.affectedAreaHa <= 0) {
      return 0;
    }
    final appliedEquivalent = _appliedTankEquivalent(item);
    if (appliedEquivalent <= 0) {
      return 0;
    }
    return item.order.affectedAreaHa * (appliedEquivalent / plannedTanks);
  }

  List<ApplicationReportPdfItem> _toPdfItems(List<_ApplicationRecord> records) {
    return records
        .map((item) {
          final order = item.order;
          final application = item.application;
          final plotName = _cleanLabel(
            application.plotName,
            fallback: _cleanLabel(order.plotName, fallback: 'Sin lote'),
          );
          return ApplicationReportPdfItem(
            appliedAt: application.appliedAt,
            orderCode: _cleanLabel(order.code, fallback: 'Sin codigo'),
            fieldName: _cleanLabel(order.farmName, fallback: 'Sin campo'),
            plotName: plotName,
            operatorName: _cleanLabel(
              order.operatorName,
              fallback: 'Sin operador',
            ),
            tankCount: application.tankCount,
            tankCapacityLt: application.tankCapacityLt,
            appliedAreaHa: _appliedAreaHa(item),
          );
        })
        .toList(growable: false);
  }

  Future<void> _exportPdf({
    required List<_ApplicationRecord> records,
    required String filtersSummary,
    required double totalTanks,
    required double totalAppliedAreaHa,
  }) async {
    if (records.isEmpty || _exportingExcel || _exportingPdf) {
      return;
    }
    final now = DateTime.now();
    setState(() {
      _exportingPdf = true;
    });
    try {
      final bytes = await _exportService.buildPdf(
        tenantName: widget.session.tenantName,
        generatedAt: now,
        filtersSummary: filtersSummary,
        totalRecords: records.length,
        totalTanks: totalTanks,
        totalAppliedAreaHa: totalAppliedAreaHa,
        items: _toPdfItems(records),
      );
      final file = await _shareService.savePdfTemp(
        bytes,
        'informe_aplicaciones_${_fileStampFormat.format(now)}.pdf',
      );
      await _shareService.sharePdf(
        file,
        'Informe de aplicaciones (${records.length} registros) en PDF.',
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

  Future<void> _exportExcel({
    required List<_ApplicationRecord> records,
    required String filtersSummary,
    required double totalTanks,
    required double totalAppliedAreaHa,
  }) async {
    if (records.isEmpty || _exportingExcel || _exportingPdf) {
      return;
    }
    final now = DateTime.now();
    setState(() {
      _exportingExcel = true;
    });
    try {
      final bytes = _exportService.buildExcel(
        tenantName: widget.session.tenantName,
        generatedAt: now,
        filtersSummary: filtersSummary,
        totalRecords: records.length,
        totalTanks: totalTanks,
        totalAppliedAreaHa: totalAppliedAreaHa,
        items: _toPdfItems(records),
      );
      final file = await _shareService.saveExcelTemp(
        bytes,
        'informe_aplicaciones_${_fileStampFormat.format(now)}.xlsx',
      );
      await _shareService.shareExcel(
        file,
        'Informe de aplicaciones (${records.length} registros) en Excel.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informe de Aplicaciones')),
      body: StreamBuilder<List<ApplicationOrder>>(
        stream: _repo.watchApplicationOrders(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ResponsivePage(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No se pudo cargar el informe: ${snapshot.error}',
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final visibleOrders = _ordersVisibleForCurrentUser(snapshot.data!);
          final allRecords = _collectRecords(visibleOrders);
          final fields = _collectFieldNames(allRecords);
          final selectedField = fields.contains(_selectedField)
              ? _selectedField
              : null;
          final availablePlots = _collectPlotNames(
            allRecords,
            selectedField: selectedField,
          );
          final selectedPlots = _selectedPlots.intersection(
            availablePlots.toSet(),
          );
          final locationFiltered = _applyLocationFilters(
            allRecords,
            selectedField: selectedField,
            selectedPlots: selectedPlots,
          );
          final operators = _collectOperatorNames(locationFiltered);
          final selectedOperator = operators.contains(_selectedOperator)
              ? _selectedOperator
              : null;
          final records = _applyFinalFilters(
            locationFiltered,
            selectedOperator: selectedOperator,
          );
          final hasFilters =
              _periodPreset != _ReportPeriodPreset.last30Days ||
              selectedField != null ||
              selectedPlots.isNotEmpty ||
              selectedOperator != null ||
              _customFrom != null ||
              _customTo != null;
          final totalTanks = records.fold<double>(
            0,
            (total, item) => total + item.application.tankCount,
          );
          final totalAppliedArea = records.fold<double>(
            0,
            (total, item) => total + _appliedAreaHa(item),
          );
          final filtersSummary = _activeFiltersSummary(
            selectedField: selectedField,
            selectedPlots: selectedPlots,
            selectedOperator: selectedOperator,
          );

          return ResponsivePage(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aplicaciones registradas - ${widget.session.tenantName}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Filtros activos: $filtersSummary',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildPeriodChip(
                              'Hoy',
                              _periodPreset == _ReportPeriodPreset.today,
                              () => _periodPreset = _ReportPeriodPreset.today,
                            ),
                            _buildPeriodChip(
                              'Ultimos 7 dias',
                              _periodPreset == _ReportPeriodPreset.last7Days,
                              () =>
                                  _periodPreset = _ReportPeriodPreset.last7Days,
                            ),
                            _buildPeriodChip(
                              'Ultimos 30 dias',
                              _periodPreset == _ReportPeriodPreset.last30Days,
                              () => _periodPreset =
                                  _ReportPeriodPreset.last30Days,
                            ),
                            _buildPeriodChip(
                              'Todo',
                              _periodPreset == _ReportPeriodPreset.all,
                              () => _periodPreset = _ReportPeriodPreset.all,
                            ),
                            _buildPeriodChip(
                              'Personalizado',
                              _periodPreset == _ReportPeriodPreset.custom,
                              () => _periodPreset = _ReportPeriodPreset.custom,
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
                                icon: const Icon(Icons.event_outlined),
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
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                            'field_${selectedField ?? ''}_${fields.length}',
                          ),
                          initialValue: selectedField ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Campo',
                            border: OutlineInputBorder(),
                          ),
                          items: <DropdownMenuItem<String>>[
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Todos los campos'),
                            ),
                            ...fields.map(
                              (item) => DropdownMenuItem<String>(
                                value: item,
                                child: Text(item),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedField = (value == null || value.isEmpty)
                                  ? null
                                  : value;
                              _selectedPlots = <String>{};
                            });
                          },
                        ),
                        const SizedBox(height: 10),
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
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                            'operator_${selectedOperator ?? ''}_${operators.length}',
                          ),
                          initialValue: selectedOperator ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Operador',
                            border: OutlineInputBorder(),
                          ),
                          items: <DropdownMenuItem<String>>[
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Todos los operadores'),
                            ),
                            ...operators.map(
                              (item) => DropdownMenuItem<String>(
                                value: item,
                                child: Text(item),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedOperator =
                                  (value == null || value.isEmpty)
                                  ? null
                                  : value;
                            });
                          },
                        ),
                        if (hasFilters) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _periodPreset =
                                      _ReportPeriodPreset.last30Days;
                                  _customFrom = null;
                                  _customTo = null;
                                  _selectedField = null;
                                  _selectedPlots = <String>{};
                                  _selectedOperator = null;
                                });
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Limpiar filtros'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed:
                                  _exportingExcel ||
                                      _exportingPdf ||
                                      records.isEmpty
                                  ? null
                                  : () => _exportExcel(
                                      records: records,
                                      filtersSummary: filtersSummary,
                                      totalTanks: totalTanks,
                                      totalAppliedAreaHa: totalAppliedArea,
                                    ),
                              icon: _exportingExcel
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.table_view_outlined),
                              label: Text(
                                _exportingExcel
                                    ? 'Generando Excel...'
                                    : 'Exportar Excel',
                              ),
                            ),
                            FilledButton.icon(
                              onPressed:
                                  _exportingExcel ||
                                      _exportingPdf ||
                                      records.isEmpty
                                  ? null
                                  : () => _exportPdf(
                                      records: records,
                                      filtersSummary: filtersSummary,
                                      totalTanks: totalTanks,
                                      totalAppliedAreaHa: totalAppliedArea,
                                    ),
                              icon: _exportingPdf
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.picture_as_pdf_outlined),
                              label: Text(
                                _exportingPdf
                                    ? 'Generando PDF...'
                                    : 'Exportar PDF',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Total registros: ${records.length}'),
                        Text(
                          'Total tanques aplicados: ${totalTanks.toStringAsFixed(2)}',
                        ),
                        Text(
                          'Total Has aplicadas: ${totalAppliedArea.toStringAsFixed(2)}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (records.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No hay aplicaciones registradas para mostrar.',
                      ),
                    ),
                  )
                else
                  ...records.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final order = item.order;
                    final application = item.application;
                    final appliedArea = _appliedAreaHa(item);
                    final plotName = _cleanLabel(
                      application.plotName,
                      fallback: _cleanLabel(
                        order.plotName,
                        fallback: 'Sin lote',
                      ),
                    );
                    return Card(
                      color: index.isEven
                          ? Theme.of(context).colorScheme.surfaceContainer
                          : Theme.of(context).colorScheme.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: index.isEven
                              ? Theme.of(context).colorScheme.outlineVariant
                              : Theme.of(context).colorScheme.primary,
                          width: index.isEven ? 0.6 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dateTimeFormat.format(application.appliedAt),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tanques aplicados: ${application.tankCount.toStringAsFixed(2)}',
                            ),
                            Text(
                              'Has aplicadas: ${appliedArea.toStringAsFixed(2)}',
                            ),
                            Text(
                              'Capacidad de tanque: ${application.tankCapacityLt.toStringAsFixed(0)} Lt',
                            ),
                            Text(
                              'Orden: ${_cleanLabel(order.code, fallback: 'Sin codigo')}',
                            ),
                            Text(
                              'Campo/Lote: ${_cleanLabel(order.farmName, fallback: 'Sin campo')} / '
                              '$plotName',
                            ),
                            Text(
                              'Operador: ${_cleanLabel(order.operatorName, fallback: 'Sin operador')}',
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ApplicationRecord {
  const _ApplicationRecord({required this.order, required this.application});

  final ApplicationOrder order;
  final TankApplicationEntry application;
}
