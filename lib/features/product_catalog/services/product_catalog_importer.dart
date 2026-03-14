import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../domain/product_catalog_models.dart';

class ProductCatalogImportIssue {
  const ProductCatalogImportIssue({
    required this.rowNumber,
    required this.reason,
  });

  final int rowNumber;
  final String reason;
}

class ProductCatalogImportPreview {
  const ProductCatalogImportPreview({
    required this.products,
    required this.issues,
    required this.duplicateRows,
  });

  final List<MasterProductCatalogItem> products;
  final List<ProductCatalogImportIssue> issues;
  final int duplicateRows;

  bool get hasValidRows => products.isNotEmpty;
}

class ProductCatalogImporter {
  ProductCatalogImportPreview parseBytes({
    required Uint8List bytes,
    required String extension,
  }) {
    final normalizedExt = extension.trim().toLowerCase();
    if (normalizedExt == 'csv') {
      return _parseRows(_parseCsvRows(bytes));
    }
    if (normalizedExt == 'xlsx' || normalizedExt == 'xls') {
      return _parseRows(_parseExcelRows(bytes));
    }
    return const ProductCatalogImportPreview(
      products: <MasterProductCatalogItem>[],
      issues: <ProductCatalogImportIssue>[
        ProductCatalogImportIssue(
          rowNumber: 0,
          reason: 'Formato no soportado. Use CSV o Excel.',
        ),
      ],
      duplicateRows: 0,
    );
  }

  List<List<String>> _parseCsvRows(Uint8List bytes) {
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      text = latin1.decode(bytes, allowInvalid: true);
    }

    final rows = <List<String>>[];
    final row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    void finishField() {
      row.add(field.toString());
      field.clear();
    }

    void finishRow() {
      finishField();
      rows.add(List<String>.from(row));
      row.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final next = i + 1 < text.length ? text[i + 1] : null;
      if (char == '"') {
        if (inQuotes && next == '"') {
          field.write('"');
          i++;
          continue;
        }
        inQuotes = !inQuotes;
        continue;
      }
      if (!inQuotes && char == ',') {
        finishField();
        continue;
      }
      if (!inQuotes && (char == '\n' || char == '\r')) {
        if (char == '\r' && next == '\n') {
          i++;
        }
        finishRow();
        continue;
      }
      field.write(char);
    }

