import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
      dio: Dio()..httpClientAdapter = server,
      rootDirectory: () async => tempDir,
      retryDelay: (_) => Duration.zero,
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
}
