import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/vault/data/merge/merge_gates.dart';

import '../../../../support/test_vault.dart';

/// Los archivos originales en la fusión (F11): se copian los que faltan y
/// alguna fila necesita; nunca se pisa uno que ya está; y si la fusión falla,
/// la carpeta de documentos queda como estaba.
void main() {
  late TestVault tel;
  late TestVault pc;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  /// Los nombres de todo lo que hay en la carpeta de documentos, con `/`.
  List<String> filesIn(TestVault vault) => [
    for (final e in vault.docs.listSync(recursive: true))
      if (e is File)
        p.posix.joinAll(p.split(p.relative(e.path, from: vault.docs.path))),
  ]..sort();

  /// Las entradas de un `.zip`, nombre → bytes.
  Map<String, List<int>> entriesOf(Uint8List zip) => {
    for (final f in ZipDecoder().decodeBytes(zip).files)
      if (f.isFile) f.name: f.content as List<int>,
  };

  group('los archivos que llegan', () {
    test('los de un elemento nuevo se copian, con su contenido', () async {
      pc.at(3);
      await pc.saveSource(
        'a',
        originalName: 'informe.pdf',
        originalContent: 'PDF de a',
      );

      final result = await tel.mergeFrom(pc);

      expect(result.filesCopied, 1);
      expect(result.filesCopiedBytes, 8);
      expect(result.filesMissing, 0);
      expect(tel.readOriginal('originales/a/informe.pdf'), 'PDF de a');
    });

    test(
      'la vista previa cuenta los mismos archivos que la fusión copia',
      () async {
        pc.at(3);
        await pc.saveSource(
          'a',
          originalName: 'uno.pdf',
          originalContent: 'x' * 30,
        );
        await pc.saveSource(
          'b',
          originalName: 'dos.mp3',
          originalContent: 'y' * 12,
        );

        final preview = await tel.backup.previewMerge(await pc.zip());
        final result = await tel.mergeFrom(pc);

        expect(preview.newFiles, result.filesCopied);
        expect(preview.newFilesBytes, result.filesCopiedBytes);
        expect(result.filesCopied, 2);
      },
    );

    test('el de un elemento que ya estaba y perdió el suyo también', () async {
      tel.at(1);
      await tel.saveSource('a', originalName: 'informe.pdf');
      pc.at(2);
      await pc.mergeFrom(tel);
      // pc lo tiene; en tel se perdió.
      File(
        p.join(tel.docs.path, 'originales', 'a', 'informe.pdf'),
      ).deleteSync();
      expect(tel.hasOriginal('originales/a/informe.pdf'), isFalse);

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.filesCopied, 1);
      expect(tel.hasOriginal('originales/a/informe.pdf'), isTrue);
    });

    test('fusionar otra vez no copia nada', () async {
      pc.at(3);
      await pc.saveSource('a', originalName: 'informe.pdf');
      await tel.mergeFrom(pc);

      final again = await tel.mergeFrom(pc);

      expect(again.changedNothing, isTrue);
      expect(again.filesCopied, 0);
    });
  });

  group('lo que no se copia', () {
    test('un archivo que ya está no se pisa, aunque sea distinto', () async {
      tel.at(1);
      await tel.saveSource(
        'a',
        originalName: 'informe.pdf',
        originalContent: 'lo de tel',
      );
      pc.at(2);
      await pc.saveSource(
        'a',
        originalName: 'informe.pdf',
        originalContent: 'lo de pc, más largo',
      );

      final result = await tel.mergeFrom(pc);

      expect(result.filesCopied, 0);
      expect(result.filesDiffering, 1);
      expect(tel.readOriginal('originales/a/informe.pdf'), 'lo de tel');
    });

    test(
      'uno que la copia dice tener y no trae se cuenta, y no rompe nada',
      () async {
        pc.at(3);
        await pc.saveSource('a', originalName: 'informe.pdf');
        File(
          p.join(pc.docs.path, 'originales', 'a', 'informe.pdf'),
        ).deleteSync();

        final result = await tel.mergeFrom(pc);

        expect(result.itemsAdded, 1);
        expect(result.filesCopied, 0);
        expect(result.filesMissing, 1);
      },
    );

    test('un archivo de la copia que ninguna fila usa no entra', () async {
      pc.at(3);
      await pc.saveSource('a');
      final zip = zipOf({
        ...entriesOf(await pc.zip()),
        'originales/huerfano/suelto.bin': [1, 2, 3],
      });

      final result = await tel.mergeZip(zip);

      expect(result.filesCopied, 0);
      expect(filesIn(tel), isEmpty);
    });

    test(
      'una ruta que sale de la carpeta de documentos no se escribe',
      () async {
        pc.at(3);
        await pc.saveSource('a', originalName: 'x.pdf');
        await pc.db.customStatement(
          "UPDATE source SET original_blob_path = 'originales/../../fuera.txt'",
        );
        final zip = zipOf({
          ...entriesOf(await pc.zip()),
          'originales/../../fuera.txt': [1, 2, 3],
        });
        final outside = File(p.join(tel.docs.parent.path, 'fuera.txt'));
        if (outside.existsSync()) outside.deleteSync();

        final result = await tel.mergeZip(zip);

        expect(outside.existsSync(), isFalse);
        expect(result.filesCopied, 0);
        expect(result.filesMissing, 1);
      },
    );
  });

  group('si la fusión falla', () {
    test('lo copiado se borra, y la carpeta queda como estaba', () async {
      tel.at(1);
      await tel.saveSource('mio', originalName: 'mio.pdf');
      final docsBefore = filesIn(tel);
      final countsBefore = await tel.counts();
      pc.at(3);
      await pc.saveSource('a', originalName: 'informe.pdf');

      await expectLater(
        tel.mergeFrom(pc, afterFiles: (_) async => throw StateError('falla')),
        throwsA(isA<StateError>()),
      );

      expect(filesIn(tel), docsBefore);
      expect(
        Directory(p.join(tel.docs.path, 'originales', 'a')).existsSync(),
        isFalse,
        reason: 'ni siquiera la carpeta vacía',
      );
      expect(await tel.counts(), countsBefore);
    });

    test(
      'una compuerta rota revierte la base y no llega a copiar archivos',
      () async {
        tel.at(1);
        await tel.saveSource('mio');
        final countsBefore = await tel.counts();
        pc.at(3);
        await pc.saveSource('a', originalName: 'informe.pdf');

        await expectLater(
          tel.mergeFrom(
            pc,
            afterWrites: (db) async {
              // Se sueltan las guardas y se borra un elemento de antes: lo que
              // la compuerta tiene que ver.
              await MergeGates(db).removeGuards();
              await db.customStatement("DELETE FROM item WHERE id = 'mio'");
            },
          ),
          throwsA(isA<VaultMergeGateException>()),
        );

        expect(filesIn(tel), isEmpty);
        expect(await tel.counts(), countsBefore);
        expect((await tel.entry('mio')).id, 'mio');
      },
    );
  });

  group('por el servicio', () {
    test(
      'mergeBackup fusiona sin reemplazar la base ni pedir reiniciar',
      () async {
        pc.at(3);
        await pc.saveSource('a', originalName: 'informe.pdf');
        tel.at(1);
        await tel.saveSource('mio');

        final result = await tel.backup.mergeBackup(await pc.zip());

        expect(result.itemsAdded, 1);
        expect(result.filesCopied, 1);
        // La misma conexión, con lo de antes y lo nuevo.
        expect(await tel.count('item'), 2);
        expect(tel.hasOriginal('originales/a/informe.pdf'), isTrue);
      },
    );

    test('una copia que no sirve se rechaza sin tocar nada', () async {
      tel.at(1);
      await tel.saveSource('mio');
      final before = await tel.counts();

      await expectLater(
        tel.backup.mergeBackup(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<Object>()),
      );

      expect(await tel.counts(), before);
    });
  });
}
