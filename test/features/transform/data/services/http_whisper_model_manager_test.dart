import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/features/transform/data/services/http_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/data/services/whisper_model_spec.dart';

class MockDio extends Mock implements Dio {}

/// Lo que "publica el servidor" para cada archivo del modelo de prueba.
const _contents = {
  'encoder.onnx': 'el codificador',
  'decoder.onnx': 'el decodificador',
  'tokens.txt': 'las fichas',
};

WhisperModelFile _file(String name) => WhisperModelFile(
  name,
  bytes: utf8.encode(_contents[name]!).length,
  sha256: sha256.convert(utf8.encode(_contents[name]!)).toString(),
);

final _spec = WhisperModelSpec(
  baseUrl: 'https://modelos.test/fijado',
  folder: 'nuevo',
  encoder: _file('encoder.onnx'),
  decoder: _file('decoder.onnx'),
  tokens: _file('tokens.txt'),
  replaces: const ['viejo'],
);

void main() {
  late MockDio dio;
  late Directory tempDir;
  late HttpWhisperModelManager manager;

  setUp(() {
    dio = MockDio();
    tempDir = Directory.systemTemp.createTempSync('sinapsis_whisper_');
    manager = HttpWhisperModelManager(
      dio: dio,
      rootDirectory: () async => tempDir,
      spec: _spec,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Directory modelDir(String folder) => Directory(
    '${tempDir.path}${Platform.pathSeparator}modelos'
    '${Platform.pathSeparator}$folder',
  );

  /// El servidor contesta cada archivo con [serve] (por defecto, el
  /// contenido verificado).
  void serveFiles([String Function(String name)? serve]) {
    when(
      () => dio.download(
        any<String>(),
        any<dynamic>(),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      ),
    ).thenAnswer((invocation) async {
      final url = invocation.positionalArguments[0] as String;
      final name = url.split('/').last;
      final path = invocation.positionalArguments[1] as String;
      File(path).writeAsStringSync(serve?.call(name) ?? _contents[name]!);
      return Response(requestOptions: RequestOptions());
    });
  }

  List<String> requestedUrls() => verify(
    () => dio.download(
      captureAny<String>(),
      any<dynamic>(),
      onReceiveProgress: any(named: 'onReceiveProgress'),
    ),
  ).captured.cast<String>();

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
    verifyNever(() => dio.head<void>(any()));
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

  test(
    'un corte transitorio se reintenta solo, sin avisar de ningún error',
    () async {
      var attempts = 0;
      when(
        () => dio.download(
          any<String>(),
          any<dynamic>(),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        ),
      ).thenAnswer((invocation) async {
        attempts++;
        // Los dos primeros intentos de cada archivo fallan; el tercero pasa.
        if (attempts % 3 != 0) {
          throw DioException(requestOptions: RequestOptions());
        }
        final name = (invocation.positionalArguments[0] as String)
            .split('/')
            .last;
        final path = invocation.positionalArguments[1] as String;
        File(path).writeAsStringSync(_contents[name]!);
        return Response(requestOptions: RequestOptions());
      });

      final errors = <Object>[];
      await manager.download().handleError(errors.add).drain<void>();

      expect(errors, isEmpty);
      expect(await manager.isReady(), isTrue);
    },
  );

  test(
    'agotados los reintentos de un archivo, el error llega al stream',
    () async {
      when(
        () => dio.download(
          any<String>(),
          any<dynamic>(),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        ),
      ).thenThrow(DioException(requestOptions: RequestOptions()));

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
}
