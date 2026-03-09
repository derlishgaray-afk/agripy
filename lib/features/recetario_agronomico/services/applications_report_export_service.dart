import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ApplicationReportPdfItem {
  const ApplicationReportPdfItem({
    required this.appliedAt,
    required this.orderCode,
    required this.fieldName,
    required this.plotName,
    required this.operatorName,
    required this.tankCount,
    required this.tankCapacityLt,
    required this.appliedAreaHa,
  });

  final DateTime appliedAt;
  final String orderCode;
  final String fieldName;
  final String plotName;
  final String operatorName;
  final double tankCount;
  final double tankCapacityLt;
  final double appliedAreaHa;
}

class ApplicationsReportExportService {
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  Uint8List buildExcel({
    required String tenantName,
    required DateTime generatedAt,
    required String filtersSummary,
    required int totalRecords,
    required double totalTanks,
    required double totalAppliedAreaHa,
    required List<ApplicationReportPdfItem> items,
  }) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    sheet.appendRow([TextCellValue('Empresa'), TextCellValue(tenantName)]);
    sheet.appendRow([
      TextCellValue('Generado'),
      TextCellValue(_dateTimeFormat.format(generatedAt)),
    ]);
    sheet.appendRow([TextCellValue('Filtros'), TextCellValue(filtersSummary)]);
    sheet.appendRow([
      TextCellValue('Total registros'),
      TextCellValue(totalRecords.toString()),
    ]);
    sheet.appendRow([
      TextCellValue('Total tanques'),
      TextCellValue(totalTanks.toStringAsFixed(2)),
    ]);
    sheet.appendRow([
      TextCellValue('Total has aplicadas'),
      TextCellValue(totalAppliedAreaHa.toStringAsFixed(2)),
    ]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Codigo'),
      TextCellValue('Campo'),
      TextCellValue('Lote'),
      TextCellValue('Operador'),
      TextCellValue('Tanques'),
      TextCellValue('Capacidad tanque (Lt)'),
      TextCellValue('Has aplicadas'),
    ]);

    for (final item in items) {
      sheet.appendRow([
        TextCellValue(_dateTimeFormat.format(item.appliedAt)),
        TextCellValue(item.orderCode),
        TextCellValue(item.fieldName),
        TextCellValue(item.plotName),
        TextCellValue(item.operatorName),
        TextCellValue(item.tankCount.toStringAsFixed(2)),
        TextCellValue(item.tankCapacityLt.toStringAsFixed(0)),
        TextCellValue(item.appliedAreaHa.toStringAsFixed(2)),
      ]);
    }

    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('No se pudo generar el archivo Excel.');
    }
    return Uint8List.fromList(encoded);
  }

  Future<Uint8List> buildPdf({
    required String tenantName,
    required DateTime generatedAt,
    required String filtersSummary,
    required int totalRecords,
    required double totalTanks,
    required double totalAppliedAreaHa,
    required List<ApplicationReportPdfItem> items,
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return [
            pw.Text(
              'Informe de aplicaciones - $tenantName',
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
                  pw.Text('Registros: $totalRecords'),
                  pw.Text('Tanques: ${totalTanks.toStringAsFixed(2)}'),
                  pw.Text(
                    'Has aplicadas: ${totalAppliedAreaHa.toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            if (items.isEmpty)
              pw.Text('No hay aplicaciones para los filtros seleccionados.')
            else
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: _buildRows(items),
              ),
          ];
        },
      ),
    );
    return document.save();
  }

  List<pw.TableRow> _buildRows(List<ApplicationReportPdfItem> items) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.green50),
        children: [
          _headerCell('Fecha'),
          _headerCell('Codigo'),
          _headerCell('Campo/Lote'),
          _headerCell('Operador'),
          _headerCell('Tanques'),
          _headerCell('Has'),
        ],
      ),
    ];

    for (final item in items) {
      rows.add(
        pw.TableRow(
          children: [
            _cell(_dateTimeFormat.format(item.appliedAt)),
            _cell(item.orderCode),
            _cell('${item.fieldName}/${item.plotName}'),
            _cell(item.operatorName),
            _cell(item.tankCount.toStringAsFixed(2)),
            _cell(item.appliedAreaHa.toStringAsFixed(2)),
          ],
        ),
      );
    }
    return rows;
  }

  pw.Widget _headerCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _cell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 7.5)),
    );
  }
}
