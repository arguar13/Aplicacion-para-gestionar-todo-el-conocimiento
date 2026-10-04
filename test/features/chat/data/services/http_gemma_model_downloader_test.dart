import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';

import '../../../../support/fake_file_server.dart';

void main() {
  const url = 'https://huggingface.co/org/repo/resolve/main/model.litertlm';
  const fileName = 'modelo.litertlm';
  final content = List<int>.generate(10, (i) => i + 1);

  late Directory tempDir;
  late FakeFileServer server;
  late HttpGemmaModelDownloader downloader;
  late File target;

  File sibling(String suffix) => File('${target.path}$suffix');

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sinapsis_gemma_');
    server = FakeFileServer({url: content});
    downloader = HttpGemmaModelDownloader(
      transfer: InAppModelFileTransfer(
        dio: Dio()..httpClientAdapter = server,
        retryDelay: (_) => Duration.zero,
      ),
      rootDirectory: () async => tempDir,
    );
    target = await downloader.targetFile(fileName);
  });

  tearDown(() {
    server.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<List<double>> download({int? publishedBytes}) => downloader
      .download(url: url, fileName: fileName, publishedBytes: publishedBytes)
      .toList();

  group('al bajar', () {
    test('baja a un archivo aparte y recién entero lo pasa a su nombre, con '
        'la marca de terminado', () async {
      final progress = await download();

      expect(target.readAsBytesSync(), content);
      expect(sibling('.descargando').existsSync(), isFalse);
      expect(sibling('.completo').readAsStringSync(), '10');
      expect(progress.last, 1);
      expect(await downloader.isComplete(fileName), isTrue);
    });

    test('retoma lo que quedó a medias de la misma dirección', () async {
      target.parent.createSync(recursive: true);
      sibling('.descargando').writeAsBytesSync(content.take(4).toList());
      sibling('.source').writeAsStringSync(url);

      await download();

      expect(target.readAsBytesSync(), content);
      expect(server.ranges, ['bytes=4-']);
    });

    test('si lo que está a medias es de otra dirección, empieza de cero en '
        'vez de agregarle bytes', () async {
      target.parent.createSync(recursive: true);
      sibling('.descargando').writeAsBytesSync([9, 9]);
      sibling(
        '.source',
      ).writeAsStringSync('https://huggingface.co/otra/url.litertlm');

      await download();

      expect(target.readAsBytesSync(), content);
      expect(server.ranges, [null]);
    });

    test('mientras está a medias, el modelo no cuenta como bajado', () async {
      target.parent.createSync(recursive: true);
      sibling('.descargando').writeAsBytesSync(content);

      expect(await downloader.isComplete(fileName), isFalse);
    });

    test('un 403 —repositorio protegido— se avisa sin reintentar', () async {
      server.misbehaviors.add(const Misbehavior.status(403));

      await expectLater(
        downloader.download(url: url, fileName: fileName),
        emitsError(isA<DioException>()),
      );
      expect(server.requests, hasLength(1));
      expect(target.existsSync(), isFalse);
    });
  });

  group('con el modelo ya en el dispositivo', () {
    test('volver a pedirlo no toca la red: ya está', () async {
      await download();
      server.requests.clear();

      final progress = await download();

      expect(progress, [1]);
      expect(server.requests, isEmpty);
    });

    test(
      'una marca que no coincide con el archivo no lo da por entero',
      () async {
        await download();
        sibling('.completo').writeAsStringSync('99');

        expect(await downloader.isComplete(fileName), isFalse);
      },
    );
  });

  group('lo bajado antes de que existiera la marca', () {
    // Esas versiones escribían directo sobre el nombre definitivo y dejaban
    // `.source` con la dirección.
    void legacyFile(List<int> bytes) {
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(bytes);
      sibling('.source').writeAsStringSync(url);
    }

    test('si mide lo que publica Hugging Face, está entero: se reconoce sin '
        'red y no se vuelve a bajar', () async {
      legacyFile(content);

      expect(await downloader.isComplete(fileName, publishedBytes: 10), isTrue);
      expect(sibling('.completo').readAsStringSync(), '10');
      expect(await download(publishedBytes: 10), [1]);
      expect(server.requests, isEmpty);
    });

    test('si mide otra cosa no se da por bueno; bajarlo lo retoma, y si ya '
        'estaba entero el servidor lo dice sin mandar nada', () async {
      legacyFile(content);
      // El tamaño publicado cambió desde que se bajó.
      expect(
        await downloader.isComplete(fileName, publishedBytes: 11),
        isFalse,
      );

      await download(publishedBytes: 11);

      expect(server.ranges, ['bytes=10-']);
      expect(target.readAsBytesSync(), content);
      expect(await downloader.isComplete(fileName), isTrue);
    });

    test('si quedó cortado, bajarlo trae solo lo que falta', () async {
      legacyFile(content.take(6).toList());

      await download(publishedBytes: 10);

      expect(server.ranges, ['bytes=6-']);
      expect(target.readAsBytesSync(), content);
    });
  });

  // Antes de F29 los modelos se bajaban a la carpeta interna de la app; con
  // el gestor del sistema se bajan a otra, donde el sistema puede escribir.
  group('lo bajado en la carpeta de antes (F29)', () {
    late Directory earlierDir;
    late HttpGemmaModelDownloader moved;

    File earlier(String suffix) => File(
      '${earlierDir.path}${Platform.pathSeparator}modelos'
      '${Platform.pathSeparator}gemma${Platform.pathSeparator}$fileName$suffix',
    );

    setUp(() {
      earlierDir = Directory.systemTemp.createTempSync('sinapsis_gemma_antes_');
      moved = HttpGemmaModelDownloader(
        transfer: InAppModelFileTransfer(
          dio: Dio()..httpClientAdapter = server,
          retryDelay: (_) => Duration.zero,
        ),
        rootDirectory: () async => tempDir,
        earlierRoots: [() async => earlierDir],
      );
    });

    tearDown(() => earlierDir.deleteSync(recursive: true));

    test('entero ahí, se reconoce y se usa donde está, sin bajarlo de '
        'nuevo', () async {
      earlier('')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(content);
      earlier('.completo').writeAsStringSync('10');

      expect(await moved.isComplete(fileName), isTrue);
      expect((await moved.completeFile(fileName))?.path, earlier('').path);
      await moved.download(url: url, fileName: fileName).drain<void>();
      expect(server.requests, isEmpty);
      expect(target.existsSync(), isFalse);
    });

    test('a medias ahí no se puede seguir desde la carpeta nueva: se borra '
        'y se baja en la nueva', () async {
      earlier('.descargando')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(content.take(4).toList());
      earlier('.source').writeAsStringSync(url);

      await moved.download(url: url, fileName: fileName).drain<void>();

      expect(target.readAsBytesSync(), content);
      expect(earlier('.descargando').existsSync(), isFalse);
      expect(earlier('.source').existsSync(), isFalse);
      expect(await moved.isComplete(fileName), isTrue);
    });
  });

  test('cancelar corta la descarga y borra lo bajado', () async {
    server.misbehaviors.add(const Misbehavior.stall());
    final errors = <Object>[];
    final done = downloader
        .download(url: url, fileName: fileName)
        .handleError(errors.add)
        .drain<void>();
    // Hasta que llega el pedido: antes hay disco de por medio.
    for (var i = 0; i < 200 && server.requests.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await downloader.isDownloading(fileName), isTrue);

    await downloader.cancel(fileName);
    await done;

    expect(errors.single, isA<ModelDownloadCancelledException>());
    expect(await downloader.isDownloading(fileName), isFalse);
    expect(sibling('.descargando').existsSync(), isFalse);
    expect(target.existsSync(), isFalse);
  });
}
