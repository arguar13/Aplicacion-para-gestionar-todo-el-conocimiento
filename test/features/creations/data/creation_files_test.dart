import 'dart:convert';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/creations/data/creation_files.dart';

import '../../../support/test_vault.dart';

/// Qué archivos son de una creación (F43, decisión H): la regla en Dart —la
/// de quien borra y barre— y la de SQL —la de la unión de bóvedas y la de lo
/// que el barrido no borra— dicen lo mismo en los mismos casos.
void main() {
  late TestVault vault;

  setUp(() async => vault = await TestVault.create(deviceId: 'tel'));
  tearDown(() => vault.dispose());

  /// Cada id con las rutas que nombra su contenido y si son suyas.
  const cases = <String, Map<String, bool>>{
    'c1': {
      'originales/c1/ilustraciones/a.png': true,
      'originales/c1/a.png': true,
      'originales/c1/sub/b/c.png': true,
      'originales/c10/ilustraciones/a.png': false,
      'originales/c1': false,
      'originales/c1/': false,
      'originales/c1/../doc/libro.pdf': false,
      r'originales/c1/ilustraciones\..\x.png': false,
      'originales/doc/libro.pdf': false,
      'otra/c1/a.png': false,
      '': false,
    },
    // Un id que no es un solo tramo no es dueño de nada: con «.», la ruta
    // sería la carpeta de los originales entera.
    '.': {'originales/./doc/libro.pdf': false},
    'a/b': {'originales/a/b/x.png': false},
    '': {'originales//x.png': false},
  };

  Future<void> insert(String id, Iterable<String> paths) => vault.db
      .into(vault.db.studyCreations)
      .insert(
        StudyCreationsCompanion.insert(
          id: id,
          kind: 'infographic',
          scopeKind: 'all',
          contentJson: Value(
            jsonEncode({
              'blocks': [
                for (final path in paths) {'illustration_ref': path},
              ],
            }),
          ),
          languageCode: 'es',
          status: 'ready',
          createdAt: vault.now,
          updatedAt: vault.now,
        ),
      );

  test('en Dart', () {
    for (final MapEntry(key: id, value: paths) in cases.entries) {
      for (final MapEntry(key: path, value: own) in paths.entries) {
        expect(isCreationFile(id, path), own, reason: '$id: $path');
      }
    }
  });

  test('en SQL, la de todas y la de una sola', () async {
    for (final MapEntry(key: id, value: paths) in cases.entries) {
      await insert(id, paths.keys);
    }
    final all = await vault.db
        .customSelect(studyCreationFilesSql('main'))
        .get();
    expect(
      {for (final row in all) row.read<String>('path')},
      {
        for (final paths in cases.values)
          for (final MapEntry(key: path, value: own) in paths.entries)
            if (own) path,
      },
    );
    for (final MapEntry(key: id, value: paths) in cases.entries) {
      final one = await vault.db
          .customSelect(
            studyCreationFilesSql('main', oneCreation: true),
            variables: [Variable.withString(id)],
          )
          .get();
      expect(
        {for (final row in one) row.read<String>('path')},
        {
          for (final MapEntry(key: path, value: own) in paths.entries)
            if (own) path,
        },
        reason: id,
      );
    }
  });
}
