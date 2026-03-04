import 'dart:math';

import 'package:intl/intl.dart';

import '../data/recetario_repo.dart';
import '../domain/models.dart';
import 'recetario_pdf.dart';
import 'recetario_share.dart';

class EmitRecetarioUsecase {
  EmitRecetarioUsecase({
    required RecetarioRepo repo,
    required RecetarioPdfService pdfService,
    required RecetarioShareService shareService,
  }) : _repo = repo,
       _pdfService = pdfService,
       _shareService = shareService;

  final RecetarioRepo _repo;
  final RecetarioPdfService _pdfService;
  final RecetarioShareService _shareService;

  Future<ApplicationOrder> emitAndShare({
    required String tenantName,
    required Recipe recipe,
    required String farmName,
    required String plotName,
    required double areaHa,
    DateTime? plannedDate,
    required String engineerName,
    required String assignedToUid,
  }) async {
    final code = _generateOrderCode();
    final order = await _repo.createOrder(
      recipe: recipe,
      code: code,
      farmName: farmName,
      plotName: plotName,
      areaHa: areaHa,
      plannedDate: plannedDate,
      engineerName: engineerName,
      assignedToUid: assignedToUid,
    );

    final bytes = await _pdfService.buildProfessionalPdf(
      tenantName,
      recipe,
      order,
      'order:${order.id}',
    );
    final file = await _shareService.savePdfTemp(
      bytes,
      'recetario_${order.code}.pdf',
    );

    final text =
        'Recetario ${order.code} - ${order.plotName} - ${recipe.crop} ${recipe.stage}. '
        'Objetivo: ${recipe.objective}. Adjuntado PDF. Confirmar al terminar.';
    await _shareService.sharePdf(file, text);
    return order;
  }

  String _generateOrderCode() {
    final now = DateTime.now();
    final random = Random.secure().nextInt(999999).toString().padLeft(6, '0');
    final year = DateFormat('yyyy').format(now);
    return 'R-$year-$random';
  }
}
