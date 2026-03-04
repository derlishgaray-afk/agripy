import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models.dart';

class RecetarioPdfService {
  Future<Uint8List> buildProfessionalPdf(
    String tenantName,
    Recipe recipe,
    ApplicationOrder order,
    String qrData,
  ) async {
    final document = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

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
              _buildDoseTable(recipe),
              pw.SizedBox(height: 10),
              _buildWaterVolume(recipe),
              pw.SizedBox(height: 10),
              _buildMixOrder(recipe),
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
            'AGRIpy - Recetario Agronomico',
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
              pw.Text('Emision: ${dateFormat.format(order.issuedAt)}'),
              pw.Text('Codigo: ${order.code}'),
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
          _sectionTitle('Identificacion'),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              pw.Text('Campo: ${order.farmName}'),
              pw.Text('Lote: ${order.plotName}'),
              pw.Text('Superficie: ${order.areaHa.toStringAsFixed(2)} ha'),
              pw.Text('Cultivo: ${recipe.crop}'),
              pw.Text('Estado fenologico: ${recipe.stage}'),
              pw.Text('Fecha planificada: $plannedDate'),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text('Objetivo: ${recipe.objective}'),
        ],
      ),
    );
  }

  pw.Widget _buildDoseTable(Recipe recipe) {
    final headers = [
      'Producto comercial',
      'Principio activo',
      'Dosis',
      'Unidad',
      'Funcion',
    ];
    final data = recipe.doseLines
        .map(
          (line) => [
            line.productName,
            line.activeIngredient ?? '-',
            line.dose.toStringAsFixed(2),
            line.unit,
            line.functionName,
          ],
        )
        .toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Mezcla / Dosis'),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: data.isEmpty
              ? [
                  ['-', '-', '-', '-', '-'],
                ]
              : data,
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

  pw.Widget _buildWaterVolume(Recipe recipe) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        'Volumen de agua: ${recipe.waterVolumeLHa.toStringAsFixed(2)} L/ha',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _buildMixOrder(Recipe recipe) {
    final lines = recipe.mixOrder.isEmpty
        ? ['Sin pasos definidos.']
        : recipe.mixOrder;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Checklist / Orden de carga'),
        pw.SizedBox(height: 4),
        ...lines.map(
          (line) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Bullet(text: line),
          ),
        ),
      ],
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
