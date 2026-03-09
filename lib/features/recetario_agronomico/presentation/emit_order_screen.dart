import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/catalog_repo.dart';
import '../data/recetario_repo.dart';
import '../domain/catalog_models.dart';
import '../domain/models.dart';
import '../services/emit_recetario.dart';
import '../services/recetario_pdf.dart';
import '../services/recetario_png.dart';
import '../services/recetario_share.dart';

class EmitOrderScreen extends StatefulWidget {
  const EmitOrderScreen({
    super.key,
    required this.session,
    required this.recipe,
  });

  final AppSession session;
  final Recipe recipe;

  @override
  State<EmitOrderScreen> createState() => _EmitOrderScreenState();
}

class _EmitOrderScreenState extends State<EmitOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _areaController = TextEditingController();
  final _affectedAreaController = TextEditingController();
  final _affectedAreaFocusNode = FocusNode();
  final _tankCapacityController = TextEditingController();
  final _responsibleController = TextEditingController();
  DateTime? _plannedDate;
  bool _plannedDateRequiredError = false;
  bool _submitting = false;

  late final EmitRecetarioUsecase _usecase;
  late final RecetarioCatalogRepo _catalogRepo;

  StreamSubscription<List<FieldRegistryItem>>? _fieldsSub;
  StreamSubscription<List<OperatorRegistryItem>>? _operatorsSub;

  List<FieldRegistryItem> _fields = const [];
  List<OperatorRegistryItem> _operators = const [];
  String? _selectedFieldId;
  final Set<int> _selectedLotIndexes = <int>{};
  bool _lotsRequiredError = false;
  String? _selectedOperatorId;
  String? _preferredOperatorName;

  @override
  void initState() {
    super.initState();
    final displayName = widget.session.access.displayName.trim();
    _responsibleController.text = displayName.isEmpty ? 'Usuario' : displayName;
    _preferredOperatorName = displayName.isEmpty ? null : displayName;
    _affectedAreaController.addListener(_onTankInputsChanged);
    _affectedAreaFocusNode.addListener(_onAffectedAreaFocusChanged);
    _tankCapacityController.addListener(_onTankInputsChanged);
    final repo = RecetarioRepo(
      firestore: FirebaseFirestore.instance,
      tenantId: widget.session.tenantId,
      currentUid: widget.session.uid,
      access: widget.session.access,
    );
    _usecase = EmitRecetarioUsecase(
      repo: repo,
      pdfService: RecetarioPdfService(),
      pngService: RecetarioPngService(),
      shareService: RecetarioShareService(),
    );
    _catalogRepo = RecetarioCatalogRepo(
      firestore: FirebaseFirestore.instance,
      tenantId: widget.session.tenantId,
      currentUid: widget.session.uid,
      access: widget.session.access,
    );
    _fieldsSub = _catalogRepo.watchFields().listen((items) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fields = items;
        _syncSelectedLots();
      });
    });
    _operatorsSub = _catalogRepo.watchOperators().listen((items) {
      if (!mounted) {
        return;
      }
      setState(() {
        _operators = items;
        _syncSelectedOperator();
      });
    });
  }

  @override
  void dispose() {
    _areaController.dispose();
    _affectedAreaController.removeListener(_onTankInputsChanged);
    _affectedAreaFocusNode.removeListener(_onAffectedAreaFocusChanged);
    _affectedAreaFocusNode.dispose();
    _tankCapacityController.removeListener(_onTankInputsChanged);
    _affectedAreaController.dispose();
    _tankCapacityController.dispose();
    _responsibleController.dispose();
    _fieldsSub?.cancel();
    _operatorsSub?.cancel();
    super.dispose();
  }

  void _syncSelectedLots() {
    final selectedField = _selectedField;
    if (selectedField == null) {
      _selectedFieldId = null;
      _selectedLotIndexes.clear();
      return;
    }
    _selectedLotIndexes.removeWhere(
      (index) => index < 0 || index >= selectedField.lots.length,
    );
    _syncAreaWithSelectedLots();
  }

  void _syncSelectedOperator() {
    final hasCurrentSelection = _operators.any(
      (item) => item.id == _selectedOperatorId,
    );
    if (!hasCurrentSelection) {
      _selectedOperatorId = null;
    }
    if (_selectedOperatorId == null && _preferredOperatorName != null) {
      for (final item in _operators) {
        if (item.name.trim().toLowerCase() ==
            _preferredOperatorName!.trim().toLowerCase()) {
          _selectedOperatorId = item.id;
          break;
        }
      }
    }
  }

  FieldRegistryItem? get _selectedField {
    for (final item in _fields) {
      if (item.id == _selectedFieldId) {
        return item;
      }
    }
    return null;
  }

  List<FieldLot> get _selectedLots {
    final field = _selectedField;
    if (field == null) {
      return const [];
    }
    final sortedIndexes = _selectedLotIndexes.toList(growable: false)..sort();
    final lots = <FieldLot>[];
    for (final index in sortedIndexes) {
      if (index >= 0 && index < field.lots.length) {
        lots.add(field.lots[index]);
      }
    }
    return List.unmodifiable(lots);
  }

  OperatorRegistryItem? get _selectedOperator {
    for (final item in _operators) {
      if (item.id == _selectedOperatorId) {
        return item;
      }
    }
    return null;
  }

  void _onTankInputsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onAffectedAreaFocusChanged() {
    if (_affectedAreaFocusNode.hasFocus) {
      return;
    }
    final normalized = _normalizeAffectedAreaText(_affectedAreaController.text);
    if (_affectedAreaController.text != normalized) {
      _affectedAreaController.text = normalized;
    }
    if (mounted) {
      setState(() {});
    }
  }

  String _normalizeAffectedAreaText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final parsed = _parseDecimalThousands(trimmed);
    return _formatDecimalThousands(parsed, decimals: 2);
  }

  void _syncAreaWithSelectedLots() {
    final totalArea = _selectedLots.fold<double>(
      0,
      (total, lot) => total + lot.areaHa,
    );
    if (totalArea <= 0) {
      _areaController.clear();
      return;
    }
    _areaController.text = _formatDecimalThousands(totalArea, decimals: 2);
  }

  Future<void> _pickLots() async {
    final field = _selectedField;
    if (field == null || field.lots.isEmpty) {
      return;
    }
    final tempSelection = _selectedLotIndexes.toSet();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Seleccionar lotes'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < field.lots.length; index++)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${field.lots[index].name} (${field.lots[index].areaHa.toStringAsFixed(2)} ha)',
                          ),
                          value: tempSelection.contains(index),
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked == true) {
                                tempSelection.add(index);
                              } else {
                                tempSelection.remove(index);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (accepted != true || !mounted) {
      return;
    }
    setState(() {
      _selectedLotIndexes
        ..clear()
        ..addAll(tempSelection);
      _lotsRequiredError = _selectedLotIndexes.isEmpty;
      _syncAreaWithSelectedLots();
    });
  }

  double get _calculatedTankCount {
    final affectedAreaHa = _parseDecimalThousands(_affectedAreaController.text);
    final tankCapacityLt = _parseTankCapacityInt(_tankCapacityController.text);
    final waterVolumeLHa = widget.recipe.waterVolumeLHa;
    if (affectedAreaHa <= 0 || tankCapacityLt <= 0 || waterVolumeLHa <= 0) {
      return 0;
    }
    return affectedAreaHa / (tankCapacityLt / waterVolumeLHa);
  }

  Future<void> _pickPlannedDateTime() async {
    final now = DateTime.now();
    final initialDate = _plannedDate ?? now;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDate: initialDate,
    );
    if (date == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final initialTime = TimeOfDay.fromDateTime(_plannedDate ?? now);
    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (time == null) {
      return;
    }
    setState(() {
      _plannedDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _plannedDateRequiredError = false;
    });
  }

  Future<void> _emitAndSharePdf() async {
    await _emitAndShare(isPng: false);
  }

  Future<void> _emitAndSharePng() async {
    await _emitAndShare(isPng: true);
  }

  Future<void> _emitAndShare({required bool isPng}) async {
    if (_selectedLots.isEmpty) {
      setState(() {
        _lotsRequiredError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un lote.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_plannedDate == null) {
      setState(() {
        _plannedDateRequiredError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una fecha planificada.')),
      );
      return;
    }
    final plannedDate = _plannedDate!;
    final selectedLots = _selectedLots;
    final selectedOperator = _selectedOperator;
    final assignedToUid = selectedOperator?.linkedUserUid?.trim() ?? '';
    final plotName = selectedLots.map((lot) => lot.name).join(', ');
    final areaHa = _parseDecimalThousands(_areaController.text);
    final affectedAreaHa = _parseDecimalThousands(_affectedAreaController.text);
    if (affectedAreaHa <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La superficie afectada debe ser mayor a cero.'),
        ),
      );
      return;
    }
    if (areaHa > 0 && affectedAreaHa > areaHa) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La superficie afectada no puede superar la superficie total.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      if (isPng) {
        await _usecase.emitAndSharePng(
          tenantName: widget.session.tenantName,
          recipe: widget.recipe,
          farmName: _selectedField!.name,
          plotName: plotName,
          areaHa: areaHa,
          affectedAreaHa: affectedAreaHa,
          tankCapacityLt: _parseTankCapacityInt(_tankCapacityController.text),
          plannedDate: plannedDate,
          engineerName: _responsibleController.text.trim(),
          operatorName: selectedOperator!.name,
          assignedToUid: assignedToUid,
        );
      } else {
        await _usecase.emitAndSharePdf(
          tenantName: widget.session.tenantName,
          recipe: widget.recipe,
          farmName: _selectedField!.name,
          plotName: plotName,
          areaHa: areaHa,
          affectedAreaHa: affectedAreaHa,
          tankCapacityLt: _parseTankCapacityInt(_tankCapacityController.text),
          plannedDate: plannedDate,
          engineerName: _responsibleController.text.trim(),
          operatorName: selectedOperator!.name,
          assignedToUid: assignedToUid,
        );
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPng
                ? 'Recetario emitido y compartido en PNG.'
                : 'Recetario emitido y compartido en PDF.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyEmitErrorMessage(error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo emitir: $message')));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  String _friendlyEmitErrorMessage(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Permiso denegado en Firestore. Verifica reglas del tenant.';
      }
      if (error.code == 'unavailable') {
        return 'Servicio no disponible. Revisa tu conexion e intenta de nuevo.';
      }
      final message = (error.message ?? '').trim();
      if (message.isNotEmpty) {
        return message;
      }
      return error.code.trim().isEmpty ? 'Error de Firestore.' : error.code;
    }

    final raw = error.toString().trim();
    if (raw.contains('Dart exception thrown from converted Future')) {
      return 'Error interno de Firestore al procesar la emision. Verifica permisos del contador secuencial.';
    }
    return raw.isEmpty ? 'Error inesperado.' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final selectedField = _selectedField;
    final selectedLots = _selectedLots;
    final hasSelectedLots = selectedLots.isNotEmpty;
    final selectedLotsSummary = hasSelectedLots
        ? selectedLots
              .map((lot) => '${lot.name} (${lot.areaHa.toStringAsFixed(2)} ha)')
              .join(' | ')
        : 'Sin lotes seleccionados.';
    final hasPlannedDate = _plannedDate != null;
    final plannedDateMissing = !hasPlannedDate && _plannedDateRequiredError;
    final plannedDateLabel = _plannedDate == null
        ? 'Sin fecha planificada'
        : DateFormat('dd/MM/yyyy HH:mm').format(_plannedDate!);

    return Scaffold(
      appBar: AppBar(title: const Text('Emitir recetario')),
      body: Form(
        key: _formKey,
        child: ResponsivePage(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.recipe.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text('${widget.recipe.crop} - ${widget.recipe.stage}'),
                      const SizedBox(height: 6),
                      Text('Objetivo: ${widget.recipe.objective}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedFieldId,
                decoration: const InputDecoration(
                  labelText: 'Campo',
                  border: OutlineInputBorder(),
                ),
                items: _fields
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _submitting || _fields.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          _selectedFieldId = value;
                          _selectedLotIndexes.clear();
                          _lotsRequiredError = false;
                          _areaController.clear();
                          _affectedAreaController.clear();
                        });
                      },
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Selecciona un campo';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Lotes',
                  border: const OutlineInputBorder(),
                  errorText: _lotsRequiredError
                      ? 'Selecciona al menos un lote'
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          _submitting ||
                              selectedField == null ||
                              selectedField.lots.isEmpty
                          ? null
                          : _pickLots,
                      icon: const Icon(Icons.checklist_outlined),
                      label: Text(
                        selectedField == null
                            ? 'Selecciona un campo primero'
                            : selectedField.lots.isEmpty
                            ? 'El campo no tiene lotes registrados'
                            : hasSelectedLots
                            ? '${selectedLots.length} lotes seleccionados'
                            : 'Seleccionar lotes',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selectedLotsSummary,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _areaController,
                readOnly: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Superficie (ha)',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _affectedAreaController,
                focusNode: _affectedAreaFocusNode,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]')),
                  const _ThousandsDecimalInputFormatter(maxDecimals: 2),
                ],
                decoration: const InputDecoration(
                  labelText: 'Superficie afectada (ha)',
                  border: OutlineInputBorder(),
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) {
                  if (mounted) {
                    setState(() {});
                  }
                },
                validator: _affectedAreaValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tankCapacityController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  const _ThousandsIntInputFormatter(),
                ],
                decoration: const InputDecoration(
                  labelText: 'Capacidad Lt tanque',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Cantidad de tanque (calculado)',
                  border: OutlineInputBorder(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _calculatedTankCount.toStringAsFixed(2),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Formula: superficie afectada / (capacidad tanque / volumen agua por ha)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _responsibleController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Responsable',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedOperatorId,
                decoration: const InputDecoration(
                  labelText: 'Operador',
                  border: OutlineInputBorder(),
                ),
                items: _operators
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _submitting || _operators.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          _selectedOperatorId = value;
                        });
                      },
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Selecciona un operador';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickPlannedDateTime,
                style: plannedDateMissing
                    ? OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  hasPlannedDate
                      ? 'Fecha planificada: $plannedDateLabel'
                      : 'Fecha planificada (obligatoria): $plannedDateLabel',
                ),
              ),
              if (plannedDateMissing) ...[
                const SizedBox(height: 6),
                Text(
                  'Campo obligatorio.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _submitting || !hasPlannedDate || !hasSelectedLots
                    ? null
                    : _emitAndSharePdf,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Emitir y compartir PDF'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _submitting || !hasPlannedDate || !hasSelectedLots
                    ? null
                    : _emitAndSharePng,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Emitir y compartir PNG'),
              ),
              if (_submitting) ...[
                const SizedBox(height: 12),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo obligatorio';
    }
    return null;
  }

  String? _affectedAreaValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Campo obligatorio';
    }
    final affectedArea = _parseDecimalThousands(text);
    if (affectedArea <= 0) {
      return 'Debe ser mayor a cero';
    }
    final totalArea = _parseDecimalThousands(_areaController.text);
    if (totalArea > 0 && affectedArea > totalArea) {
      return 'No puede superar la superficie (ha)';
    }
    return null;
  }

  double _parseTankCapacityInt(String? value) {
    final digitsOnly = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return 0;
    }
    return double.tryParse(digitsOnly) ?? 0;
  }

  String _formatDecimalThousands(num value, {int decimals = 2}) {
    final fixed = value.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    if (decimals <= 0 || parts.length < 2) {
      return intPart;
    }
    return '$intPart,${parts[1]}';
  }

  double _parseDecimalThousands(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return 0;
    }
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    final lastComma = compact.lastIndexOf(',');
    final lastDot = compact.lastIndexOf('.');
    String normalized;
    if (lastComma >= 0 && lastDot >= 0) {
      if (lastComma > lastDot) {
        normalized = compact.replaceAll('.', '').replaceAll(',', '.');
      } else {
        normalized = compact.replaceAll(',', '');
      }
    } else if (lastComma >= 0) {
      normalized = compact.replaceAll('.', '').replaceAll(',', '.');
    } else {
      normalized = compact.replaceAll(',', '');
    }
    return double.tryParse(normalized) ?? 0;
  }
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

class _ThousandsDecimalInputFormatter extends TextInputFormatter {
  const _ThousandsDecimalInputFormatter({this.maxDecimals = 2});

  final int maxDecimals;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(RegExp(r'[^0-9,\.]'), '');
    if (raw.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final lastComma = raw.lastIndexOf(',');
    final lastDot = raw.lastIndexOf('.');
    final decimalIndex = lastComma > lastDot ? lastComma : lastDot;

    String intDigits;
    String decimalDigits = '';
    var hasDecimalSeparator = false;

    if (decimalIndex >= 0) {
      hasDecimalSeparator = true;
      intDigits = raw
          .substring(0, decimalIndex)
          .replaceAll(RegExp(r'[^0-9]'), '');
      decimalDigits = raw
          .substring(decimalIndex + 1)
          .replaceAll(RegExp(r'[^0-9]'), '');
      if (decimalDigits.length > maxDecimals) {
        decimalDigits = decimalDigits.substring(0, maxDecimals);
      }
    } else {
      intDigits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    }

    if (intDigits.isEmpty) {
      intDigits = '0';
    }

    final intFormatted = intDigits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

    final text = hasDecimalSeparator
        ? '$intFormatted,$decimalDigits'
        : intFormatted;

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
