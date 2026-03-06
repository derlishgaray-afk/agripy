import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportProductItem {
  const ReportProductItem({
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

class ReportsExportService {
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  Uint8List buildCsv({
    required String tenantName,
    required DateTime generatedAt,
    required String filtersSummary,
    required List<ReportProductItem> items,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Empresa,${_escapeCsv(tenantName)}');
    buffer.writeln(
      'Generado,${_escapeCsv(_dateTimeFormat.format(generatedAt))}',
    );
    buffer.writeln('Filtros,${_escapeCsv(filtersSummary)}');
    buffer.writeln();
    buffer.writeln(
      'Codigo,Fecha emision,Campo,Lote,Producto,Principio activo,Dosis,Unidad,Funcion,Cultivo,Estado fenologico,Objetivo,Responsable,Operador,Estado,Superficie afectada (ha)',
    );

    for (final item in items) {
      buffer.writeln(
        [
          _escapeCsv(item.orderCode),
          _escapeCsv(_dateTimeFormat.format(item.issuedAt)),
          _escapeCsv(item.fieldName),
          _escapeCsv(item.plotName),
          _escapeCsv(item.productName),
          _escapeCsv(item.activeIngredient),
          item.dose.toStringAsFixed(2),
          _escapeCsv(item.unit),
          _escapeCsv(item.functionName),
          _escapeCsv(item.crop),
          _escapeCsv(item.stage),
          _escapeCsv(item.objective),
          _escapeCsv(item.responsibleName),
          _escapeCsv(item.operatorName),
          _escapeCsv(item.emissionStatus),
          item.affectedAreaHa.toStringAsFixed(2),
        ].join(','),
      );
    }

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  Future<Uint8List> buildPdf({
    required String tenantName,
    required DateTime generatedAt,
    required String filtersSummary,
    required List<ReportProductItem> items,
  }) async {
    final document = pw.Document();
    final summary = _buildSummary(items);
    final tableRows = _buildPdfTableRows(items);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return [
            pw.Text(
              'Informe de productos recetados - $tenantName',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green800,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Generado: ${_dateTimeFormat.format(generatedAt)}'),
            pw.SizedBox(height: 4),
            pw.Text('Filtros: $filtersSummary'),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  pw.Text('Lineas: ${summary.totalRows}'),
                  pw.Text('Productos: ${summary.distinctProducts}'),
                  pw.Text('Emisiones: ${summary.distinctOrders}'),
                  pw.Text(
                    'Sup. afectada: ${summary.totalAffectedArea.toStringAsFixed(2)} ha',
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            if (items.isEmpty)
              pw.Text(
                'No hay productos recetados para los filtros seleccionados.',
              )
            else
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: tableRows,
              ),
          ];
        },
      ),
    );

    return document.save();
  }

  List<pw.TableRow> _buildPdfTableRows(List<ReportProductItem> items) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.green50),
        children: [
          _pdfHeaderCell('Codigo'),
          _pdfHeaderCell('Fecha'),
          _pdfHeaderCell('Campo/Lote'),
          _pdfHeaderCell('Producto'),
          _pdfHeaderCell('Dosis'),
          _pdfHeaderCell('Responsable'),
          _pdfHeaderCell('Operador'),
          _pdfHeaderCell('Estado'),
        ],
      ),
    ];
    var currentOrderCode = '';
    var codeGroupIndex = -1;
    for (final item in items) {
      if (item.orderCode != currentOrderCode) {
        currentOrderCode = item.orderCode;
        codeGroupIndex += 1;
      }
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: codeGroupIndex.isOdd ? PdfColors.grey100 : PdfColors.white,
          ),
          children: [
            _pdfCell(item.orderCode),
            _pdfCell(_dateTimeFormat.format(item.issuedAt)),
            _pdfCell('${item.fieldName}/${item.plotName}'),
            _pdfCell(item.productName),
            _pdfCell('${item.dose.toStringAsFixed(2)} ${item.unit}'),
            _pdfCell(item.responsibleName),
            _pdfCell(item.operatorName),
            _pdfCell(item.emissionStatus),
          ],
        ),
      );
    }
    return rows;
  }

  pw.Widget _pdfHeaderCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _pdfCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 7.5)),
    );
  }

  _SummaryData _buildSummary(List<ReportProductItem> items) {
    final products = <String>{};
    final orderAreas = <String, double>{};
    for (final item in items) {
      products.add(item.productName.toLowerCase());
      orderAreas[item.orderCode] = item.affectedAreaHa;
    }
    var totalAffectedArea = 0.0;
    for (final area in orderAreas.values) {
      totalAffectedArea += area;
    }
    return _SummaryData(
      totalRows: items.length,
      distinctProducts: products.length,
      distinctOrders: orderAreas.length,
      totalAffectedArea: totalAffectedArea,
    );
  }

  String _escapeCsv(String input) {
    final escaped = input.replaceAll('"', '""');
    return '"$escaped"';
  }
}

class _SummaryData {
  const _SummaryData({
    required this.totalRows,
    required this.distinctProducts,
    required this.distinctOrders,
    required this.totalAffectedArea,
  });

  final int totalRows;
  final int distinctProducts;
  final int distinctOrders;
  final double totalAffectedArea;
}
