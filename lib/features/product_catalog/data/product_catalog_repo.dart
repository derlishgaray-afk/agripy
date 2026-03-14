import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/product_catalog_models.dart';

class ProductCatalogImportPersistResult {
  const ProductCatalogImportPersistResult({
    required this.created,
    required this.updated,
    required this.skipped,
  });

  final int created;
  final int updated;
  final int skipped;
}

class MasterProductCatalogRepo {
  MasterProductCatalogRepo(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _catalog =>
      _firestore.collection('master_product_catalog');

  Stream<List<MasterProductCatalogItem>> watchProducts() {
    return _catalog.snapshots().map((snapshot) {
      final items =
          snapshot.docs
              .map(
                (doc) =>
                    MasterProductCatalogItem.fromMap(doc.data(), id: doc.id),
              )
              .toList(growable: true)
            ..sort(
              (a, b) => a.commercialName.toLowerCase().compareTo(
                b.commercialName.toLowerCase(),
              ),
            );
      return List<MasterProductCatalogItem>.unmodifiable(items);
    });
  }

  Stream<List<MasterProductCatalogItem>> watchActiveProducts() {
    return _catalog.where('active', isEqualTo: true).snapshots().map((
      snapshot,
    ) {
      final items =
          snapshot.docs
              .map(
                (doc) =>
                    MasterProductCatalogItem.fromMap(doc.data(), id: doc.id),
              )
              .toList(growable: true)
            ..sort(
              (a, b) => a.commercialName.toLowerCase().compareTo(
                b.commercialName.toLowerCase(),
              ),
            );
      return List<MasterProductCatalogItem>.unmodifiable(items);
    });
  }

  Future<void> createProduct({
    required MasterProductCatalogItem item,
    required String actorUid,
  }) async {
    final now = DateTime.now();
    final normalized = item.normalized();
    final doc = _catalog.doc();
    await doc.set({
      ...normalized
          .copyWith(
            createdAt: now,
            updatedAt: now,
            source: normalized.source.isEmpty ? 'manual' : normalized.source,
          )
          .toMap(),
      'createdBy': actorUid.trim(),
      'updatedBy': actorUid.trim(),
    });
  }

  Future<void> updateProduct({
    required MasterProductCatalogItem item,
    required String actorUid,
  }) async {
    final id = item.id?.trim() ?? '';
    if (id.isEmpty) {
      throw StateError('Producto sin id.');
    }
    final normalized = item.normalized();
    await _catalog.doc(id).set({
      ...normalized.copyWith(updatedAt: DateTime.now()).toMap(),
      'updatedBy': actorUid.trim(),
    }, SetOptions(merge: true));
  }

  Future<void> setProductActive({
    required String productId,
    required bool active,
    required String actorUid,
  }) async {
    final id = productId.trim();
    if (id.isEmpty) {
      throw StateError('Producto sin id.');
    }
    await _catalog.doc(id).set({
      'active': active,
      'updatedAt': Timestamp.now(),
      'updatedBy': actorUid.trim(),
    }, SetOptions(merge: true));
  }

  Future<Set<String>> fetchExistingCommercialNameKeys() async {
    final snapshot = await _catalog.get();
    final keys = <String>{};
    for (final doc in snapshot.docs) {
      final item = MasterProductCatalogItem.fromMap(doc.data(), id: doc.id);
      final key = item.commercialNameKey?.trim() ?? '';
      if (key.isNotEmpty) {
        keys.add(key);
      }
    }
    return keys;
  }

  Future<ProductCatalogImportPersistResult> upsertImportedProducts({
    required List<MasterProductCatalogItem> products,
    required String actorUid,
    required String source,
  }) async {
    if (products.isEmpty) {
      return const ProductCatalogImportPersistResult(
        created: 0,
        updated: 0,
        skipped: 0,
      );
    }

    final normalizedActor = actorUid.trim();
    if (normalizedActor.isEmpty) {
      throw StateError('Actor invalido para importacion.');
    }

    final now = DateTime.now();
    final existingSnapshot = await _catalog.get();
    final keyToDocId = <String, String>{};
    for (final doc in existingSnapshot.docs) {
      final item = MasterProductCatalogItem.fromMap(doc.data(), id: doc.id);
      final key = item.commercialNameKey?.trim() ?? '';
      if (key.isEmpty) {
        continue;
      }
      keyToDocId[key] = doc.id;
    }

    var created = 0;
    var updated = 0;
    var skipped = 0;

    var batch = _firestore.batch();
    var pendingOps = 0;

    Future<void> commitBatchIfNeeded({required bool force}) async {
      if (!force && pendingOps < 350) {
        return;
      }
      if (pendingOps == 0) {
        return;
      }
      await batch.commit();
      batch = _firestore.batch();
      pendingOps = 0;
    }

    for (final rawItem in products) {
      final item = rawItem.normalized(allowEmptyUnit: true);
      final key = item.commercialNameKey?.trim() ?? '';
      if (key.isEmpty) {
        skipped++;
        continue;
      }

      final payload = {
        ...item
            .copyWith(active: true, source: source, updatedAt: now)
            .toMap(allowEmptyUnit: true),
        'updatedBy': normalizedActor,
      };

      final existingDocId = keyToDocId[key];
      if (existingDocId == null || existingDocId.isEmpty) {
        final doc = _catalog.doc();
        batch.set(doc, {
          ...payload,
          'createdAt': Timestamp.fromDate(now),
          'createdBy': normalizedActor,
        }, SetOptions(merge: true));
        keyToDocId[key] = doc.id;
        created++;
      } else {
        batch.set(
          _catalog.doc(existingDocId),
          payload,
          SetOptions(merge: true),
        );
        updated++;
      }
      pendingOps++;
      await commitBatchIfNeeded(force: false);
    }

    await commitBatchIfNeeded(force: true);
    return ProductCatalogImportPersistResult(
      created: created,
      updated: updated,
      skipped: skipped,
    );
  }
}
