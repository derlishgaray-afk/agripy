import 'dart:math';

import 'package:intl/intl.dart';

import '../data/recetario_repo.dart';
import '../domain/models.dart';
import 'recetario_pdf.dart';
import 'recetario_png.dart';
import 'recetario_share.dart';

class EmitRecetarioUsecase {
  EmitRecetarioUsecase({
    required RecetarioRepo repo,
    required RecetarioPdfService pdfService,
    required RecetarioPngService pngService,
    required RecetarioShareService shareService,
  }) : _repo = repo,
       _pdfService = pdfService,
       _pngService = pngService,
       _shareService = shareService;

  final RecetarioRepo _repo;
  final RecetarioPdfService _pdfService;
  final RecetarioPngService _pngService;
  final RecetarioShareService _shareService;

  Future<ApplicationOrder> emitAndSharePdf({
    required String tenantName,
    required Recipe recipe,
    required String farmName,
    required String plotName,
    required double areaHa,
    required double affectedAreaHa,
    required double tankCapacityLt,
    DateTime? plannedDate,
    required String engineerName,
    required String operatorName,
    required String assignedToUid,
  }) async {
    final order = await _emitOrder(
      recipe: recipe,
      farmName: farmName,
      plotName: plotName,
      areaHa: areaHa,
      affectedAreaHa: affectedAreaHa,
      tankCapacityLt: tankCapacityLt,
      plannedDate: plannedDate,
      engineerName: engineerName,
      operatorName: operatorName,
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

  Future<ApplicationOrder> emitAndSharePng({
    required String tenantName,
    required Recipe recipe,
    required String farmName,
    required String plotName,
    required double areaHa,
    required double affectedAreaHa,
    required double tankCapacityLt,
    DateTime? plannedDate,
    required String engineerName,
    required String operatorName,
    required String assignedToUid,
  }) async {
    final order = await _emitOrder(
      recipe: recipe,
      farmName: farmName,
      plotName: plotName,
      areaHa: areaHa,
      affectedAreaHa: affectedAreaHa,
      tankCapacityLt: tankCapacityLt,
      plannedDate: plannedDate,
      engineerName: engineerName,
      operatorName: operatorName,
      assignedToUid: assignedToUid,
    );
    final emissionData = RecipeEmissionData.fromOrder(order);
    final bytes = await _pngService.buildEmissionPng(
      tenantName: tenantName,
      recipe: recipe.copyWith(lastEmission: emissionData),
      emission: emissionData,
    );
    final file = await _shareService.savePngTemp(
      bytes,
      'recetario_${order.code}.png',
    );

    final text =
        'Recetario ${order.code} - ${order.plotName} - ${recipe.crop} ${recipe.stage}. '
        'Objetivo: ${recipe.objective}. Adjuntado PNG. Confirmar al terminar.';
    await _shareService.sharePng(file, text);
    return order;
  }

  Future<ApplicationOrder> _emitOrder({
    required Recipe recipe,
    required String farmName,
    required String plotName,
    required double areaHa,
    required double affectedAreaHa,
    required double tankCapacityLt,
    DateTime? plannedDate,
    required String engineerName,
    required String operatorName,
    required String assignedToUid,
  }) async {
    final code = _generateOrderCode();
    return _repo.createOrder(
      recipe: recipe,
      code: code,
      farmName: farmName,
      plotName: plotName,
      areaHa: areaHa,
      affectedAreaHa: affectedAreaHa,
      tankCapacityLt: tankCapacityLt,
      plannedDate: plannedDate,
      engineerName: engineerName,
      operatorName: operatorName,
      assignedToUid: assignedToUid,
    );
  }

  String _generateOrderCode() {
    final now = DateTime.now();
    final random = Random.secure().nextInt(999999).toString().padLeft(6, '0');
    final year = DateFormat('yyyy').format(now);
    return 'R-$year-$random';
  }
}
