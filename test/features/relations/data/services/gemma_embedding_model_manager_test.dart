import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';
import 'package:sinapsis/features/relations/data/services/gemma_embedding_model_manager.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';

import '../../../../support/fake_gemma_runtime.dart';

class MockHttpGemmaModelDownloader extends Mock
    implements HttpGemmaModelDownloader {}

const _model = 'embeddinggemma-300M_seq1024_mixed-precision.tflite';
const _tokenizer = 'embeddinggemma-sentencepiece.model';
const _modelBytes = 183329528;
const _tokenizerBytes = 4683319;

/// El modelo real no corre en una prueba; `flutter_gemma` va con
/// [FakeGemmaRuntime], que arranca sin nada activo como el paquete al
/// reabrir la app. Se prueba cómo se combina el progreso de las dos
/// descargas, cómo se traduce un error de cualquiera de las dos, y que un
/// modelo ya bajado se reconozca sin volver a bajarlo.
void main() {
  late MockHttpGemmaModelDownloader downloader;
  late FakeGemmaRuntime runtime;
  late GemmaEmbeddingModelManager manager;

  /// Qué devuelve la descarga de cada archivo.
  void serve(Stream<double> Function(String fileName) stream) {
    when(
      () => downloader.download(
        url: any(named: 'url'),
        fileName: any(named: 'fileName'),
        token: any(named: 'token'),
        publishedBytes: any(named: 'publishedBytes'),
        label: any(named: 'label'),
      ),
    ).thenAnswer(
      (invocation) => stream(invocation.namedArguments[#fileName] as String),
    );
  }

  /// Si cada archivo está entero, y dónde.
  void complete(Map<String, File?> files) {
    when(
      () => downloader.completeFile(
        any(),
        publishedBytes: any(named: 'publishedBytes'),
      ),
    ).thenAnswer(
      (invocation) async => files[invocation.positionalArguments[0]],
    );
    when(
      () => downloader.isComplete(
        any(),
        publishedBytes: any(named: 'publishedBytes'),
      ),
    ).thenAnswer(
      (invocation) async => files[invocation.positionalArguments[0]] != null,
    );
  }

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
    complete({});
  });

  test('downloadSizeInBytes: sin dato de antemano, es null', () async {
    expect(await manager.downloadSizeInBytes(), isNull);
  });

  test('isReady: sin ningún modelo activo ni sus archivos, false', () async {
    expect(await manager.isReady(), isFalse);
    expect(runtime.embedderInstalls, isEmpty);
  });

  test('isReady: con los dos archivos enteros de una sesión anterior, los '
      'registra desde donde están y está listo sin bajar nada', () async {
    // Bajados antes de F29: en la carpeta interna, no donde se baja ahora.
    complete({
      _model: File('antes/$_model'),
      _tokenizer: File('antes/$_tokenizer'),
    });

    expect(await manager.isReady(), isTrue);
    expect(runtime.embedderInstalls, [
      (File('antes/$_model').path, File('antes/$_tokenizer').path),
    ]);
  });

  test('isReady: con solo el modelo entero y el tokenizador a medias, no '
      'está listo', () async {
    complete({_model: File(_model)});

    expect(await manager.isReady(), isFalse);
    expect(runtime.embedderInstalls, isEmpty);
  });

  test('isReady: los tamaños publicados reconocen lo bajado antes de la '
      'marca de terminado', () async {
    await manager.isReady();

    verify(
      () => downloader.isComplete(_model, publishedBytes: _modelBytes),
    ).called(1);
  });

  test('pide los dos archivos a la vez —con el gestor del sistema siguen con '
      'la app cerrada— y el progreso los combina por bytes', () async {
    final model = StreamController<double>();
    final tokenizer = StreamController<double>();
    serve((name) => name == _model ? model.stream : tokenizer.stream);
    const total = _modelBytes + _tokenizerBytes;

    final progress = <double>[];
    final done = manager.download().listen(progress.add).asFuture<void>();
    await pumpEventQueue();
    // Los dos pedidos antes de que ninguno termine.
    expect(model.hasListener, isTrue);
    expect(tokenizer.hasListener, isTrue);

    tokenizer.add(1);
    await pumpEventQueue();
    expect(progress.last, closeTo(_tokenizerBytes / total, 1e-9));

    model.add(0.5);
    await pumpEventQueue();
    expect(
      progress.last,
      closeTo((0.5 * _modelBytes + _tokenizerBytes) / total, 1e-9),
    );

    model.add(1);
    await Future.wait([model.close(), tokenizer.close()]);
    complete({_model: File(_model), _tokenizer: File(_tokenizer)});
    await done;

    expect(progress.last, 1.0);
    expect(runtime.hasActiveEmbedder, isTrue);
  });

  test('un 401 al bajar el modelo termina en NeedsAuthentication', () async {
    serve(
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

  test('un 401 del gestor de descargas del sistema, también', () async {
    serve((_) => Stream.error(const ModelDownloadHttpException(401)));

    await expectLater(
      manager.download(),
      emitsError(isA<EmbeddingModelNeedsAuthentication>()),
    );
  });

  test('sin lugar, el error llega tal cual: la pantalla lo sabe decir', () {
    serve(
      (_) => Stream.error(
        const InsufficientStorageException(requiredBytes: _modelBytes),
      ),
    );

    return expectLater(
      manager.download(),
      emitsError(isA<InsufficientStorageException>()),
    );
  });

  test('un error genérico termina en DownloadFailed', () async {
    serve((_) => Stream.error(Exception('sin conexión')));

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
        label: any(named: 'label'),
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

  group('la descarga que siguió con la app cerrada (F29)', () {
    test('hay una en curso si cualquiera de los dos archivos baja', () async {
      when(
        () => downloader.isDownloading(_model),
      ).thenAnswer((_) async => false);
      when(
        () => downloader.isDownloading(_tokenizer),
      ).thenAnswer((_) async => true);

      expect(await manager.isDownloading(), isTrue);
    });

    test('ninguno baja: no hay a qué engancharse', () async {
      when(
        () => downloader.isDownloading(any()),
      ).thenAnswer((_) async => false);

      expect(await manager.isDownloading(), isFalse);
    });

    test('cancelar corta los dos', () async {
      when(() => downloader.cancel(any())).thenAnswer((_) async {});

      await manager.cancelDownload();

      verify(() => downloader.cancel(_model)).called(1);
      verify(() => downloader.cancel(_tokenizer)).called(1);
    });
  });
}
