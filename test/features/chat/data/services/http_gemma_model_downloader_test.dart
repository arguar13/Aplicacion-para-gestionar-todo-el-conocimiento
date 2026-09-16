import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late Directory tempDir;
  late HttpGemmaModelDownloader downloader;

  const url = 'https://huggingface.co/org/repo/resolve/main/model.litertlm';

  setUp(() {
    dio = MockDio();
    tempDir = Directory.systemTemp.createTempSync('sinapsis_gemma_');
    downloader = HttpGemmaModelDownloader(
      dio: dio,
      rootDirectory: () async => tempDir,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Response<ResponseBody> fullResponse(List<int> bytes) => Response(
    requestOptions: RequestOptions(),
    statusCode: 200,
    data: ResponseBody.fromBytes(bytes, 200),
  );

  Response<ResponseBody> partialResponse(List<int> bytes) => Response(
    requestOptions: RequestOptions(),
    statusCode: 206,
    data: ResponseBody.fromBytes(bytes, 206),
  );

  test('sin nada bajado todavía, escribe el archivo entero de una', () async {
    when(
      () => dio.get<ResponseBody>(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => fullResponse([1, 2, 3, 4]));

    await downloader
        .download(url: url, fileName: 'modelo.litertlm')
        .drain<void>();

    final file = await downloader.targetFile('modelo.litertlm');
    expect(file.readAsBytesSync(), Uint8List.fromList([1, 2, 3, 4]));
  });

  test('con un archivo a medias de la misma fuente, pide el resto con Range '
      'y lo agrega', () async {
    final file = await downloader.targetFile('modelo.litertlm')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2]);
    await File('${file.path}.source').writeAsString(url);

    when(
      () => dio.get<ResponseBody>(any(), options: any(named: 'options')),
    ).thenAnswer((invocation) async {
      final options = invocation.namedArguments[#options] as Options;
      expect(options.headers?['range'], 'bytes=2-');
      return partialResponse([3, 4]);
    });

    await downloader
        .download(url: url, fileName: 'modelo.litertlm')
        .drain<void>();

    expect(file.readAsBytesSync(), Uint8List.fromList([1, 2, 3, 4]));
  });

  test('si la fuente resuelta cambió desde el intento anterior, empieza de '
      'cero en vez de agregarle a lo que ya había', () async {
    final file = await downloader.targetFile('modelo.litertlm')
      ..createSync(recursive: true)
      ..writeAsBytesSync([9, 9]);
    await File(
      '${file.path}.source',
    ).writeAsString('https://huggingface.co/otra/url.litertlm');

    when(
      () => dio.get<ResponseBody>(any(), options: any(named: 'options')),
    ).thenAnswer((invocation) async {
      final options = invocation.namedArguments[#options] as Options;
      // Sin bytes previos que valgan, no se pide ningún rango.
      expect(options.headers?.containsKey('range'), isFalse);
      return fullResponse([1, 2, 3]);
    });

    await downloader
        .download(url: url, fileName: 'modelo.litertlm')
        .drain<void>();

    expect(file.readAsBytesSync(), Uint8List.fromList([1, 2, 3]));
  });

  test('si el servidor no soporta reanudar y contesta 200 en vez de 206, '
      'reemplaza el archivo entero en vez de duplicar bytes', () async {
    final file = await downloader.targetFile('modelo.litertlm')
      ..createSync(recursive: true)
      ..writeAsBytesSync([9, 9]);
    await File('${file.path}.source').writeAsString(url);

    when(
      () => dio.get<ResponseBody>(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => fullResponse([1, 2, 3]));

    await downloader
        .download(url: url, fileName: 'modelo.litertlm')
        .drain<void>();

    expect(file.readAsBytesSync(), Uint8List.fromList([1, 2, 3]));
  });

  test(
    'un 403 —repositorio protegido— no se reintenta, se avisa directo',
    () async {
      var attempts = 0;
      when(
        () => dio.get<ResponseBody>(any(), options: any(named: 'options')),
      ).thenAnswer((_) async {
        attempts++;
        throw DioException(
          requestOptions: RequestOptions(),
          response: Response(requestOptions: RequestOptions(), statusCode: 403),
        );
      });

      await expectLater(
        downloader.download(url: url, fileName: 'modelo.litertlm'),
        emitsError(isA<DioException>()),
      );
      expect(attempts, 1);
    },
  );

  test(
    'un corte transitorio se reintenta solo hasta que se completa',
    () async {
      var attempts = 0;
      when(
        () => dio.get<ResponseBody>(any(), options: any(named: 'options')),
      ).thenAnswer((_) async {
        attempts++;
        if (attempts < 3) {
          throw DioException(requestOptions: RequestOptions());
        }
        return fullResponse([1, 2, 3]);
      });

      final errors = <Object>[];
      await downloader
          .download(url: url, fileName: 'modelo.litertlm')
          .handleError(errors.add)
          .drain<void>();

      expect(errors, isEmpty);
      expect(attempts, 3);
    },
  );
}
