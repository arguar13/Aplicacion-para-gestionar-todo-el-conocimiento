import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/schema_too_old_exception.dart';

/// Desde F10 la actualización más antigua que se soporta es la v15. Una base
/// anterior se corta con un mensaje que dice qué hacer, antes de tocar nada.
void main() {
  /// Una base que dice ser de la versión [version], sin ninguna tabla: alcanza
  /// para llegar a `onUpgrade`, que es lo único que decide.
  AppDatabase databaseAtVersion(int version) => AppDatabase(
    NativeDatabase.memory(
      setup: (raw) => raw.execute('PRAGMA user_version = $version'),
    ),
  );

  test('la versión mínima es la 15', () {
    expect(AppDatabase.minimumUpgradableSchemaVersion, 15);
  });

  for (final version in [1, 8, 14]) {
    test('una base del esquema v$version no se actualiza: dice cuál es la '
        'versión mínima y qué hacer', () async {
      final db = databaseAtVersion(version);
      addTearDown(db.close);

      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<SchemaTooOldException>()
              .having((e) => e.from, 'from', version)
              .having((e) => e.minimum, 'minimum', 15)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('v$version'),
                  contains('v15'),
                  contains('No se modificó nada'),
                ),
              ),
        ),
      );
    });
  }

  test('una base de la versión mínima sí se abre', () async {
    // Sin tablas: `onUpgrade` no falla por la versión, sino más adelante por lo
    // que le falta a esta base vacía. Lo que se comprueba es que NO es la
    // excepción de versión demasiado vieja.
    final db = databaseAtVersion(AppDatabase.minimumUpgradableSchemaVersion);
    addTearDown(db.close);

    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(isNot(isA<SchemaTooOldException>())),
    );
  });
}
