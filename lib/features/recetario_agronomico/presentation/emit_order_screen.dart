import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/recetario_repo.dart';
import '../domain/models.dart';
import '../services/emit_recetario.dart';
import '../services/recetario_pdf.dart';
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
  final _farmController = TextEditingController();
  final _plotController = TextEditingController();
  final _areaController = TextEditingController();
  final _assignedController = TextEditingController();
  DateTime? _plannedDate;
  bool _submitting = false;

  late final EmitRecetarioUsecase _usecase;

  @override
  void initState() {
    super.initState();
    _assignedController.text = widget.session.uid;
    final repo = RecetarioRepo(
      firestore: FirebaseFirestore.instance,
      tenantId: widget.session.tenantId,
      currentUid: widget.session.uid,
      access: widget.session.access,
    );
    _usecase = EmitRecetarioUsecase(
      repo: repo,
      pdfService: RecetarioPdfService(),
      shareService: RecetarioShareService(),
    );
  }

  @override
  void dispose() {
    _farmController.dispose();
    _plotController.dispose();
    _areaController.dispose();
    _assignedController.dispose();
    super.dispose();
  }

  Future<void> _pickPlannedDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDate: _plannedDate ?? now,
    );
    if (date == null) {
      return;
    }
    setState(() {
      _plannedDate = DateTime(date.year, date.month, date.day, 8, 0);
    });
  }

  Future<void> _emitAndShare() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await _usecase.emitAndShare(
        tenantName: widget.session.tenantName,
        recipe: widget.recipe,
        farmName: _farmController.text.trim(),
        plotName: _plotController.text.trim(),
        areaHa: parseFlexibleDouble(_areaController.text.trim()),
        plannedDate: _plannedDate,
        engineerName: widget.session.access.displayName,
        assignedToUid: _assignedController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recetario emitido y compartido.')),
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
        : DateFormat('dd/MM/yyyy').format(_plannedDate!);

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
              TextFormField(
                controller: _farmController,
                decoration: const InputDecoration(
                  labelText: 'Campo',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _plotController,
                decoration: const InputDecoration(
                  labelText: 'Lote',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _areaController,
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
                controller: _assignedController,
                decoration: const InputDecoration(
                  labelText: 'Responsable UID',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickPlannedDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Fecha planificada: $plannedDateLabel'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _submitting ? null : _emitAndShare,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Emitir y Compartir'),
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
