import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models.dart';
import 'mix_validation_service.dart';

class RecetarioPdfService {
  final MixValidationService _mixValidationService =
      const MixValidationService();

  Future<Uint8List> buildProfessionalPdf(
    String tenantName,
    Recipe recipe,
    ApplicationOrder order,
    String qrData,
  ) async {
    final document = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final mixWarnings = _resolveMixValidationWarnings(recipe);

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(tenantName, order, dateFormat),
              pw.SizedBox(height: 12),
              _buildIdentity(recipe, order, dateFormat),
              pw.SizedBox(height: 10),
              _buildDoseTable(recipe, order),
              pw.SizedBox(height: 10),
              _buildWaterVolume(recipe),
              if (mixWarnings.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                _buildMixValidation(mixWarnings),
              ],
              pw.SizedBox(height: 10),
              _buildSafety(recipe),
              pw.Spacer(),
              _buildFooter(qrData),
            ],
          );
        },
      ),
    );

    return document.save();
  }

  pw.Widget _buildHeader(
    String tenantName,
    ApplicationOrder order,
    DateFormat dateFormat,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 1.2, color: PdfColors.green700),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'AGRIpy - Recetario Agronómico',
            style: pw.TextStyle(
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              pw.Text('Empresa: $tenantName'),
              pw.Text('Responsable: ${order.engineerName}'),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [pw.Text('Operador: ${order.operatorName}')],
          ),
          pw.SizedBox(height: 2),
          pw.Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              pw.Text('Código: ${order.code}'),
              pw.Text('Emisión: ${dateFormat.format(order.issuedAt)}'),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildIdentity(
    Recipe recipe,
    ApplicationOrder order,
    DateFormat dateFormat,
  ) {
    final plannedDate = order.plannedDate == null
        ? 'No definida'
        : dateFormat.format(order.plannedDate!);
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('Identificación'),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _inlineField('Campo', order.farmName),
              _inlineField('Lote', order.plotName, highlightValue: true),
              _inlineField(
                'Superficie',
                '${order.areaHa.toStringAsFixed(2)} ha',
              ),
              _inlineField(
                'Superficie afectada',
                '${order.affectedAreaHa.toStringAsFixed(2)} ha',
                highlightValue: true,
              ),
              _inlineField(
                'Capacidad tanque',
                '${order.tankCapacityLt.toStringAsFixed(2)} L',
              ),
              _inlineField(
                'Cantidad de tanque',
                order.tankCount.toStringAsFixed(2),
                highlightValue: true,
              ),
              _inlineField('Cultivo', recipe.crop),
              _inlineField('Estado fenológico', recipe.stage),
              _inlineField(
                'Fecha planificada',
                plannedDate,
                highlightValue: true,
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text('Objetivo: ${recipe.objective}'),
        ],
      ),
    );
  }

  pw.Widget _buildDoseTable(Recipe recipe, ApplicationOrder order) {
    final headers = [
      'N°',
      'Producto comercial',
      'Principio activo',
      'Unidad',
      'Dosis',
      'Por tanque',
    ];
    final tankCapacityLt = order.tankCapacityLt;
    final waterVolumeLHa = recipe.waterVolumeLHa;
    final data = recipe.doseLines
        .asMap()
        .entries
        .map(
          (entry) => [
            '${entry.key + 1}',
            _formatDoseLineProductName(entry.value),
            entry.value.activeIngredient ?? '-',
            entry.value.unit,
            entry.value.dose.toStringAsFixed(2),
            _calculatePerTankAmount(
              dosePerHa: entry.value.dose,
              tankCapacityLt: tankCapacityLt,
              waterVolumeLHa: waterVolumeLHa,
            ).toStringAsFixed(2),
          ],
        )
        .toList(growable: false);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Mezcla / Dosis / Orden de Carga (Seguir la secuencia)'),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: data.isEmpty
              ? [
                  ['-', '-', '-', '-', '-', '-'],
                ]
              : data,
          columnWidths: <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(0.55),
            1: const pw.FlexColumnWidth(2.5),
            2: const pw.FlexColumnWidth(2.4),
            3: const pw.FlexColumnWidth(0.95),
            4: const pw.FlexColumnWidth(0.95),
            5: const pw.FlexColumnWidth(1.05),
          },
          border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.6),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.green900,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green50),
          cellAlignment: pw.Alignment.centerLeft,
          cellStyle: const pw.TextStyle(fontSize: 9.5),
          headerHeight: 22,
          cellHeight: 20,
        ),
      ],
    );
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

  pw.Widget _buildWaterVolume(Recipe recipe) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Volumen de agua: ${recipe.waterVolumeLHa.toStringAsFixed(2)} L/ha',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (recipe.nozzleTypes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            _inlineField(
              'Tipo de pico/boquilla',
              recipe.nozzleTypes,
              highlightValue: true,
            ),
          ],
        ],
      ),
    );
  }

  List<String> _resolveMixValidationWarnings(Recipe recipe) {
    final items = <MixValidationItem>[];
    for (final line in recipe.doseLines) {
      final product = _stripFormulationSuffix(line.productName).trim();
      if (product.isEmpty) {
        continue;
      }
      final formulation =
          (line.formulation ?? _extractFormulationFromLabel(line.productName))
              ?.trim();
      final functionName = line.functionName.trim();
      final inferredType =
          ((formulation ?? '').toLowerCase() == 'coadyuvante' ||
              functionName.isNotEmpty)
          ? 'coadyuvante'
          : null;
      items.add(
        MixValidationItem(
          productName: product,
          formulation: formulation,
          type: inferredType,
          funcion: functionName.isEmpty ? null : functionName,
        ),
      );
    }
    return _mixValidationService.validateMix(items).warnings;
  }

  String _stripFormulationSuffix(String value) {
    return value.replaceAll(RegExp(r'\s*\([^()]*\)\s*$'), '').trim();
  }

  String? _extractFormulationFromLabel(String value) {
    final match = RegExp(r'\(([^()]+)\)\s*$').firstMatch(value.trim());
    final formulation = (match?.group(1) ?? '').trim();
    if (formulation.isEmpty) {
      return null;
    }
    return formulation;
  }

  pw.Widget _buildMixValidation(List<String> warnings) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.green200, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('Validacion de mezcla'),
          pw.SizedBox(height: 4),
          ...warnings.map(
            (warning) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                '- $warning',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDoseLineProductName(DoseLine line) {
    final productName = line.productName.trim();
    if (productName.isEmpty) {
      return '-';
    }
    final formulation = (line.formulation ?? '').trim().toUpperCase();
    if (formulation.isEmpty) {
      return productName;
    }
    final hasFormulationInLabel = RegExp(
      r'\([^()]+\)\s*$',
    ).hasMatch(productName);
    if (hasFormulationInLabel) {
      return productName;
    }
    return '$productName ($formulation)';
  }

  pw.Widget _inlineField(
    String label,
    String value, {
    bool highlightValue = false,
  }) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: '$label: '),
          pw.TextSpan(
            text: value,
            style: highlightValue
                ? pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSafety(Recipe recipe) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.orange700, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('Seguridad y restricciones'),
          pw.SizedBox(height: 4),
          pw.Text(
            recipe.warnings.isEmpty ? 'Sin advertencias.' : recipe.warnings,
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Observaciones: ${recipe.notes.isEmpty ? '-' : recipe.notes}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(String qrData) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Documento generado por AgriPy',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: qrData,
          width: 62,
          height: 62,
        ),
      ],
    );
  }

  pw.Widget _sectionTitle(String label) {
    return pw.Text(
      label,
      style: pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.green800,
      ),
    );
  }
}
