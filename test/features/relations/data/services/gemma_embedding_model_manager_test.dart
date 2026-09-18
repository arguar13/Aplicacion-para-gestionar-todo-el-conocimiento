import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';
import 'package:sinapsis/features/relations/data/services/gemma_embedding_model_manager.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';

class MockHttpGemmaModelDownloader extends Mock
    implements HttpGemmaModelDownloader {}

/// No hay forma de correr el modelo real —ni siquiera instalarlo, con
/// `FlutterGemma.installEmbedder()...install()`— en un test sin el canal
/// de plataforma real, mismo límite que ya tiene `GemmaChatModelManager`
/// hoy, sin ningún test propio por el mismo motivo. Lo que sí se puede
/// probar sin tocar el plugin: cómo se combina el progreso de las dos
/// descargas, y cómo se traduce un error de cualquiera de las dos —los
/// dos pasan ANTES de llegar a `install()`.
void main() {
  late MockHttpGemmaModelDownloader downloader;
  late GemmaEmbeddingModelManager manager;

  setUp(() {
    downloader = MockHttpGemmaModelDownloader();
    manager = GemmaEmbeddingModelManager(downloader: downloader);
    when(() => downloader.targetFile(any())).thenAnswer(
      (invocation) async => File(invocation.positionalArguments[0] as String),
    );
  });

  test('downloadSizeInBytes: sin dato de antemano, es null', () async {
    expect(await manager.downloadSizeInBytes(), isNull);
  });

  test('isReady: sin ningún modelo activo, false', () async {
    expect(await manager.isReady(), isFalse);
  });

  test('el progreso combina las dos descargas: 0-90% el modelo, 90-100% el '
      'tokenizador', () async {
    when(
      () => downloader.download(
        url: any(named: 'url'),
        fileName: any(named: 'fileName'),
        token: any(named: 'token'),
        expectedSizeBytes: any(named: 'expectedSizeBytes'),
      ),
    ).thenAnswer((invocation) {
      final fileName = invocation.namedArguments[#fileName] as String;
      return fileName.contains('sentencepiece')
          ? Stream.fromIterable([1.0])
          : Stream.fromIterable([0.5, 1.0]);
    });

    // `emitsInOrder` se desuscribe apenas matchea los tres valores, sin
    // esperar a que el stream cierre —lo que sigue después (instalar el
    // modelo vía el plugin real) no tiene con qué correr en un test, y
    // no hace falta: lo único que se prueba acá es cómo se combina el
    // progreso de las dos descargas.
    await expectLater(manager.download(), emitsInOrder([0.45, 0.9, 1.0]));
  });

  test('un 401 al bajar el modelo termina en NeedsAuthentication', () async {
    when(
      () => downloader.download(
        url: any(named: 'url'),
        fileName: any(named: 'fileName'),
        token: any(named: 'token'),
        expectedSizeBytes: any(named: 'expectedSizeBytes'),
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
        expectedSizeBytes: any(named: 'expectedSizeBytes'),
      ),
    ).thenAnswer((_) => Stream.error(Exception('sin conexión')));

    await expectLater(
      manager.download(),
      emitsError(isA<EmbeddingModelDownloadFailed>()),
    );
  });
}
