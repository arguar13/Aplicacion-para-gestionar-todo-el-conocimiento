import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/storage/local_file_store.dart';
import 'package:sinapsis/features/attachments/data/services/zip_archive_expander.dart';
import 'package:sinapsis/features/attachments/domain/services/archive_expander.dart';

void main() {
  late Directory root;
  late LocalFileStore files;

  setUp(() {
    root = Directory.systemTemp.createTempSync('sinapsis_zip_');
    files = LocalFileStore(rootDirectory: () async => root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// Guarda un `.zip` con [entries] y devuelve su ruta relativa.
  Future<String> zipOf(
    Map<String, List<int>> entries, {
    bool stored = false,
    Uint8List Function(Uint8List zip)? tamper,
  }) async {
    final archive = Archive();
    for (final MapEntry(:key, :value) in entries.entries) {
      final file = ArchiveFile.bytes(key, value);
      if (stored) file.compression = CompressionType.none;
      archive.add(file);
    }
    var bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    if (tamper != null) bytes = tamper(bytes);
    return files.save(bytes: bytes, suggestedName: 'datos.zip', id: 'src');
  }

  List<String> filesOnDisk() => [
    for (final f in root.listSync(recursive: true).whereType<File>())
      f.path.substring(root.path.length + 1).replaceAll(r'\', '/'),
  ]..sort();

  ZipArchiveExpander expander({
    int maxEntries = 2000,
    int maxRatio = 200,
    int ratioFloorBytes = 16 * 1024 * 1024,
  }) => ZipArchiveExpander(
    files: files,
    maxEntries: maxEntries,
    maxRatio: maxRatio,
    ratioFloorBytes: ratioFloorBytes,
  );

  test('saca cada archivo a la carpeta, con su ruta como nombre', () async {
    final zip = await zipOf({
      'informe.pdf': utf8.encode('%PDF-1.4 hola'),
      'fotos/roma/coliseo.jpg': [0xFF, 0xD8, 0xFF, 1, 2, 3],
      'otras/coliseo.jpg': [0xFF, 0xD8, 0xFF, 9],
      'interior.zip': [0x50, 0x4B, 3, 4],
      '__MACOSX/._informe.pdf': [1],
      'fotos/.DS_Store': [1],
    });

    final out = await expander().expand(
      zip,
      storeId: 'src',
      folder: 'contenido',
      maxBytes: 1000,
    );

    expect(out.map((f) => (f.entryName, f.relativePath, f.bytes)), [
      ('informe.pdf', 'originales/src/contenido/informe.pdf', 13),
      ('fotos/roma/coliseo.jpg', 'originales/src/contenido/coliseo.jpg', 6),
      ('otras/coliseo.jpg', 'originales/src/contenido/coliseo-2.jpg', 4),
      // Un .zip adentro de otro se guarda cerrado.
      ('interior.zip', 'originales/src/contenido/interior.zip', 4),
    ]);
    expect(
      File(
        '${root.path}/originales/src/contenido/informe.pdf',
      ).readAsStringSync(),
      '%PDF-1.4 hola',
    );
  });

  test('las rutas hostiles no se sacan, y nada sale de la carpeta', () async {
    final zip = await zipOf({
      '../../databases/sinapsis.db': [6, 6, 6],
      '/etc/passwd': [6],
      r'..\..\windows.ini': [6],
      'C:/autoexec.bat': [6],
      'bien.txt': utf8.encode('ok'),
    });

    final out = await expander().expand(
      zip,
      storeId: 'src',
      folder: 'contenido',
      maxBytes: 1000,
    );

    expect(out.map((f) => f.entryName), ['bien.txt']);
    expect(filesOnDisk(), [
      'originales/src/contenido/bien.txt',
      'originales/src/datos.zip',
    ]);
  });

  test('isSafeEntryName', () {
    expect(isSafeEntryName('a/b/c.txt'), isTrue);
    for (final bad in [
      '',
      '/a',
      '../a',
      'a/../../b',
      'a/./b',
      'a//b',
      r'a\b',
      'c:/a',
      'a\u0000b',
    ]) {
      expect(isSafeEntryName(bad), isFalse, reason: bad);
    }
  });

  test('una bomba se corta mientras sale, y no deja nada', () async {
    final zip = await zipOf({
      'chico.txt': utf8.encode('hola'),
      'ceros.bin': Uint8List(512 * 1024),
    });

    await expectLater(
      expander(maxRatio: 10, ratioFloorBytes: 64 * 1024).expand(
        zip,
        storeId: 'src',
        folder: 'contenido',
        maxBytes: 100 * 1024 * 1024,
      ),
      throwsA(isA<UnsafeArchiveException>()),
    );
    expect(filesOnDisk(), ['originales/src/datos.zip']);
  });

  test('lo descomprimido no pasa del tope', () async {
    final zip = await zipOf({'grande.bin': Uint8List(10 * 1024)});

    await expectLater(
      expander().expand(
        zip,
        storeId: 'src',
        folder: 'contenido',
        maxBytes: 4 * 1024,
      ),
      throwsA(isA<UnsafeArchiveException>()),
    );
    expect(filesOnDisk(), ['originales/src/datos.zip']);
  });

  test('demasiadas entradas, o demasiado hondas, no se abren', () async {
    final many = await zipOf({
      for (var i = 0; i < 30; i++) '$i.txt': [i],
    });
    await expectLater(
      expander(
        maxEntries: 20,
      ).expand(many, storeId: 'src', folder: 'contenido', maxBytes: 1000),
      throwsA(isA<UnsafeArchiveException>()),
    );

    final deep = await zipOf({
      '${List.filled(40, 'd').join('/')}/x.txt': [1],
    });
    await expectLater(
      expander().expand(
        deep,
        storeId: 'src',
        folder: 'contenido',
        maxBytes: 1000,
      ),
      throwsA(isA<UnsafeArchiveException>()),
    );
  });

  test('una entrada alterada no pasa el CRC', () async {
    final text = utf8.encode('contenido original del archivo');
    final zip = await zipOf(
      {'a.txt': text},
      stored: true,
      tamper: (bytes) {
        // El contenido va tal cual en un zip sin compresión: se le cambia
        // una letra.
        final at = _indexOf(bytes, text);
        return Uint8List.fromList(bytes)..[at] ^= 0x20;
      },
    );

    await expectLater(
      expander().expand(
        zip,
        storeId: 'src',
        folder: 'contenido',
        maxBytes: 1000,
      ),
      throwsA(isA<UnsafeArchiveException>()),
    );
    expect(filesOnDisk(), ['originales/src/datos.zip']);
  });

  test('algo que no es un zip', () async {
    final notZip = await files.save(
      bytes: Uint8List.fromList(utf8.encode('no soy un zip')),
      suggestedName: 'falso.zip',
      id: 'src',
    );
    await expectLater(
      expander().expand(
        notZip,
        storeId: 'src',
        folder: 'contenido',
        maxBytes: 1000,
      ),
      throwsA(isA<UnsafeArchiveException>()),
    );
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  throw StateError('no está');
}
