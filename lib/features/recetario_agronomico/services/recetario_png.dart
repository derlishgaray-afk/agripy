import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/models.dart';

class RecetarioPngService {
  Future<Uint8List> buildEmissionPng({
    required String tenantName,
    required Recipe recipe,
    required RecipeEmissionData emission,
  }) async {
    const width = 1080;
    const height = 1528;
    const pagePadding = 48.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.white,
    );

    final titleStyle = const TextStyle(
      fontSize: 50,
      fontWeight: FontWeight.w700,
      color: Color(0xFF1E6A2F),
    );
    final sectionTitleStyle = const TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w700,
      color: Color(0xFF1E6A2F),
    );
    final bodyStyle = const TextStyle(fontSize: 28, color: Color(0xFF202020));
    final labelStyle = bodyStyle.copyWith(fontWeight: FontWeight.w600);
    final highlightedValueStyle = bodyStyle.copyWith(
      fontWeight: FontWeight.w700,
      color: const Color(0xFFC62828),
    );
    final smallStyle = const TextStyle(fontSize: 22, color: Color(0xFF303030));
    final smallHighlightedValueStyle = smallStyle.copyWith(
      fontWeight: FontWeight.w700,
      color: const Color(0xFFC62828),
    );

    final pageWidth = width - (pagePadding * 2);
    final plannedDateText = emission.plannedDate == null
        ? 'No definida'
        : dateFormat.format(emission.plannedDate!);

    var y = pagePadding;

    final headerLine1Fields = <_InlineField>[
      _InlineField(label: 'Empresa', value: tenantName),
      _InlineField(label: 'Responsable', value: _safe(emission.engineerName)),
    ];
    final headerLine2Fields = <_InlineField>[
      _InlineField(label: 'Operador', value: _safe(emission.operatorName)),
    ];
    final headerLine3Fields = <_InlineField>[
      _InlineField(label: 'Código', value: _safe(emission.code)),
      _InlineField(
        label: 'Emisión',
        value: dateFormat.format(emission.issuedAt),
      ),
    ];
    final headerHeight =
        24 +
        _measureTextHeight(
          'AGRIpy - Recetario Agronómico',
          titleStyle,
          pageWidth - 24,
        ) +
        12 +
        _measureInlineFieldsHeight(
          fields: headerLine1Fields,
          labelStyle: bodyStyle,
          highlightedValueStyle: highlightedValueStyle,
          maxWidth: pageWidth - 24,
        ) +
        8 +
        _measureInlineFieldsHeight(
          fields: headerLine2Fields,
          labelStyle: bodyStyle,
          highlightedValueStyle: highlightedValueStyle,
          maxWidth: pageWidth - 24,
        ) +
        6 +
        _measureInlineFieldsHeight(
          fields: headerLine3Fields,
          labelStyle: bodyStyle,
          highlightedValueStyle: highlightedValueStyle,
          maxWidth: pageWidth - 24,
        ) +
        24;

    final headerRect = Rect.fromLTWH(pagePadding, y, pageWidth, headerHeight);
    _drawBox(
      canvas,
      rect: headerRect,
      borderColor: const Color(0xFF3B9B48),
      borderWidth: 2.2,
      radius: 10,
    );
    var hy = y + 18;
    hy = _paintBlockText(
      canvas,
      text: 'AGRIpy - Recetario Agronómico',
      x: pagePadding + 18,
      y: hy,
      maxWidth: pageWidth - 36,
      style: titleStyle,
    );
    hy += 8;
    hy = _paintInlineFields(
      canvas,
      fields: headerLine1Fields,
      x: pagePadding + 18,
      y: hy,
      maxWidth: pageWidth - 36,
      labelStyle: bodyStyle,
      highlightedValueStyle: highlightedValueStyle,
    );
    hy += 4;
    hy = _paintInlineFields(
      canvas,
      fields: headerLine2Fields,
      x: pagePadding + 18,
      y: hy,
      maxWidth: pageWidth - 36,
      labelStyle: bodyStyle,
      highlightedValueStyle: highlightedValueStyle,
    );
    hy += 2;
    _paintInlineFields(
      canvas,
      fields: headerLine3Fields,
      x: pagePadding + 18,
      y: hy,
      maxWidth: pageWidth - 36,
      labelStyle: bodyStyle,
      highlightedValueStyle: highlightedValueStyle,
    );
    y += headerHeight + 24;

    final idLines = <List<_InlineField>>[
      [
        _InlineField(label: 'Campo', value: _safe(emission.farmName)),
        _InlineField(
          label: 'Lote',
          value: _safe(emission.plotName),
          highlightValue: true,
        ),
        _InlineField(
          label: 'Superficie',
          value: '${emission.areaHa.toStringAsFixed(2)} ha',
        ),
      ],
      [
        _InlineField(
          label: 'Superficie afectada',
          value: '${emission.affectedAreaHa.toStringAsFixed(2)} ha',
          highlightValue: true,
        ),
      ],
      [
        _InlineField(
          label: 'Capacidad tanque',
          value: '${emission.tankCapacityLt.toStringAsFixed(2)} L',
        ),
        _InlineField(
          label: 'Cantidad de tanque',
          value: emission.tankCount.toStringAsFixed(2),
          highlightValue: true,
        ),
      ],
      [
        _InlineField(label: 'Cultivo', value: _safe(recipe.crop)),
        _InlineField(label: 'Estado fenológico', value: _safe(recipe.stage)),
      ],
      [
        _InlineField(
          label: 'Fecha planificada',
          value: plannedDateText,
          highlightValue: true,
        ),
      ],
      [_InlineField(label: 'Objetivo', value: _safe(recipe.objective))],
    ];
    final identityHeight =
        20 +
        _measureTextHeight(
          'Identificación',
          sectionTitleStyle,
          pageWidth - 24,
        ) +
        10 +
        idLines
            .map(
              (line) =>
                  _measureInlineFieldsHeight(
                    fields: line,
                    labelStyle: bodyStyle,
                    highlightedValueStyle: highlightedValueStyle,
                    maxWidth: pageWidth - 24,
                  ) +
                  4,
            )
            .fold<double>(0, (a, b) => a + b) +
        16;
    final identityRect = Rect.fromLTWH(
      pagePadding,
      y,
      pageWidth,
      identityHeight,
    );
    _drawBox(
      canvas,
      rect: identityRect,
      borderColor: const Color(0xFFBBBBBB),
      borderWidth: 1.8,
      radius: 8,
    );
    var iy = y + 14;
    iy = _paintBlockText(
      canvas,
      text: 'Identificación',
      x: pagePadding + 16,
      y: iy,
      maxWidth: pageWidth - 32,
      style: sectionTitleStyle.copyWith(fontSize: 34),
    );
    iy += 8;
    for (final line in idLines) {
      iy = _paintInlineFields(
        canvas,
        fields: line,
        x: pagePadding + 16,
        y: iy,
        maxWidth: pageWidth - 32,
        labelStyle: bodyStyle,
        highlightedValueStyle: highlightedValueStyle,
      );
      iy += 2;
    }
    y += identityHeight + 22;

    y = _paintBlockText(
      canvas,
      text: 'Mezcla / Dosis',
      x: pagePadding,
      y: y,
      maxWidth: pageWidth,
      style: sectionTitleStyle.copyWith(fontSize: 34),
    );
    y += 10;

    final headers = [
      'Producto comercial',
      'Principio activo',
      'Unidad',
      'Dosis',
      'Por tanque',
    ];
    final tankCapacityLt = emission.tankCapacityLt;
    final waterVolumeLHa = recipe.waterVolumeLHa;
    final columnFlex = [0.30, 0.32, 0.10, 0.12, 0.16];
    final rows = recipe.doseLines.isEmpty
        ? [
            ['-', '-', '-', '-', '-'],
          ]
        : recipe.doseLines
              .map(
                (line) => [
                  _safe(line.productName),
                  _safe(line.activeIngredient),
                  _safe(line.unit),
                  line.dose.toStringAsFixed(2),
                  _calculatePerTankAmount(
                    dosePerHa: line.dose,
                    tankCapacityLt: tankCapacityLt,
                    waterVolumeLHa: waterVolumeLHa,
                  ).toStringAsFixed(2),
                ],
              )
              .toList(growable: false);
    const tableHeaderHeight = 46.0;
    const tableRowHeight = 42.0;
    final tableHeight = tableHeaderHeight + (rows.length * tableRowHeight);
    final tableRect = Rect.fromLTWH(pagePadding, y, pageWidth, tableHeight);

    _drawBox(
      canvas,
      rect: tableRect,
      borderColor: const Color(0xFF7B7B7B),
      borderWidth: 1.5,
      radius: 0,
    );
    canvas.drawRect(
      Rect.fromLTWH(pagePadding, y, pageWidth, tableHeaderHeight),
      Paint()..color = const Color(0xFFE8F3EA),
    );
    canvas.drawLine(
      Offset(pagePadding, y + tableHeaderHeight),
      Offset(pagePadding + pageWidth, y + tableHeaderHeight),
      Paint()
        ..color = const Color(0xFF7B7B7B)
        ..strokeWidth = 1.5,
    );

    final columnWidths = <double>[];
    for (final flex in columnFlex) {
      columnWidths.add(pageWidth * flex);
    }
    var xCursor = pagePadding;
    for (var i = 0; i < headers.length; i++) {
      final cellWidth = columnWidths[i];
      _paintCellText(
        canvas,
        text: headers[i],
        x: xCursor + 8,
        y: y + 10,
        maxWidth: cellWidth - 16,
        style: labelStyle.copyWith(
          color: const Color(0xFF1E6A2F),
          fontSize: 24,
        ),
      );
      xCursor += cellWidth;
      if (i < headers.length - 1) {
        canvas.drawLine(
          Offset(xCursor, y),
          Offset(xCursor, y + tableHeight),
          Paint()
            ..color = const Color(0xFF7B7B7B)
            ..strokeWidth = 1.2,
        );
      }
    }

    for (var row = 0; row < rows.length; row++) {
      final rowTop = y + tableHeaderHeight + (row * tableRowHeight);
      if (row > 0) {
        canvas.drawLine(
          Offset(pagePadding, rowTop),
          Offset(pagePadding + pageWidth, rowTop),
          Paint()
            ..color = const Color(0xFF9B9B9B)
            ..strokeWidth = 1,
        );
      }
      var rowX = pagePadding;
      for (var col = 0; col < headers.length; col++) {
        final cellWidth = columnWidths[col];
        _paintCellText(
          canvas,
          text: rows[row][col],
          x: rowX + 8,
          y: rowTop + 10,
          maxWidth: cellWidth - 16,
          style: smallStyle,
        );
        rowX += cellWidth;
      }
    }
    y += tableHeight + 18;

    final waterText =
        'Volumen de agua: ${recipe.waterVolumeLHa.toStringAsFixed(2)} L/ha';
    final hasNozzleTypes = recipe.nozzleTypes.trim().isNotEmpty;
    final waterTitleHeight = _measureTextHeight(
      waterText,
      labelStyle.copyWith(fontSize: 32),
      pageWidth - 28,
    );
    final nozzleHeight = hasNozzleTypes
        ? _measureInlineFieldsHeight(
            fields: [
              _InlineField(
                label: 'Tipo de pico/boquilla',
                value: recipe.nozzleTypes,
                highlightValue: true,
              ),
            ],
            labelStyle: smallStyle,
            highlightedValueStyle: smallHighlightedValueStyle,
            maxWidth: pageWidth - 28,
          )
        : 0.0;
    final waterHeight =
        waterTitleHeight + (hasNozzleTypes ? nozzleHeight + 14 : 0) + 20;
    final waterRect = Rect.fromLTWH(pagePadding, y, pageWidth, waterHeight);
    _drawBox(
      canvas,
      rect: waterRect,
      fillColor: const Color(0xFFF1F1F1),
      radius: 6,
    );
    final waterTitleBottom = _paintBlockText(
      canvas,
      text: waterText,
      x: pagePadding + 14,
      y: y + 10,
      maxWidth: pageWidth - 28,
      style: labelStyle.copyWith(fontSize: 32),
    );
    if (hasNozzleTypes) {
      _paintInlineFields(
        canvas,
        fields: [
          _InlineField(
            label: 'Tipo de pico/boquilla',
            value: recipe.nozzleTypes,
            highlightValue: true,
          ),
        ],
        x: pagePadding + 14,
        y: waterTitleBottom + 4,
        maxWidth: pageWidth - 28,
        labelStyle: smallStyle,
        highlightedValueStyle: smallHighlightedValueStyle,
      );
    }
    y += waterHeight + 18;

    y = _paintBlockText(
      canvas,
      text: 'Checklist / Orden de carga',
      x: pagePadding,
      y: y,
      maxWidth: pageWidth,
      style: sectionTitleStyle.copyWith(fontSize: 34),
    );
    y += 8;
    final mixOrderSteps = _resolveMixOrderSteps(recipe);
    if (mixOrderSteps.isEmpty) {
      y = _paintBlockText(
        canvas,
        text: 'Sin pasos definidos',
        x: pagePadding + 8,
        y: y,
        maxWidth: pageWidth - 8,
        style: bodyStyle,
      );
    } else {
      y = _paintBlockText(
        canvas,
        text: mixOrderSteps.join(' -> '),
        x: pagePadding + 8,
        y: y,
        maxWidth: pageWidth - 8,
        style: bodyStyle,
      );
    }
    y += 14;

    final warningsText = _safe(recipe.warnings);
    final notesText = _safe(recipe.notes);
    final safetyTitle = 'Seguridad y restricciones';
    final safetyBody1 = warningsText.isEmpty
        ? 'Sin advertencias.'
        : warningsText;
    final safetyBody2 = 'Observaciones: ${notesText.isEmpty ? '-' : notesText}';
    final safetyHeight =
        18 +
        _measureTextHeight(
          safetyTitle,
          sectionTitleStyle.copyWith(fontSize: 34),
          pageWidth - 28,
        ) +
        8 +
        _measureTextHeight(safetyBody1, bodyStyle, pageWidth - 28) +
        6 +
        _measureTextHeight(safetyBody2, bodyStyle, pageWidth - 28) +
        18;
    final safetyRect = Rect.fromLTWH(pagePadding, y, pageWidth, safetyHeight);
    _drawBox(
      canvas,
      rect: safetyRect,
      borderColor: const Color(0xFFFF7A21),
      borderWidth: 2,
      radius: 8,
    );
    var sy = y + 12;
    sy = _paintBlockText(
      canvas,
      text: safetyTitle,
      x: pagePadding + 14,
      y: sy,
      maxWidth: pageWidth - 28,
      style: sectionTitleStyle.copyWith(fontSize: 34),
    );
    sy += 4;
    sy = _paintBlockText(
      canvas,
      text: safetyBody1,
      x: pagePadding + 14,
      y: sy,
      maxWidth: pageWidth - 28,
      style: bodyStyle,
    );
    sy += 2;
    _paintBlockText(
      canvas,
      text: safetyBody2,
      x: pagePadding + 14,
      y: sy,
      maxWidth: pageWidth - 28,
      style: bodyStyle,
    );

    _paintBlockText(
      canvas,
      text: 'Documento generado por AgriPy',
      x: pagePadding,
      y: height - 40,
      maxWidth: pageWidth,
      style: smallStyle.copyWith(fontSize: 18, color: const Color(0xFF696969)),
    );

    final image = await recorder.endRecording().toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('No se pudo generar el PNG.');
    }
    return byteData.buffer.asUint8List();
  }

  Future<Uint8List> buildRequiredProductsPng({
    required String tenantName,
    required Recipe recipe,
    required RecipeEmissionData emission,
  }) async {
    const width = 1080;
    const pagePadding = 48.0;
    final rows = recipe.doseLines
        .map(
          (line) => _RequiredProductRow(
            productName: _safe(line.productName),
            unit: _safe(line.unit),
            totalRequired: _calculateTotalRequiredAmount(
              dosePerHa: line.dose,
              affectedAreaHa: emission.affectedAreaHa,
            ),
            perTank: _calculatePerTankAmount(
              dosePerHa: line.dose,
              tankCapacityLt: emission.tankCapacityLt,
              waterVolumeLHa: recipe.waterVolumeLHa,
            ),
          ),
        )
        .toList(growable: false);
    final computedHeight =
        300.0 + (rows.isEmpty ? 120.0 : rows.length * 72.0) + 120.0;
    final height = computedHeight.clamp(920.0, 2200.0).toInt();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.white,
    );

    final titleStyle = const TextStyle(
      fontSize: 50,
      fontWeight: FontWeight.w700,
      color: Color(0xFF1E6A2F),
    );
    final sectionTitleStyle = const TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w700,
      color: Color(0xFF1E6A2F),
    );
    final bodyStyle = const TextStyle(fontSize: 28, color: Color(0xFF202020));
    final smallStyle = const TextStyle(fontSize: 24, color: Color(0xFF303030));

    final pageWidth = width - (pagePadding * 2);
    var y = pagePadding;
    y = _paintBlockText(
      canvas,
      text: 'AGRIpy - Productos necesarios',
      x: pagePadding,
      y: y,
      maxWidth: pageWidth,
      style: titleStyle,
    );
    y += 14;

    final infoText =
        'Empresa: ${_safe(tenantName)}\n'
        'Campo: ${_safe(emission.farmName)}\n'
        'Lotes: ${_safe(emission.plotName)}\n'
        'Superficie afectada: ${emission.affectedAreaHa.toStringAsFixed(2)} ha\n'
        'Capacidad tanque: ${emission.tankCapacityLt.toStringAsFixed(2)} L';
    final infoHeight =
        _measureTextHeight(infoText, bodyStyle, pageWidth - 24) + 22;
    _drawBox(
      canvas,
      rect: Rect.fromLTWH(pagePadding, y, pageWidth, infoHeight),
      borderColor: const Color(0xFFB5B5B5),
      borderWidth: 1.6,
      radius: 8,
    );
    _paintBlockText(
      canvas,
      text: infoText,
      x: pagePadding + 12,
      y: y + 10,
      maxWidth: pageWidth - 24,
      style: bodyStyle,
    );
    y += infoHeight + 18;

    y = _paintBlockText(
      canvas,
      text: 'Productos',
      x: pagePadding,
      y: y,
      maxWidth: pageWidth,
      style: sectionTitleStyle,
    );
    y += 10;

    if (rows.isEmpty) {
      y = _paintBlockText(
        canvas,
        text: 'Sin lineas de mezcla.',
        x: pagePadding,
        y: y,
        maxWidth: pageWidth,
        style: bodyStyle,
      );
    } else {
      for (final row in rows) {
        y = _paintBlockText(
          canvas,
          text:
              '- ${row.productName}: ${row.totalRequired.toStringAsFixed(2)} ${row.unit} total '
              '(por tanque: ${row.perTank.toStringAsFixed(2)} ${row.unit})',
          x: pagePadding,
          y: y,
          maxWidth: pageWidth,
          style: bodyStyle,
        );
        y += 8;
      }
    }

    _paintBlockText(
      canvas,
      text: 'Documento generado por AgriPy',
      x: pagePadding,
      y: height - 40,
      maxWidth: pageWidth,
      style: smallStyle.copyWith(fontSize: 18, color: const Color(0xFF696969)),
    );

    final image = await recorder.endRecording().toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('No se pudo generar el PNG de productos.');
    }
    return byteData.buffer.asUint8List();
  }

  void _drawBox(
    Canvas canvas, {
    required Rect rect,
    Color? fillColor,
    Color borderColor = const Color(0x00000000),
    double borderWidth = 0,
    double radius = 0,
  }) {
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    if (fillColor != null) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill,
      );
    }
    if (borderWidth > 0) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = borderColor
          ..strokeWidth = borderWidth
          ..style = PaintingStyle.stroke,
      );
    }
  }

  double _paintBlockText(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required double maxWidth,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(x, y));
    return y + painter.height;
  }

  double _paintInlineFields(
    Canvas canvas, {
    required List<_InlineField> fields,
    required double x,
    required double y,
    required double maxWidth,
    required TextStyle labelStyle,
    required TextStyle highlightedValueStyle,
  }) {
    final painter = TextPainter(
      text: _buildInlineFieldsSpan(
        fields: fields,
        labelStyle: labelStyle,
        highlightedValueStyle: highlightedValueStyle,
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(x, y));
    return y + painter.height;
  }

  void _paintCellText(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required double maxWidth,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(x, y));
  }

  double _measureTextHeight(String text, TextStyle style, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  double _measureInlineFieldsHeight({
    required List<_InlineField> fields,
    required TextStyle labelStyle,
    required TextStyle highlightedValueStyle,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: _buildInlineFieldsSpan(
        fields: fields,
        labelStyle: labelStyle,
        highlightedValueStyle: highlightedValueStyle,
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  TextSpan _buildInlineFieldsSpan({
    required List<_InlineField> fields,
    required TextStyle labelStyle,
    required TextStyle highlightedValueStyle,
  }) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      spans.add(TextSpan(text: '${field.label}: ', style: labelStyle));
      spans.add(
        TextSpan(
          text: field.value,
          style: field.highlightValue ? highlightedValueStyle : labelStyle,
        ),
      );
      if (i < fields.length - 1) {
        spans.add(TextSpan(text: '    ', style: labelStyle));
      }
    }
    return TextSpan(children: spans);
  }

  String _safe(String? value) {
    final normalized = (value ?? '').trim();
    return normalized;
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
        .map((step) => _safe(step))
        .where((step) => step.isNotEmpty)
        .toList(growable: false);
    if (explicitSteps.isNotEmpty) {
      return explicitSteps;
    }
    return recipe.doseLines
        .map((line) => _safe(line.productName))
        .where((step) => step.isNotEmpty)
        .toList(growable: false);
  }
}

class _InlineField {
  const _InlineField({
    required this.label,
    required this.value,
    this.highlightValue = false,
  });

  final String label;
  final String value;
  final bool highlightValue;
}

class _RequiredProductRow {
  const _RequiredProductRow({
    required this.productName,
    required this.unit,
    required this.totalRequired,
    required this.perTank,
  });

  final String productName;
  final String unit;
  final double totalRequired;
  final double perTank;
}
