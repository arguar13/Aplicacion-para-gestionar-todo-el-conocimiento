import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/services/local_vault_backup_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../../../support/rss_sampler.dart';

/// Armar la copia de una bóveda GRANDE (F12): ni la base ni los originales ni
/// lo comprimido pasan enteros por la memoria, y lo que sale se puede leer de
/// vuelta —con el CRC de cada entrada verificado— y trae todo.
void main() {
  test('armar la copia de una base de 160 MB no pasa por la memoria y sale '
      'completa', () async {
    final dir = await Directory.systemTemp.createTemp('sinapsis_backup_big_');
    addTearDown(() => dir.delete(recursive: true));
    final docs = Directory(p.join(dir.path, 'documentos'))..createSync();

    // Una base de Sinapsis con unos 160 MB de contenido incompresible, que
    // corre en su propio aislado, como la de la app.
    final dbFile = File(p.join(dir.path, 'sinapsis.sqlite'));
    final db = AppDatabase(NativeDatabase.createInBackground(dbFile));
    addTearDown(db.close);
    await db.customStatement(
      'CREATE TABLE relleno (id INTEGER PRIMARY KEY, v BLOB NOT NULL)',
    );
    await db.customStatement('''
      WITH RECURSIVE n(x) AS (
        SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 42000
      )
      INSERT INTO relleno (v) SELECT randomblob(3000) FROM n''');
    final dbBytes = dbFile.lengthSync();

    // Y unos originales: uno de texto grande, que se comprime, y un PDF.
    final text = List.generate(
      400000,
      (i) => 'renglón $i del original',
    ).join('\n');
    final originals = Directory(p.join(docs.path, 'originales', 'doc-1'))
      ..createSync(recursive: true);
    File(p.join(originals.path, 'texto.txt')).writeAsStringSync(text);
    File(
      p.join(originals.path, 'libro.pdf'),
    ).writeAsBytesSync(List.generate(4 * 1024 * 1024, (i) => (i * 31) & 0xff));

    final service = LocalVaultBackupService(
      database: db,
      documentsDirectory: () async => docs,
    );

    final sampler = await RssSampler.start();
    final built = await service.buildBackupFile();
    final growth = await sampler.stop();

    // La memoria creció una fracción de lo que pesa la base. No es
    // proporcional a ella —con una base de 82 MB creció 31 MB y con una de 329,
    // 39: la holgura de la recolección de basura y las tandas—; lo que se
    // descarta es lo que sí lo sería: lo comprimido de la base entera en
    // memoria (121 MB acá, y varias veces eso con las copias de `archive`).
    expect(
      growth,
      lessThan(dbBytes ~/ 2),
      reason:
          'creció ${growth ~/ 1048576} MB con una base de '
          '${dbBytes ~/ 1048576} MB',
    );
    expect(built.sizeBytes, File(built.path).lengthSync());
    // Y la copia sale completa: se lee de vuelta, con el CRC de cada entrada
    // verificado, y trae la base entera y los originales tal cual.
    final incoming = await IncomingVault.openFile(File(built.path));
    addTearDown(incoming.dispose);
    final copy = sqlite3.sqlite3.open(
      incoming.databaseFile.path,
      mode: sqlite3.OpenMode.readOnly,
    );
    addTearDown(copy.close);
    expect(copy.select('SELECT COUNT(*) AS n FROM relleno').single['n'], 42000);
    expect(incoming.originalPaths.toSet(), {
      'originales/doc-1/texto.txt',
      'originales/doc-1/libro.pdf',
    });
    final out = Directory(p.join(dir.path, 'restaurado'))..createSync();
    final copiedText = await incoming.copyOriginalTo(
      'originales/doc-1/texto.txt',
      out,
    );
    expect(copiedText!.readAsStringSync(), text);

    // Soltarla borra el .zip y su carpeta de trabajo —con el .zip ya suelto:
    // en Windows, uno abierto no se borra—.
    await incoming.dispose();
    await service.discardBackup(built);
    expect(File(built.path).existsSync(), isFalse);
    expect(File(built.path).parent.existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
