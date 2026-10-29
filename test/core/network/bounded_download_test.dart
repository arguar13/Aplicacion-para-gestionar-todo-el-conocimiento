import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/bounded_download.dart';
import 'package:sinapsis/core/network/host_gate.dart';

/// Un servidor de mentira: cada dirección contesta lo que diga su lista de
/// respuestas, una por pedido (la última se repite).
class _Server implements HttpClientAdapter {
  final routes = <String, List<_Reply>>{};
  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    final replies = routes[options.uri.toString()];
    if (replies == null) return ResponseBody.fromString('', 404);
    final reply = replies.length > 1 ? replies.removeAt(0) : replies.first;
    return ResponseBody(
      Stream.fromIterable([
        for (var i = 0; i < reply.body.length; i += 4)
          Uint8List.fromList(reply.body.skip(i).take(4).toList()),
      ]),
      reply.status,
      headers: {
        if (reply.contentType != null) 'content-type': [reply.contentType!],
        if (reply.declareLength)
          Headers.contentLengthHeader: ['${reply.body.length}'],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Reply {
  _Reply(
    this.body, {
    this.status = 200,
    this.contentType,
    this.declareLength = true,
    this.headers = const {},
  });

  final List<int> body;
  final int status;
  final String? contentType;
  final bool declareLength;
  final Map<String, List<String>> headers;
}

void main() {
  late _Server server;
  late Map<String, List<int>> saved;
  late int? free;

  BoundedDownloader downloader({int reserve = 0}) => BoundedDownloader(
    dio: Dio()..httpClientAdapter = server,
    hosts: HostGate(gap: Duration.zero),
    freeBytes: () async => free,
    reserveBytes: reserve,
    spaceCheckEvery: 4,
  );

  Future<String> save(Stream<List<int>> bytes, String name) async {
    final collected = <int>[];
    await for (final chunk in bytes) {
      collected.addAll(chunk);
    }
    saved[name] = collected;
    return 'originales/x/$name';
  }

  setUp(() {
    server = _Server();
    saved = {};
    free = null;
  });

  final pdf = Uri.parse('https://ejemplo.org/docs/informe.pdf');
  final bytes = List<int>.generate(20, (i) => i);

  test('baja y guarda, con el tipo y el nombre del servidor', () async {
    server.routes['$pdf'] = [
      _Reply(
        bytes,
        contentType: 'application/PDF; charset=binary',
        headers: {
          'content-disposition': [
            "attachment; filename*=UTF-8''Informe%20anual%202026.pdf",
          ],
        },
      ),
    ];

    final result = await downloader().download(pdf, maxBytes: 100, save: save);

    expect(result.bytes, 20);
    expect(result.contentType, 'application/pdf');
    expect(result.fileName, 'Informe anual 2026.pdf');
    expect(result.savedAs, 'originales/x/Informe anual 2026.pdf');
    expect(saved['Informe anual 2026.pdf'], bytes);
  });

  test('el nombre en UTF-8 crudo, como lo deja `dart:io`, llega entero y '
      'así se guarda (F43, M7)', () async {
    server.routes['$pdf'] = [
      _Reply(
        bytes,
        headers: {
          'content-disposition': [
            latin1.decode(
              utf8.encode('attachment; filename="Declaración.pdf"'),
            ),
          ],
        },
      ),
    ];

    final result = await downloader().download(pdf, maxBytes: 100, save: save);

    expect(result.fileName, 'Declaración.pdf');
    expect(saved.keys, ['Declaración.pdf']);
  });

  test('sin Content-Disposition, el nombre sale de la dirección', () async {
    server.routes['$pdf'] = [_Reply(bytes)];
    final result = await downloader().download(pdf, maxBytes: 100, save: save);
    expect(result.fileName, 'informe.pdf');
  });

  test('si dice que pesa de más, no baja nada', () async {
    server.routes['$pdf'] = [_Reply(bytes)];

    await expectLater(
      downloader().download(pdf, maxBytes: 10, save: save),
      throwsA(
        isA<DownloadTooLargeException>().having(
          (e) => e.declared,
          'declarado',
          20,
        ),
      ),
    );
    expect(saved, isEmpty);
  });

  test('si no dice cuánto pesa, se corta al pasarse, mientras baja', () async {
    server.routes['$pdf'] = [_Reply(bytes, declareLength: false)];
    final progress = <int>[];

    await expectLater(
      downloader().download(
        pdf,
        maxBytes: 10,
        save: save,
        onProgress: (received, _) => progress.add(received),
      ),
      throwsA(isA<DownloadTooLargeException>()),
    );
    expect(saved, isEmpty);
    // Llegó hasta el pedazo que se pasó, y ni uno más.
    expect(progress.last, lessThanOrEqualTo(10));
  });

  test('sin lugar en el teléfono, no empieza', () async {
    server.routes['$pdf'] = [_Reply(bytes)];
    free = 25;

    await expectLater(
      downloader(reserve: 10).download(pdf, maxBytes: 100, save: save),
      throwsA(isA<NotEnoughSpaceException>()),
    );
    expect(saved, isEmpty);
  });

  test('si el espacio se acaba a mitad de camino, corta', () async {
    server.routes['$pdf'] = [_Reply(bytes, declareLength: false)];
    var calls = 0;
    final d = BoundedDownloader(
      dio: Dio()..httpClientAdapter = server,
      hosts: HostGate(gap: Duration.zero),
      // Antes de empezar hay lugar; después de unos bytes, ya no.
      freeBytes: () async => calls++ == 0 ? 1000 : 5,
      reserveBytes: 10,
      spaceCheckEvery: 8,
    );

    await expectLater(
      d.download(pdf, maxBytes: 100, save: save),
      throwsA(isA<NotEnoughSpaceException>()),
    );
    expect(saved, isEmpty);
  });

  test('una página en vez de un archivo se rechaza sin bajarla', () async {
    server.routes['$pdf'] = [
      _Reply(List.filled(10, 60), contentType: 'text/html; charset=utf-8'),
    ];

    await expectLater(
      downloader().download(
        pdf,
        maxBytes: 100,
        save: save,
        accept: (type) => type != 'text/html',
      ),
      throwsA(isA<UnwantedContentException>()),
    );
    expect(saved, isEmpty);
  });

  test('un 429 con Retry-After se espera y se vuelve a pedir', () async {
    server.routes['$pdf'] = [
      _Reply(
        const [],
        status: 429,
        headers: {
          'retry-after': ['0'],
        },
      ),
      _Reply(bytes),
    ];

    final result = await downloader().download(pdf, maxBytes: 100, save: save);

    expect(result.bytes, 20);
    expect(server.requests, hasLength(2));
  });

  test('un 404 no se reintenta', () async {
    await expectLater(
      downloader().download(pdf, maxBytes: 100, save: save),
      throwsA(isA<DioException>()),
    );
    expect(server.requests, hasLength(1));
  });

  test('un 503 que no se arregla se rinde después de los intentos', () async {
    server.routes['$pdf'] = [
      _Reply(
        const [],
        status: 503,
        headers: {
          'retry-after': ['0'],
        },
      ),
    ];

    await expectLater(
      downloader().download(pdf, maxBytes: 100, save: save),
      throwsA(isA<DioException>()),
    );
    expect(server.requests, hasLength(3));
  });

  group('fileNameFromContentDisposition', () {
    test('las formas comunes', () {
      expect(
        fileNameFromContentDisposition('attachment; filename="a b.pdf"'),
        'a b.pdf',
      );
      expect(fileNameFromContentDisposition('inline; filename=c.mp3'), 'c.mp3');
      expect(
        fileNameFromContentDisposition(
          "attachment; filename=\"x.pdf\"; filename*=UTF-8''%C3%A1rbol.pdf",
        ),
        'árbol.pdf',
      );
      expect(fileNameFromContentDisposition('inline'), isNull);
      expect(fileNameFromContentDisposition(null), isNull);
    });

    group('las letras de afuera del ASCII (F43, M7)', () {
      /// El encabezado como lo deja `dart:io`: cada byte, una letra de
      /// Latin-1.
      String asHeader(String sent) => latin1.decode(utf8.encode(sent));

      test('un `filename` en UTF-8 crudo no sale como «DeclaraciÃ³n»', () {
        final header = asHeader(
          'attachment; filename="Declaración de los Derechos.pdf"',
        );
        expect(header, contains('Ã³'));

        expect(
          fileNameFromContentDisposition(header),
          'Declaración de los Derechos.pdf',
        );
      });

      test('un `filename` en Latin-1 de verdad queda como llegó', () {
        expect(
          fileNameFromContentDisposition('attachment; filename="Año.pdf"'),
          'Año.pdf',
        );
      });

      test('el `filename*` respeta su codificación: ISO-8859-1', () {
        expect(
          fileNameFromContentDisposition(
            "attachment; filename*=ISO-8859-1''Declaraci%F3n.pdf",
          ),
          'Declaración.pdf',
        );
      });

      test('un `filename*` mal codificado deja el `filename`', () {
        expect(
          fileNameFromContentDisposition(
            "attachment; filename=\"bien.pdf\"; filename*=UTF-8''mal%F3.pdf",
          ),
          'bien.pdf',
        );
        expect(
          fileNameFromContentDisposition(
            "attachment; filename=\"bien.pdf\"; filename*=UTF-8''mal%-1.pdf",
          ),
          'bien.pdf',
        );
      });
    });
  });
}
