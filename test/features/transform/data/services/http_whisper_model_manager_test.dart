import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/features/transform/data/services/http_whisper_model_manager.dart';

class MockDio extends Mock implements Dio {}

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
    );

    // Los tres archivos declaran 10 bytes cada uno por `Content-Length`,
    // para que el progreso tenga un total con el que calcular una fracción.
    when(() => dio.head<void>(any())).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(),
        headers: Headers.fromMap({
          Headers.contentLengthHeader: ['10'],
        }),
      ),
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Directory modelDir() => Directory(
    '${tempDir.path}/modelos/whisper-base'.replaceAll(
      '/',
      Platform.pathSeparator,
    ),
  );

  test('un archivo que ya está completo de un intento anterior no se vuelve a '
      'pedir', () async {
    // Simula que "base-encoder.int8.onnx" ya había quedado bien la vez
    // pasada: el segundo intento no debería pedirlo de nuevo.
    final dir = modelDir()..createSync(recursive: true);
    File('${dir.path}/base-encoder.int8.onnx').writeAsStringSync('ya está');

    when(
      () => dio.download(
        any<String>(),
        any<dynamic>(),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      ),
    ).thenAnswer((invocation) async {
      final path = invocation.positionalArguments[1] as String;
      File(path).writeAsStringSync('contenido');
      return Response(requestOptions: RequestOptions());
    });

    await manager.download().drain<void>();

    // Solo los otros dos archivos se pidieron — el que ya estaba no.
    final requested = verify(
      () => dio.download(
        captureAny<String>(),
        any<dynamic>(),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      ),
    ).captured;
    expect(requested, hasLength(2));
    expect(
      requested.cast<String>().any((url) => url.contains('base-encoder')),
      isFalse,
    );
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
        final path = invocation.positionalArguments[1] as String;
        File(path).writeAsStringSync('contenido');
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

      await expectLater(manager.download(), emitsError(isA<DioException>()));
    },
  );
}
