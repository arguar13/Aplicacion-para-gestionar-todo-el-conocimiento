import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';
import 'package:sinapsis/features/relations/data/services/gemma_embedding_model_manager.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';

import '../../../../support/fake_gemma_runtime.dart';

class MockHttpGemmaModelDownloader extends Mock
    implements HttpGemmaModelDownloader {}

/// El modelo real no corre en una prueba; `flutter_gemma` va con
/// [FakeGemmaRuntime], que arranca sin nada activo como el paquete al
/// reabrir la app. Se prueba cómo se combina el progreso de las dos
/// descargas, cómo se traduce un error de cualquiera de las dos, y que un
/// modelo ya bajado se reconozca sin volver a bajarlo.
void main() {
  late MockHttpGemmaModelDownloader downloader;
  late FakeGemmaRuntime runtime;
  late GemmaEmbeddingModelManager manager;

  setUp(() {
    downloader = MockHttpGemmaModelDownloader();
    runtime = FakeGemmaRuntime();
    manager = GemmaEmbeddingModelManager(
      downloader: downloader,
      runtime: runtime,
    );
    when(() => downloader.targetFile(any())).thenAnswer(
      (invocation) async => File(invocation.positionalArguments[0] as String),
    );
    when(
      () => downloader.isComplete(
        any(),
        publishedBytes: any(named: 'publishedBytes'),
      ),
    ).thenAnswer((_) async => false);
  });

  test('downloadSizeInBytes: sin dato de antemano, es null', () async {
    expect(await manager.downloadSizeInBytes(), isNull);
  });

  test('isReady: sin ningún modelo activo ni sus archivos, false', () async {
    expect(await manager.isReady(), isFalse);
    expect(runtime.embedderInstalls, isEmpty);
  });

  test('isReady: con los dos archivos enteros de una sesión anterior, los '
      'registra y está listo sin bajar nada', () async {
    when(
      () => downloader.isComplete(
        any(),
        publishedBytes: any(named: 'publishedBytes'),
      ),
    ).thenAnswer((_) async => true);

    expect(await manager.isReady(), isTrue);
    expect(runtime.embedderInstalls, [
      (
        'embeddinggemma-300M_seq1024_mixed-precision.tflite',
        'embeddinggemma-sentencepiece.model',
      ),
    ]);
  });

  test('isReady: con solo el modelo entero y el tokenizador a medias, no '
      'está listo', () async {
    when(
      () => downloader.isComplete(
        'embeddinggemma-sentencepiece.model',
        publishedBytes: any(named: 'publishedBytes'),
      ),
    ).thenAnswer((_) async => false);
    when(
      () => downloader.isComplete(
        'embeddinggemma-300M_seq1024_mixed-precision.tflite',
        publishedBytes: any(named: 'publishedBytes'),
      ),
    ).thenAnswer((_) async => true);

    expect(await manager.isReady(), isFalse);
    expect(runtime.embedderInstalls, isEmpty);
  });

  test('isReady: los tamaños publicados reconocen lo bajado antes de la '
      'marca de terminado', () async {
    await manager.isReady();

    verify(
      () => downloader.isComplete(
        'embeddinggemma-300M_seq1024_mixed-precision.tflite',
        publishedBytes: 183329528,
      ),
    ).called(1);
  });

  test('el progreso combina las dos descargas: 0-90% el modelo, 90-100% el '
      'tokenizador', () async {
    when(
      () => downloader.download(
        url: any(named: 'url'),
        fileName: any(named: 'fileName'),
        token: any(named: 'token'),
        publishedBytes: any(named: 'publishedBytes'),
      ),
    ).thenAnswer((invocation) {
      final fileName = invocation.namedArguments[#fileName] as String;
      return fileName.contains('sentencepiece')
          ? Stream.fromIterable([1.0])
          : Stream.fromIterable([0.5, 1.0]);
    });

    await expectLater(
      manager.download(),
      emitsInOrder([0.45, 0.9, 1.0, emitsDone]),
    );
    expect(runtime.hasActiveEmbedder, isTrue);
  });

  test('un 401 al bajar el modelo termina en NeedsAuthentication', () async {
    when(
      () => downloader.download(
        url: any(named: 'url'),
        fileName: any(named: 'fileName'),
        token: any(named: 'token'),
        publishedBytes: any(named: 'publishedBytes'),
      ),
    ).thenAnswer(
      (_) => Stream.error(
        DioException(
          requestOptions: RequestOptions(path: '/modelo'),
          response: Response(
            requestOptions: RequestOptions(path: '/modelo'),
            statusCode: 401,
          ),
        ),
      ),
    );

    await expectLater(
      manager.download(),
      emitsError(isA<EmbeddingModelNeedsAuthentication>()),
    );
  });

  test('un error genérico termina en DownloadFailed', () async {
    when(
      () => downloader.download(
        url: any(named: 'url'),
        fileName: any(named: 'fileName'),
        token: any(named: 'token'),
        publishedBytes: any(named: 'publishedBytes'),
      ),
    ).thenAnswer((_) => Stream.error(Exception('sin conexión')));

    await expectLater(
      manager.download(),
      emitsError(isA<EmbeddingModelDownloadFailed>()),
    );
  });

  test('baja el modelo y el tokenizador del repositorio cuya licencia pide '
      'aceptar la pantalla, no del que trae fijo el paquete', () async {
    final urls = <String>[];
    when(
      () => downloader.download(
        url: any(named: 'url'),
        fileName: any(named: 'fileName'),
        token: any(named: 'token'),
        publishedBytes: any(named: 'publishedBytes'),
      ),
    ).thenAnswer((invocation) {
      urls.add(invocation.namedArguments[#url] as String);
      return Stream.fromIterable([1.0]);
    });

    await manager.download().drain<void>();

    expect(urls, [
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq1024_mixed-precision.tflite',
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    ]);
  });
}
