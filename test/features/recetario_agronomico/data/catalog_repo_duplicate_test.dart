import 'package:agripy/core/constants/modules.dart';
import 'package:agripy/core/services/access_controller.dart';
import 'package:agripy/core/services/tenant_path.dart';
import 'package:agripy/features/recetario_agronomico/data/catalog_repo.dart';
import 'package:agripy/features/recetario_agronomico/domain/catalog_models.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tenantId = 'tenant_test';
  const uid = 'uid_test';

  late FakeFirebaseFirestore firestore;
  late RecetarioCatalogRepo repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = RecetarioCatalogRepo(
      firestore: firestore,
      tenantId: tenantId,
      currentUid: uid,
      access: const TenantUserAccess(
        role: TenantRole.admin,
        activeModules: <String>[AppModules.recetarioAgronomico],
        status: 'active',
        displayName: 'Tester',
      ),
    );
  });

  test('createSupply guarda el primer insumo', () async {
    await repo.createSupply(_supply());

    final snapshot = await TenantPath.inputsRef(firestore, tenantId).get();
    expect(snapshot.docs, hasLength(1));
  });

  test('createSupply bloquea duplicado por clave normalizada', () async {
    await repo.createSupply(
      _supply(
        commercialName: ' Sterinn ',
        unit: 'L',
        type: ' Coadyuvante ',
        formulation: 'sl',
      ),
    );

    await expectLater(
      repo.createSupply(
        _supply(
          commercialName: 'STERINN',
          unit: 'Lt.',
          type: 'coadyuvante',
          formulation: 'SL',
        ),
      ),
      throwsA(
        isA<DuplicateSupplyException>().having(
          (error) => error.userMessage,
          'userMessage',
          contains('Ya existe un insumo'),
        ),
      ),
    );
  });

  test('updateSupply permite editar el mismo registro', () async {
    await repo.createSupply(
      _supply(
        commercialName: ' Sterinn ',
        unit: 'Lt.',
        type: 'coadyuvante',
        formulation: 'SL',
      ),
    );

    final id = await _findInputIdByCommercialName(
      firestore: firestore,
      tenantId: tenantId,
      commercialName: 'STERINN',
    );

    await expectLater(
      repo.updateSupply(
        _supply(
          id: id,
          commercialName: 'sterinn',
          unit: 'l',
          type: 'COADYUVANTE',
          formulation: 'sl',
        ),
      ),
      completes,
    );
  });

  test(
    'updateSupply bloquea duplicado al colisionar con otro registro',
    () async {
      await repo.createSupply(
        _supply(
          commercialName: 'STERINN',
          unit: 'Lt.',
          type: 'coadyuvante',
          formulation: 'SL',
        ),
      );
      await repo.createSupply(
        _supply(
          commercialName: 'TRIACANAZOLE',
          unit: 'Kg',
          type: 'fungicida',
          formulation: 'WG',
        ),
      );

      final secondId = await _findInputIdByCommercialName(
        firestore: firestore,
        tenantId: tenantId,
        commercialName: 'TRIACANAZOLE',
      );

      await expectLater(
        repo.updateSupply(
          _supply(
            id: secondId,
            commercialName: ' sterinn ',
            unit: 'l',
            type: 'COADYUVANTE',
            formulation: 'sl',
          ),
        ),
        throwsA(isA<DuplicateSupplyException>()),
      );
    },
  );
}

String _normalizeCommercialName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
}

Future<String> _findInputIdByCommercialName({
  required FakeFirebaseFirestore firestore,
  required String tenantId,
  required String commercialName,
}) async {
  final target = _normalizeCommercialName(commercialName);
  final snapshot = await TenantPath.inputsRef(firestore, tenantId).get();
  final doc = snapshot.docs.firstWhere(
    (item) => (item.data()['commercialName'] as String?) == target,
  );
  return doc.id;
}

SupplyRegistryItem _supply({
  String? id,
  String commercialName = 'STERINN',
  String? activeIngredient,
  String unit = 'Lt.',
  String type = 'coadyuvante',
  String formulation = 'SL',
  String funcion = 'penetrante',
}) {
  return SupplyRegistryItem(
    id: id,
    commercialName: commercialName,
    activeIngredient: activeIngredient,
    unit: unit,
    type: type,
    formulation: formulation,
    funcion: funcion,
  );
}
