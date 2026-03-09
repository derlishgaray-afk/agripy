import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/services/tenant_path.dart';

class RecetarioCodeService {
  RecetarioCodeService({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  Future<String> generateNextRecetarioCode({
    required String tenantId,
    DateTime? issuedAt,
  }) async {
    return _firestore.runTransaction((transaction) {
      return generateNextRecetarioCodeInTransaction(
        tenantId: tenantId,
        transaction: transaction,
        issuedAt: issuedAt,
      );
    });
  }

  Future<String> generateNextRecetarioCodeInTransaction({
    required String tenantId,
    required Transaction transaction,
    DateTime? issuedAt,
  }) async {
    final effectiveIssuedAt = issuedAt ?? DateTime.now();
    final year = effectiveIssuedAt.year;
    final counterRef = TenantPath.counterRef(
      _firestore,
      tenantId,
      counterDocIdForYear(year),
    );
    final counterSnapshot = await transaction.get(counterRef);
    final data = counterSnapshot.data();

    if (data == null) {
      transaction.set(counterRef, {
        'nextNumber': 2,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return formatRecetarioCode(year, 1);
    }

    final currentNextNumber = _parseNextNumber(data['nextNumber']);
    final numberToUse = currentNextNumber <= 0 ? 1 : currentNextNumber;
    transaction.set(counterRef, {
      'nextNumber': numberToUse + 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return formatRecetarioCode(year, numberToUse);
  }

  static String counterDocIdForYear(int year) => 'recetario_$year';

  static String formatRecetarioCode(int year, int number) {
    return 'R-$year-${number.toString().padLeft(6, '0')}';
  }

  int _parseNextNumber(dynamic rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    if (rawValue is String) {
      return int.tryParse(rawValue) ?? 1;
    }
    return 1;
  }
}
