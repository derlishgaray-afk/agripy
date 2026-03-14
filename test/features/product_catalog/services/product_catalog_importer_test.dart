import 'dart:convert';
import 'dart:typed_data';

import 'package:agripy/features/product_catalog/domain/product_catalog_models.dart';
import 'package:agripy/features/product_catalog/services/product_catalog_importer.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductCatalogImporter', () {
    test(
      'normaliza filas CSV y omite duplicados obvios por nombre comercial',
      () {
        final importer = ProductCatalogImporter();
        const csv = '''
producto comercial,ingrediente activo,unidad,tipo,formulacion,funcion
Roundup,Glifosato,Lt,Herbicida,SL,
Aceite Mineral,,l,coadyuvante,aceite,adherente
  , , , , ,
Roundup,Glifosato,lt,herbicida,sl,
''';

        final preview = importer.parseBytes(
          bytes: Uint8List.fromList(utf8.encode(csv)),
          extension: 'csv',
        );

        expect(preview.products.length, 2);
        expect(preview.duplicateRows, 1);
        expect(preview.issues, isEmpty);

        final first = preview.products.first;
        expect(first.commercialName, 'ROUNDUP');
        expect(first.activeIngredient, 'Glifosato');
        expect(first.unit, 'Lt.');
        expect(first.type, 'herbicida');
        expect(first.formulation, 'SL');
        expect(first.funcion, isNull);

        final second = preview.products.last;
        expect(second.commercialName, 'ACEITE MINERAL');
        expect(second.unit, 'Lt.');
        expect(second.type, 'coadyuvante');
        expect(second.formulation, 'Aceite');
        expect(second.funcion, 'adherente');
      },
    );

    test(
      'mapea tipo desde Tipo/Uso y formulacion desde sigla en parentesis',
      () {
        final importer = ProductCatalogImporter();
        final bytes = _buildExcelBytes(<List<Object?>>[
          <Object?>[
            'Producto',
            'P.Activo',
            'Situacion',
            'Formulacion',
            'Mantenimiento',
            'Uso',
            'Tipo',
          ],
          <Object?>[
            'Prod Insect',
            'Imidacloprid',
            '',
            'POLVO MOJABLE (WP)',
            '',
            '',
            'INSECTICIDA',
          ],
          <Object?>[
            'Prod Uso Semicolon',
            '',
            '',
            'TABLETAS FUMIGANTES (DT)',
            '',
            'INSECTICIDA;NEMATICIDA',
            '',
          ],
          <Object?>[
            'Prod Uso Espacio',
            '',
            '',
            'SIN PARENTESIS',
            '',
            'FUNGICIDA BACTERICIDA',
            '',
          ],
          <Object?>[
            'Prod Uso Guion',
            '',
            '',
            'CONCENTRADO EMULSIONABLE (EC)',
            '',
            'COADYUVANTE-REGULADOR DE PH',
            '',
          ],
          <Object?>[
            'Prod Uso Plus',
            '',
            '',
            'POLVO SOLUBLE (SP)',
            '',
            'INSECTICIDA+FERTILIZANTE',
            '',
          ],
          <Object?>[
            'Prod Tipo Raro',
            '',
            '',
            'CEBO/ISCA (RB)',
            '',
            '',
            'LIBERADORES',
          ],
          <Object?>[
            'Prod Tipo Adherente',
            '',
            '',
            'SUSPENSION CONCENTRADA P/ TRAT. DE SEMILLA (FS)',
            '',
            '',
            'ADHERENTE',
          ],
          <Object?>[
            'Prod Form CS',
            '',
            '',
            'MICROCAPSULADO (CS)',
            '',
            '',
            'HERBICIDA',
          ],
          <Object?>[
            'Prod Form ME',
            '',
            '',
            'MICROEMULSION (ME)',
            '',
            '',
            'FUNGICIDA',
          ],
          <Object?>[
            'Prod Form GR',
            '',
            '',
            'GRANULADO (GR)',
            '',
            '',
            'INSECTICIDA',
          ],
          <Object?>[
            'Prod Form SG',
            '',
            '',
            'SOLUBLE GRANULADO (SG)',
            '',
            '',
            'FERTILIZANTE',
          ],
        ]);

        final preview = importer.parseBytes(bytes: bytes, extension: 'xlsx');
        expect(preview.issues, isEmpty);
        expect(preview.products.length, 11);

        final byCommercialName = <String, MasterProductCatalogItem>{
          for (final item in preview.products) item.commercialName: item,
        };

        expect(byCommercialName['PROD INSECT']?.type, 'insecticida');
        expect(byCommercialName['PROD INSECT']?.formulation, 'WP');
        expect(byCommercialName['PROD INSECT']?.unit, 'Kg.');
        expect(
          byCommercialName['PROD INSECT']?.activeIngredient,
          'Imidacloprid',
        );

        expect(byCommercialName['PROD USO SEMICOLON']?.type, 'insecticida');
        expect(byCommercialName['PROD USO SEMICOLON']?.formulation, 'DT');
        expect(byCommercialName['PROD USO SEMICOLON']?.unit, 'Kg.');

        expect(byCommercialName['PROD USO ESPACIO']?.type, 'fungicida');
        expect(byCommercialName['PROD USO ESPACIO']?.formulation, 'Otro');
        expect(byCommercialName['PROD USO ESPACIO']?.unit, '');

        expect(byCommercialName['PROD USO GUION']?.type, 'coadyuvante');
        expect(byCommercialName['PROD USO GUION']?.formulation, 'EC');
        expect(byCommercialName['PROD USO GUION']?.unit, 'Lt.');

        expect(byCommercialName['PROD USO PLUS']?.type, 'insecticida');
        expect(byCommercialName['PROD USO PLUS']?.formulation, 'SP');
        expect(byCommercialName['PROD USO PLUS']?.unit, 'Kg.');

        expect(byCommercialName['PROD TIPO RARO']?.type, 'Otros');
        expect(byCommercialName['PROD TIPO RARO']?.formulation, 'RB');
        expect(byCommercialName['PROD TIPO RARO']?.unit, 'Kg.');

        expect(byCommercialName['PROD TIPO ADHERENTE']?.type, 'Otros');
        expect(byCommercialName['PROD TIPO ADHERENTE']?.formulation, 'FS');
        expect(byCommercialName['PROD TIPO ADHERENTE']?.unit, 'Lt.');

        expect(byCommercialName['PROD FORM CS']?.formulation, 'CS');
        expect(byCommercialName['PROD FORM CS']?.unit, 'Lt.');
        expect(byCommercialName['PROD FORM ME']?.formulation, 'ME');
        expect(byCommercialName['PROD FORM ME']?.unit, 'Lt.');
        expect(byCommercialName['PROD FORM GR']?.formulation, 'GR');
        expect(byCommercialName['PROD FORM GR']?.unit, 'Kg.');
        expect(byCommercialName['PROD FORM SG']?.formulation, 'SG');
        expect(byCommercialName['PROD FORM SG']?.unit, 'Kg.');
      },
    );

    test('retorna error cuando formato no es soportado', () {
      final importer = ProductCatalogImporter();
      final preview = importer.parseBytes(
        bytes: Uint8List.fromList(utf8.encode('nombreComercial')),
        extension: 'txt',
      );
      expect(preview.products, isEmpty);
      expect(preview.issues, isNotEmpty);
    });

    test('no falla con celdas excel no textuales', () {
      final importer = ProductCatalogImporter();
      final bytes = _buildExcelBytes(<List<Object?>>[
        <Object?>['Producto', 'Formulacion', 'Tipo'],
        <Object?>[
          'Prod Fecha',
          const DateTimeCellValue(
            year: 2026,
            month: 3,
            day: 14,
            hour: 10,
            minute: 30,
          ),
          'HERBICIDA',
        ],
      ]);

      final preview = importer.parseBytes(bytes: bytes, extension: 'xlsx');
      expect(preview.products.length, 1);
      expect(preview.products.first.commercialName, 'PROD FECHA');
      expect(preview.products.first.type, 'herbicida');
      expect(preview.products.first.formulation, 'Otro');
      expect(preview.products.first.unit, '');
    });
  });
}

Uint8List _buildExcelBytes(List<List<Object?>> rows) {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
  final sheet = excel[sheetName];

  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
      final rawValue = row[columnIndex];
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(
          columnIndex: columnIndex,
          rowIndex: rowIndex,
        ),
      );
      if (rawValue == null) {
        cell.value = null;
      } else if (rawValue is CellValue) {
        cell.value = rawValue;
      } else {
        cell.value = TextCellValue(rawValue.toString());
      }
    }
  }

  final encoded = excel.encode();
  if (encoded == null) {
    throw StateError('No se pudo generar el archivo Excel de prueba.');
  }
  return Uint8List.fromList(encoded);
}