    if (field.isNotEmpty || row.isNotEmpty) {
      finishRow();
    }
    return rows;
  }

  List<List<String>> _parseExcelRows(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    Sheet? targetSheet;
    for (final entry in excel.sheets.entries) {
      if (entry.value.rows.isNotEmpty) {
        targetSheet = entry.value;
        break;
      }
    }
    if (targetSheet == null) {
      return const <List<String>>[];
    }

    final rows = <List<String>>[];
    for (final row in targetSheet.rows) {
      final values = row.map(_cellToString).toList(growable: false);
      rows.add(values);
    }
    return rows;
  }

  String _cellToString(Data? data) {
    try {
      final value = data?.value;
      if (value == null) {
        return '';
      }

      if (value is TextCellValue) {
        return value.value.toString();
      }
      if (value is IntCellValue) {
        return value.value.toString();
      }
      if (value is DoubleCellValue) {
        final number = value.value;
        if (number == number.roundToDouble()) {
          return number.toInt().toString();
        }
        return number.toString();
      }
      if (value is BoolCellValue) {
        return value.value ? 'true' : 'false';
      }
      if (value is DateCellValue) {
        return value.asDateTimeLocal().toIso8601String();
      }
      if (value is DateTimeCellValue) {
        return value.asDateTimeLocal().toIso8601String();
      }
      if (value is TimeCellValue) {
        return '${value.hour}:${value.minute}:${value.second}';
      }
      if (value is FormulaCellValue) {
        return value.formula;
      }

      return value.toString();
    } catch (_) {
      return '';
    }
  }

  ProductCatalogImportPreview _parseRows(List<List<String>> rawRows) {
    if (rawRows.isEmpty) {
      return const ProductCatalogImportPreview(
        products: <MasterProductCatalogItem>[],
        issues: <ProductCatalogImportIssue>[
          ProductCatalogImportIssue(
            rowNumber: 0,
            reason: 'El archivo no contiene datos.',
          ),
        ],
        duplicateRows: 0,
      );
    }

    final headerRowIndex = rawRows.indexWhere((row) => _rowHasData(row));
    if (headerRowIndex < 0) {
      return const ProductCatalogImportPreview(
        products: <MasterProductCatalogItem>[],
        issues: <ProductCatalogImportIssue>[
          ProductCatalogImportIssue(
            rowNumber: 0,
            reason: 'No se encontro encabezado valido.',
          ),
        ],
        duplicateRows: 0,
      );
    }

    final headerMap = _buildHeaderIndex(rawRows[headerRowIndex]);
    if (!headerMap.containsKey('commercialName')) {
      return const ProductCatalogImportPreview(
        products: <MasterProductCatalogItem>[],
        issues: <ProductCatalogImportIssue>[
          ProductCatalogImportIssue(
            rowNumber: 0,
            reason: 'Falta columna nombreComercial.',
          ),
        ],
        duplicateRows: 0,
      );
    }

    final issues = <ProductCatalogImportIssue>[];
    final products = <MasterProductCatalogItem>[];
    final seenKeys = <String>{};
    var duplicateRows = 0;

    for (var i = headerRowIndex + 1; i < rawRows.length; i++) {
      final rowNumber = i + 1;
      final row = rawRows[i];
      if (!_rowHasData(row)) {
        continue;
      }

      final commercialNameRaw = _getByHeader(
        row: row,
        headerMap: headerMap,
        canonicalKey: 'commercialName',
      );
      final commercialName = normalizeProductCommercialName(commercialNameRaw);
      if (commercialName.isEmpty) {
        issues.add(
          ProductCatalogImportIssue(
            rowNumber: rowNumber,
            reason: 'nombreComercial es obligatorio.',
          ),
        );
        continue;
      }

      final type = normalizeProductType(
        _getByHeader(row: row, headerMap: headerMap, canonicalKey: 'type'),
        supportValue: _getByHeader(
          row: row,
          headerMap: headerMap,
          canonicalKey: 'usage',
        ),
      );
      final formulation = normalizeProductFormulation(
        _getByHeader(
          row: row,
          headerMap: headerMap,
          canonicalKey: 'formulation',
        ),
        preferParenthesizedCode: true,
      );
      final inferredUnit = inferProductUnitFromFormulation(formulation) ?? '';
      final funcion = normalizeProductFunction(
        _getByHeader(row: row, headerMap: headerMap, canonicalKey: 'funcion'),
        type: type,
      );

      final item = MasterProductCatalogItem(
        commercialName: commercialName,
        activeIngredient: normalizeProductActiveIngredient(
          _getByHeader(
            row: row,
            headerMap: headerMap,
            canonicalKey: 'activeIngredient',
          ),
        ),
        unit: inferredUnit,
        type: type,
        formulation: formulation,
        funcion: funcion,
        active: true,
        source: 'import',
      ).normalized(allowEmptyUnit: true);

      final key = item.commercialNameKey?.trim() ?? '';
      if (key.isEmpty) {
        issues.add(
          ProductCatalogImportIssue(
            rowNumber: rowNumber,
            reason: 'No se pudo normalizar nombreComercial.',
          ),
        );
        continue;
      }
      if (seenKeys.contains(key)) {
        duplicateRows++;
        continue;
      }
      seenKeys.add(key);
      products.add(item);
    }

    return ProductCatalogImportPreview(
      products: List<MasterProductCatalogItem>.unmodifiable(products),
      issues: List<ProductCatalogImportIssue>.unmodifiable(issues),
      duplicateRows: duplicateRows,
    );
  }

  bool _rowHasData(List<String> row) {
    for (final value in row) {
      if (value.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Map<String, int> _buildHeaderIndex(List<String> row) {
    final map = <String, int>{};
    for (var i = 0; i < row.length; i++) {
      final canonical = _canonicalHeader(row[i]);
      if (canonical == null || canonical.isEmpty) {
        continue;
      }
      map.putIfAbsent(canonical, () => i);
    }
    return map;
  }

  String _getByHeader({
    required List<String> row,
    required Map<String, int> headerMap,
    required String canonicalKey,
  }) {
    final index = headerMap[canonicalKey];
    if (index == null || index < 0 || index >= row.length) {
      return '';
    }
    return row[index].trim();
  }

  String? _canonicalHeader(String rawHeader) {
    final normalized = _normalizeHeader(rawHeader);
    if (normalized.isEmpty) {
      return null;
    }
    const aliases = <String, String>{
      'nombrecomercial': 'commercialName',
      'nombre comercial': 'commercialName',
      'producto': 'commercialName',
      'producto comercial': 'commercialName',
      'comercial': 'commercialName',
      'commercialname': 'commercialName',
      'principioactivo': 'activeIngredient',
      'principio activo': 'activeIngredient',
      'p.activo': 'activeIngredient',
      'p. activo': 'activeIngredient',
      'p activo': 'activeIngredient',
      'ingredienteactivo': 'activeIngredient',
      'ingrediente activo': 'activeIngredient',
      'activeingredient': 'activeIngredient',
      'unidad': 'unit',
      'unit': 'unit',
      'tipo': 'type',
      'type': 'type',
      'formulacion': 'formulation',
      'formulacion quimica': 'formulation',
      'formulacion comercial': 'formulation',
      'formulation': 'formulation',
      'funcion': 'funcion',
      'function': 'funcion',
      'funcion del producto': 'funcion',
      'uso': 'usage',
      'use': 'usage',
    };
    return aliases[normalized];
  }

  String _normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
  }
}
