import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/features/transform/data/services/http_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/data/services/whisper_model_spec.dart';

import '../../../../support/fake_file_server.dart';

/// Lo que "publica el servidor" para cada archivo del modelo de prueba.
const _contents = {
  'encoder.onnx': 'el codificador',
  'decoder.onnx': 'el decodificador',
  'tokens.txt': 'las fichas',
};

const _baseUrl = 'https://modelos.test/fijado';
const _encoderUrl = '$_baseUrl/encoder.onnx';

WhisperModelFile _file(String name) => WhisperModelFile(
  name,
  bytes: utf8.encode(_contents[name]!).length,
  sha256: sha256.convert(utf8.encode(_contents[name]!)).toString(),
);

final _spec = WhisperModelSpec(
  baseUrl: _baseUrl,
  folder: 'nuevo',
  encoder: _file('encoder.onnx'),
  decoder: _file('decoder.onnx'),
  tokens: _file('tokens.txt'),
  replaces: const ['viejo'],
);

void main() {
  late FakeFileServer server;
  late Directory tempDir;
  late HttpWhisperModelManager manager;

  /// El servidor sirve cada archivo con [serve] (por defecto, el contenido
  /// verificado).
  void serveFiles([String Function(String name)? serve]) {
    server.files
      ..clear()
      ..addAll({
        for (final name in _contents.keys)
          '$_baseUrl/$name': utf8.encode(serve?.call(name) ?? _contents[name]!),
      });
  }

  setUp(() {
    server = FakeFileServer({});
    tempDir = Directory.systemTemp.createTempSync('sinapsis_whisper_');
    manager = HttpWhisperModelManager(
      transfer: InAppModelFileTransfer(
        dio: Dio()..httpClientAdapter = server,
        retryDelay: (_) => Duration.zero,
      ),
      rootDirectory: () async => tempDir,
      spec: _spec,
    );
  });

  tearDown(() {
    server.close();
    tempDir.deleteSync(recursive: true);
  });

  Directory modelDir(String folder) => Directory(
    '${tempDir.path}${Platform.pathSeparator}modelos'
    '${Platform.pathSeparator}$folder',
  );

  List<String> requestedUrls() => [
    for (final request in server.requests) request.uri.toString(),
  ];

  test('baja los tres archivos de la versión fijada y queda listo', () async {
    serveFiles();

    await manager.download().drain<void>();

    expect(await manager.isReady(), isTrue);
    expect(
      requestedUrls(),
      everyElement(startsWith('https://modelos.test/fijado/')),
    );
  });

  test('el tamaño se sabe sin preguntarle nada al servidor', () async {
    expect(
      await manager.downloadSizeInBytes(),
      _contents.values
          .map((c) => utf8.encode(c).length)
          .reduce((a, b) => a + b),
    );
    expect(server.requests, isEmpty);
  });

  test('un archivo que llega distinto de lo verificado se descarta: la '
      'descarga falla y no queda nada que parezca listo', () async {
    // Mismo tamaño, otro contenido: solo la huella lo delata.
    serveFiles(
      (name) => name == 'decoder.onnx' ? 'el decodificadoR' : _contents[name]!,
    );

    await expectLater(
      manager.download(),
      emitsThrough(emitsError(isA<WhisperModelIntegrityException>())),
    );

    expect(await manager.isReady(), isFalse);
    final left = modelDir(
      'nuevo',
    ).listSync().map((e) => e.uri.pathSegments.last);
    expect(left, isNot(contains('decoder.onnx')));
    expect(left.where((n) => n.contains('descargando')), isEmpty);
  });

  test(
    'el modelo anterior se borra recién cuando el nuevo quedó entero',
    () async {
      final old = modelDir('viejo')..createSync(recursive: true);
      File(
        '${old.path}${Platform.pathSeparator}small.onnx',
      ).writeAsStringSync('x');
      serveFiles();

      await manager.download().drain<void>();

      expect(old.existsSync(), isFalse);
    },
  );

  test('si la descarga falla, el modelo anterior no se toca', () async {
    final old = modelDir('viejo')..createSync(recursive: true);
    serveFiles((name) => 'otra cosa');

    await manager.download().handleError((_) {}).drain<void>();

    expect(old.existsSync(), isTrue);
  });

  test('un archivo a medias —de otro tamaño— no cuenta como bajado', () async {
    final dir = modelDir('nuevo')..createSync(recursive: true);
    for (final name in _contents.keys) {
      File('${dir.path}${Platform.pathSeparator}$name').writeAsStringSync(
        name == 'encoder.onnx' ? 'el codifi' : _contents[name]!,
      );
    }

    expect(await manager.isReady(), isFalse);
  });

  test('un archivo que ya está completo de un intento anterior no se vuelve '
      'a pedir', () async {
    final dir = modelDir('nuevo')..createSync(recursive: true);
    File(
      '${dir.path}${Platform.pathSeparator}encoder.onnx',
    ).writeAsStringSync(_contents['encoder.onnx']!);
    serveFiles();

    await manager.download().drain<void>();

    final requested = requestedUrls();
    expect(requested, hasLength(2));
    expect(requested.any((url) => url.endsWith('encoder.onnx')), isFalse);
  });

  test('un corte transitorio se reintenta solo, sin avisar de ningún '
      'error', () async {
    serveFiles();
    server.misbehaviors.addAll([
      const Misbehavior.status(503),
      const Misbehavior.status(503),
    ]);

    final errors = <Object>[];
    await manager.download().handleError(errors.add).drain<void>();

    expect(errors, isEmpty);
    expect(await manager.isReady(), isTrue);
  });

  test('un archivo cortado a mitad se retoma desde donde quedó, no desde '
      'cero', () async {
    serveFiles();
    server.misbehaviorsByUrl[_encoderUrl] = [const Misbehavior.cut(6)];

    await manager.download().drain<void>();

    expect(await manager.isReady(), isTrue);
    expect(server.rangesFor(_encoderUrl), [null, 'bytes=6-']);
  });

  test('lo que quedó a medias de una sesión anterior se retoma por '
      'rango', () async {
    serveFiles();
    final dir = modelDir('nuevo')..createSync(recursive: true);
    File(
      '${dir.path}${Platform.pathSeparator}.encoder.onnx.descargando',
    ).writeAsStringSync(_contents['encoder.onnx']!.substring(0, 4));

    await manager.download().drain<void>();

    expect(await manager.isReady(), isTrue);
    expect(server.rangesFor(_encoderUrl), ['bytes=4-']);
  });

  test('lo que quedó a medias y se completa con bytes que no son los '
      'verificados se descarta: la huella lo delata', () async {
    serveFiles();
    final dir = modelDir('nuevo')..createSync(recursive: true);
    File(
      '${dir.path}${Platform.pathSeparator}.encoder.onnx.descargando',
    ).writeAsStringSync('XXXX');

    await expectLater(
      manager.download(),
      emitsThrough(emitsError(isA<WhisperModelIntegrityException>())),
    );
    final left = dir.listSync().map((e) => e.uri.pathSegments.last);
    expect(left.where((n) => n.contains('encoder')), isEmpty);
  });

  test(
    'agotados los reintentos de un archivo, el error llega al stream',
    () async {
      serveFiles();
      server.misbehaviorsByUrl[_encoderUrl] = List.filled(
        8,
        const Misbehavior.status(500),
      );

      await expectLater(
        manager.download(),
        emitsThrough(emitsError(isA<DioException>())),
      );
    },
  );

  test('la versión real: fijada a un commit, con las huellas medidas', () {
    const real = WhisperModelSpec.smallWithAttention;

    expect(real.baseUrl, contains('/resolve/9a896a02'));
    expect(real.baseUrl, isNot(contains('/main')));
    expect(real.totalBytes, 375744699);
    expect(real.replaces, ['whisper-small']);
  });

  test('pide los tres archivos a la vez: con el gestor del sistema siguen '
      'con la app cerrada', () async {
    serveFiles();
    for (final name in _contents.keys) {
      server.misbehaviorsByUrl['$_baseUrl/$name'] = [const Misbehavior.stall()];
    }

    final done = manager.download().drain<void>().catchError((_) {});
    // Hasta que llegan los tres pedidos: antes hay disco de por medio.
    for (var i = 0; i < 200 && server.requests.length < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(requestedUrls().toSet(), {
      for (final name in _contents.keys) '$_baseUrl/$name',
    });
    expect(await manager.isDownloading(), isTrue);
    await manager.cancelDownload();
    await done;
    expect(await manager.isDownloading(), isFalse);
    expect(await manager.isReady(), isFalse);
  });

  test('cancelar a medias borra también los archivos que ya habían '
      'terminado: sin los tres el modelo no sirve', () async {
    serveFiles();
    for (final name in ['encoder.onnx', 'decoder.onnx']) {
      server.misbehaviorsByUrl['$_baseUrl/$name'] = [const Misbehavior.stall()];
    }
    final tokens = File(
      '${modelDir('nuevo').path}${Platform.pathSeparator}tokens.txt',
    );

    final done = manager.download().drain<void>().catchError((_) {});
    for (var i = 0; i < 200 && !tokens.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(tokens.existsSync(), isTrue);

    await manager.cancelDownload();
    await done;

    expect(tokens.existsSync(), isFalse);
    expect(modelDir('nuevo').listSync(), isEmpty);
  });

  test('cancelar con el modelo ya entero no borra nada', () async {
    serveFiles();
    await manager.download().drain<void>();

    await manager.cancelDownload();

    expect(await manager.isReady(), isTrue);
  });

  // Antes de F29 el modelo se bajaba a la carpeta interna de la app; con el
  // gestor del sistema se baja a otra, donde el sistema puede escribir.
  group('lo bajado en la carpeta de antes (F29)', () {
    late Directory earlierDir;
    late HttpWhisperModelManager moved;

    Directory earlierModelDir(String folder) => Directory(
      '${earlierDir.path}${Platform.pathSeparator}modelos'
      '${Platform.pathSeparator}$folder',
    );

    setUp(() {
      earlierDir = Directory.systemTemp.createTempSync(
        'sinapsis_whisper_antes_',
      );
      moved = HttpWhisperModelManager(
        transfer: InAppModelFileTransfer(
          dio: Dio()..httpClientAdapter = server,
          retryDelay: (_) => Duration.zero,
        ),
        rootDirectory: () async => tempDir,
        earlierRoots: [() async => earlierDir],
        spec: _spec,
      );
    });

    tearDown(() => earlierDir.deleteSync(recursive: true));

    test(
      'entero ahí, está listo y se usa donde está, sin bajar nada',
      () async {
        final dir = earlierModelDir('nuevo')..createSync(recursive: true);
        for (final entry in _contents.entries) {
          File(
            '${dir.path}${Platform.pathSeparator}${entry.key}',
          ).writeAsStringSync(entry.value);
        }

        expect(await moved.isReady(), isTrue);
        expect((await moved.paths()).encoder, startsWith(earlierDir.path));
        await moved.download().drain<void>();
        expect(server.requests, isEmpty);
      },
    );

    test('a medias ahí no se sigue: se borra, y se baja entero en la carpeta '
        'nueva', () async {
      serveFiles();
      final dir = earlierModelDir('nuevo')..createSync(recursive: true);
      final old = File(
        '${dir.path}${Platform.pathSeparator}.encoder.onnx.descargando',
      )..writeAsStringSync('el c');

      await moved.download().drain<void>();

      expect(await moved.isReady(), isTrue);
      expect((await moved.paths()).encoder, startsWith(tempDir.path));
      expect(old.existsSync(), isFalse);
      expect(dir.existsSync(), isFalse);
    });
  });
}
