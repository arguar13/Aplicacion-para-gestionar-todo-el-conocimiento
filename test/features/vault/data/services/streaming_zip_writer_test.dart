import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/services/streaming_zip_writer.dart';

import '../../../../support/test_vault.dart';

/// El `.zip` que arma la copia de la bóveda (F12): cada entrada se escribe por
/// tandas y el resultado es un `.zip` común —lo lee `ZipDecoder`, y lo lee la
/// fusión, que además comprueba el CRC-32 de cada entrada—.
void main() {
  late Directory dir;
  late Directory work;
  late File zip;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sinapsis_zipwriter_');
    work = Directory(p.join(dir.path, 'trabajo'))..createSync();
    zip = File(p.join(dir.path, 'copia.zip'));
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  File write(String name, List<int> bytes) =>
      File(p.join(dir.path, name))..writeAsBytesSync(bytes);

  /// Arma el .zip con [entries] —nombre en el .zip → archivo— y lo lee de
  /// vuelta.
  Future<Archive> build(Map<String, File> entries) async {
    final writer = StreamingZipWriter(zip, workDirectory: work);
    for (final entry in entries.entries) {
      await writer.addFile(entry.value, entry.key);
    }
    await writer.close();
    return ZipDecoder().decodeBytes(zip.readAsBytesSync(), verify: true);
  }

  List<int> contentOf(Archive archive, String name) =>
      archive.files.firstWhere((f) => f.name == name).content as List<int>;

  ArchiveFile entryOf(Archive archive, String name) =>
      archive.files.firstWhere((f) => f.name == name);

  Uint8List randomBytes(int length, {int seed = 7}) {
    final random = Random(seed);
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  List<String> compressionTemporaries() => [
    for (final e in work.listSync())
      if (e.path.endsWith('.deflate')) e.path,
  ];

  group('lo que guarda', () {
    test(
      'un texto, comprimido, que ZipDecoder lee igual y verificado',
      () async {
        final text = List.generate(20000, (i) => 'línea número $i').join('\n');
        final file = write('nota.txt', utf8.encode(text));

        final archive = await build({'originales/nota.txt': file});

        expect(utf8.decode(contentOf(archive, 'originales/nota.txt')), text);
        final entry = entryOf(archive, 'originales/nota.txt');
        expect(entry.compression, CompressionType.deflate);
        // Comprimió de verdad: el .zip pesa una fracción del texto.
        expect(zip.lengthSync(), lessThan(file.lengthSync() ~/ 3));
        expect(entry.size, file.lengthSync());
      },
    );

    test('lo que ya viene comprimido se guarda sin comprimir', () async {
      final bytes = randomBytes(300000);
      final file = write('foto.PNG', bytes);

      final archive = await build({'originales/foto.PNG': file});

      final entry = entryOf(archive, 'originales/foto.PNG');
      expect(entry.compression, CompressionType.none);
      expect(contentOf(archive, 'originales/foto.PNG'), bytes);
    });

    test('un archivo vacío', () async {
      final archive = await build({'originales/vacio.txt': write('v.txt', [])});

      expect(contentOf(archive, 'originales/vacio.txt'), isEmpty);
    });

    test('nombres con subcarpetas, espacios y acentos', () async {
      const name = 'originales/doc 1/ñandú y más.txt';
      final archive = await build({name: write('x.txt', utf8.encode('hola'))});

      expect(archive.files.map((f) => f.name), [name]);
      expect(utf8.decode(contentOf(archive, name)), 'hola');
    });

    test(
      'un archivo de varios MB sale idéntico, con datos de todo tipo',
      () async {
        // La mitad compresible y la otra no: el compresor las alterna.
        final mixed = BytesBuilder()
          ..add(utf8.encode(List.generate(80000, (i) => 'palabra$i').join(' ')))
          ..add(randomBytes(2 * 1024 * 1024))
          ..add(Uint8List(1024 * 1024));
        final file = write('mixto.bin', mixed.toBytes());

        final archive = await build({'mixto.bin': file});

        expect(contentOf(archive, 'mixto.bin'), mixed.toBytes());
      },
    );

    test('varias entradas en un mismo .zip, cada una con su método', () async {
      final archive = await build({
        'a.txt': write('a.txt', utf8.encode('aaaa' * 500)),
        'b.jpg': write('b.jpg', randomBytes(5000, seed: 1)),
        'c.txt': write('c.txt', utf8.encode('cccc' * 500)),
      });

      expect(archive.files.map((f) => f.name), ['a.txt', 'b.jpg', 'c.txt']);
      expect(entryOf(archive, 'a.txt').compression, CompressionType.deflate);
      expect(entryOf(archive, 'b.jpg').compression, CompressionType.none);
      expect(utf8.decode(contentOf(archive, 'c.txt')), 'cccc' * 500);
    });
  });

  group('lo que deja', () {
    test('ningún temporal de compresión al terminar', () async {
      await build({
        'a.txt': write('a.txt', utf8.encode('aaaa' * 5000)),
        'b.txt': write('b.txt', utf8.encode('bbbb' * 5000)),
      });

      expect(compressionTemporaries(), isEmpty);
    });

    test('si un archivo no existe, falla sin dejar temporales', () async {
      final writer = StreamingZipWriter(zip, workDirectory: work);

      await expectLater(
        writer.addFile(File(p.join(dir.path, 'no-esta.txt')), 'x.txt'),
        throwsA(isA<FileSystemException>()),
      );
      await writer.close();

      expect(compressionTemporaries(), isEmpty);
    });
  });

  group('lo que la fusión hace con él', () {
    test('lo abre IncomingVault.openFile, que verifica cada CRC', () async {
      final database = write(
        'sinapsis.sqlite',
        await sqliteBytesAtVersion(AppDatabase.currentSchemaVersion),
      );
      final text = List.generate(5000, (i) => 'línea $i').join('\n');
      final original = write('a.txt', utf8.encode(text));
      final photo = write('f.jpg', randomBytes(20000));
      await build({
        'sinapsis.sqlite': database,
        'originales/a/a.txt': original,
        'originales/a/f.jpg': photo,
      });

      final incoming = await IncomingVault.openFile(zip);
      addTearDown(incoming.dispose);
      final out = Directory(p.join(dir.path, 'documentos'))..createSync();

      expect(incoming.schemaVersion, AppDatabase.currentSchemaVersion);
      expect(incoming.originalPaths.toSet(), {
        'originales/a/a.txt',
        'originales/a/f.jpg',
      });
      final copiedText = await incoming.copyOriginalTo(
        'originales/a/a.txt',
        out,
      );
      final copiedPhoto = await incoming.copyOriginalTo(
        'originales/a/f.jpg',
        out,
      );
      expect(copiedText!.readAsStringSync(), text);
      expect(copiedPhoto!.readAsBytesSync(), photo.readAsBytesSync());
    });
  });
}
