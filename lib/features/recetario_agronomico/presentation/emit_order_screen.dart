import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
  final _tankCapacityController = TextEditingController();
  final _responsibleController = TextEditingController();
  DateTime? _plannedDate;
  bool _submitting = false;

  late final EmitRecetarioUsecase _usecase;
  late final RecetarioCatalogRepo _catalogRepo;

  StreamSubscription<List<FieldRegistryItem>>? _fieldsSub;
  StreamSubscription<List<OperatorRegistryItem>>? _operatorsSub;

  List<FieldRegistryItem> _fields = const [];
  List<OperatorRegistryItem> _operators = const [];
  String? _selectedFieldId;
  int? _selectedLotIndex;
  String? _selectedOperatorId;
  String? _preferredOperatorName;

  @override
  void initState() {
    super.initState();
    final displayName = widget.session.access.displayName.trim();
    _responsibleController.text = displayName.isEmpty ? 'Usuario' : displayName;
    _preferredOperatorName = displayName.isEmpty ? null : displayName;
    _affectedAreaController.addListener(_onTankInputsChanged);
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
        _syncSelectedFieldAndLot();
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
    _tankCapacityController.removeListener(_onTankInputsChanged);
    _affectedAreaController.dispose();
    _tankCapacityController.dispose();
    _responsibleController.dispose();
    _fieldsSub?.cancel();
    _operatorsSub?.cancel();
    super.dispose();
  }

  void _syncSelectedFieldAndLot() {
    final selectedField = _selectedField;
    if (selectedField == null) {
      _selectedFieldId = null;
      _selectedLotIndex = null;
      return;
    }
    if (_selectedLotIndex != null &&
        (_selectedLotIndex! < 0 || _selectedLotIndex! >= selectedField.lots.length)) {
      _selectedLotIndex = null;
    }
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

  FieldLot? get _selectedLot {
    final field = _selectedField;
    if (field == null) {
      return null;
    }
    final index = _selectedLotIndex;
    if (index == null || index < 0 || index >= field.lots.length) {
      return null;
    }
    return field.lots[index];
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

  double get _calculatedTankCount {
    final affectedAreaHa = parseFlexibleDouble(_affectedAreaController.text.trim());
    final tankCapacityLt = parseFlexibleDouble(_tankCapacityController.text.trim());
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
    });
  }

  Future<void> _emitAndSharePdf() async {
    await _emitAndShare(isPng: false);
  }

  Future<void> _emitAndSharePng() async {
    await _emitAndShare(isPng: true);
  }

  Future<void> _emitAndShare({required bool isPng}) async {
    if (!_formKey.currentState!.validate()) {
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
          plotName: _selectedLot!.name,
          areaHa: parseFlexibleDouble(_areaController.text.trim()),
          affectedAreaHa: parseFlexibleDouble(
            _affectedAreaController.text.trim(),
          ),
          tankCapacityLt: parseFlexibleDouble(_tankCapacityController.text.trim()),
          plannedDate: _plannedDate,
          engineerName: _responsibleController.text.trim(),
          operatorName: _selectedOperator!.name,
          assignedToUid: widget.session.uid,
        );
      } else {
        await _usecase.emitAndSharePdf(
          tenantName: widget.session.tenantName,
          recipe: widget.recipe,
          farmName: _selectedField!.name,
          plotName: _selectedLot!.name,
          areaHa: parseFlexibleDouble(_areaController.text.trim()),
          affectedAreaHa: parseFlexibleDouble(
            _affectedAreaController.text.trim(),
          ),
          tankCapacityLt: parseFlexibleDouble(_tankCapacityController.text.trim()),
          plannedDate: _plannedDate,
          engineerName: _responsibleController.text.trim(),
          operatorName: _selectedOperator!.name,
          assignedToUid: widget.session.uid,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo emitir: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        _selectedLotIndex = null;
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
              DropdownButtonFormField<int>(
                initialValue: _selectedLotIndex,
                decoration: const InputDecoration(
                  labelText: 'Lote',
                  border: OutlineInputBorder(),
                ),
                items: _selectedField == null
                    ? const []
                    : List.generate(_selectedField!.lots.length, (index) {
                        final lot = _selectedField!.lots[index];
                        return DropdownMenuItem<int>(
                          value: index,
                          child: Text(
                            '${lot.name} (${lot.areaHa.toStringAsFixed(2)} ha)',
                          ),
                        );
                      }),
                onChanged: _submitting || _selectedField == null
                    ? null
                    : (value) {
                        setState(() {
                          _selectedLotIndex = value;
                          final selectedLot = _selectedLot;
                          if (selectedLot != null) {
                            _areaController.text =
                                selectedLot.areaHa.toStringAsFixed(2);
                          }
                        });
                      },
                validator: (_) {
                  final field = _selectedField;
                  if (field == null) {
                    return 'Selecciona un campo primero';
                  }
                  if (field.lots.isEmpty) {
                    return 'El campo no tiene lotes registrados';
                  }
                  if (_selectedLotIndex == null) {
                    return 'Selecciona un lote';
                  }
                  return null;
                },
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Superficie afectada (ha)',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tankCapacityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Fecha planificada: $plannedDateLabel'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _submitting ? null : _emitAndSharePdf,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Emitir y compartir PDF'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _emitAndSharePng,
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
}
