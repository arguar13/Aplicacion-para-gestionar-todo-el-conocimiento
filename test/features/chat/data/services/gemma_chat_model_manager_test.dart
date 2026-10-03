import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model_manager.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';

import '../../../../support/fake_file_server.dart';
import '../../../../support/fake_gemma_runtime.dart';

/// De dónde se baja cada modelo de lenguaje —lo que falló en el teléfono:
/// Gemma 4 se resolvía leyendo un `litertlm_manifest.json` que sus
/// repositorios no publican—, y que uno ya bajado se reconozca al reabrir la
/// app: `flutter_gemma` 1.8.3 no lo recuerda (ver
/// `GemmaChatModelManager.isReady`), y [FakeGemmaRuntime] arranca igual, sin
/// nada activo.
void main() {
  // Los archivos que publica cada repositorio, tal cual los lista Hugging
  // Face (consultado el 2026-10-03).
  const published = {
    ChatModelOption.gemma4E4b:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    ChatModelOption.gemma3nE4b:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/resolve/main/gemma-3n-E4B-it-int4.litertlm',
    ChatModelOption.gemma412b:
        'https://huggingface.co/litert-community/gemma-4-12B-it-litert-lm/resolve/main/gemma-4-12B-it.litertlm',
  };

  test('cada opción baja un archivo concreto de su repositorio, sin '
      'depender de un manifiesto', () {
    for (final option in ChatModelOption.values) {
      expect(
        GemmaChatModelManager.downloadUrlOf(option),
        published[option],
        reason: option.name,
      );
    }
  });

  test('para teléfonos, el archivo general y no las variantes de escritorio '
      'o de navegador', () {
    final url = GemmaChatModelManager.downloadUrlOf(ChatModelOption.gemma4E4b);

    expect(url, isNot(contains('-gpu')));
    expect(url, isNot(contains('-web')));
  });

  group('al reabrir la app', () {
    late Directory tempDir;
    late FakeFileServer server;
    late HttpGemmaModelDownloader downloader;
    late FakeGemmaRuntime runtime;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sinapsis_gemma_chat_');
      server = FakeFileServer({
        for (final option in ChatModelOption.values)
          GemmaChatModelManager.downloadUrlOf(option): [1, 2, 3, 4],
      });
      downloader = HttpGemmaModelDownloader(
        dio: Dio()..httpClientAdapter = server,
        rootDirectory: () async => tempDir,
        retryDelay: (_) => Duration.zero,
      );
      runtime = FakeGemmaRuntime();
    });

    tearDown(() {
      server.close();
      tempDir.deleteSync(recursive: true);
    });

    GemmaChatModelManager managerFor(ChatModelOption option) =>
        GemmaChatModelManager(
          option: option,
          downloader: downloader,
          runtime: runtime,
        );

    /// Baja [option] en una «sesión anterior» y deja `flutter_gemma` como
    /// queda al reabrir: sin nada activo.
    Future<void> downloadedBefore(ChatModelOption option) async {
      await managerFor(option).download().drain<void>();
      runtime.activeModel = null;
      runtime.modelInstalls.clear();
      server.requests.clear();
    }

    test('un modelo ya bajado se reconoce y se registra desde su archivo, '
        'sin volver a bajarlo', () async {
      await downloadedBefore(ChatModelOption.gemma4E4b);

      expect(await managerFor(ChatModelOption.gemma4E4b).isReady(), isTrue);
      final file = await downloader.targetFile('gemma4E4b.litertlm');
      expect(runtime.modelInstalls, [file.path]);
      expect(runtime.activeModel?.type, ModelType.gemma4);
      expect(server.requests, isEmpty);
    });

    test('cada opción se reconoce con el nombre con que flutter_gemma '
        'registra su archivo —Gemma 3n incluida—', () async {
      for (final option in ChatModelOption.values) {
        await managerFor(option).download().drain<void>();

        expect(
          await managerFor(option).isReady(),
          isTrue,
          reason: '${option.name}: activo como ${runtime.activeModel}',
        );
      }
    });

    test('el modelo activo de otra opción no cuenta como el elegido, aunque '
        'sea del mismo tipo', () async {
      await managerFor(ChatModelOption.gemma4E4b).download().drain<void>();

      expect(await managerFor(ChatModelOption.gemma412b).isReady(), isFalse);
    });

    test('lo que dejó instalado la descarga de flutter_gemma que se usaba '
        'antes también cuenta', () async {
      runtime.activeModel = (
        type: ModelType.gemmaIt,
        name: 'gemma-3n-E4B-it-int4',
      );

      expect(await managerFor(ChatModelOption.gemma3nE4b).isReady(), isTrue);
      expect(runtime.modelInstalls, isEmpty);
    });

    test(
      'sin el archivo entero no está listo, y no se registra nada',
      () async {
        final file = await downloader.targetFile('gemma4E4b.litertlm');
        File('${file.path}.descargando')
          ..createSync(recursive: true)
          ..writeAsBytesSync([1, 2]);

        expect(await managerFor(ChatModelOption.gemma4E4b).isReady(), isFalse);
        expect(runtime.modelInstalls, isEmpty);
      },
    );

    test('varias comprobaciones a la vez registran el modelo una sola '
        'vez', () async {
      await downloadedBefore(ChatModelOption.gemma4E4b);
      final manager = managerFor(ChatModelOption.gemma4E4b);

      final ready = await Future.wait([manager.isReady(), manager.isReady()]);

      expect(ready, [isTrue, isTrue]);
      expect(runtime.modelInstalls, hasLength(1));
    });

    test('volver a tocar «Descargar» con el modelo ya bajado lo deja listo '
        'sin pedir nada al servidor', () async {
      await downloadedBefore(ChatModelOption.gemma3nE4b);

      await expectLater(
        managerFor(ChatModelOption.gemma3nE4b).download(),
        emitsInOrder([1.0, emitsDone]),
      );
      expect(server.requests, isEmpty);
      expect(await managerFor(ChatModelOption.gemma3nE4b).isReady(), isTrue);
    });
  });
}
