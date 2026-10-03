import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/dev_seed/data/services/dio_sample_file_downloader.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/dev_seed/domain/services/sample_file_downloader.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Una respuesta de mentira: el código, los bytes y, si hace falta, las
/// cabeceras.
typedef _Reply = ({
  int status,
  List<int> body,
  Map<String, List<String>> headers,
});

/// El servidor de mentira: contesta, en orden, lo que tenga en [replies]; si
/// [hangUntilCancelled], no contesta hasta que se cancele el pedido.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.replies, {this.hangUntilCancelled = false});

  final List<_Reply> replies;
  final bool hangUntilCancelled;
  final requested = <String>[];
  final started = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.toString());
    if (!started.isCompleted) started.complete();
    if (hangUntilCancelled) {
      await cancelFuture;
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: 'cancelado',
      );
    }
    final reply = replies.removeAt(0);
    return ResponseBody.fromBytes(
      reply.body,
      reply.status,
      headers: reply.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

const _pdf = SampleFile(
  id: 'pdf-ddhc',
  title: 'Declaración de 1789',
  why: 'Un PDF.',
  kind: SampleFileKind.pdf,
  url: 'https://ejemplo.org/ddhc.pdf',
  fileName: 'declaracion.pdf',
  approxBytes: 100,
);

final _pdfBytes = [...ascii.encode('%PDF-1.4\n'), ...List.filled(200, 0x20)];

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('sinapsis_ejemplo_');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  DioSampleFileDownloader build(_FakeAdapter adapter) =>
      DioSampleFileDownloader(
        dio: Dio()..httpClientAdapter = adapter,
        temporaryRoot: () async => root,
        defaultThrottleWait: Duration.zero,
      );

  Directory folder() => Directory('${root.path}/biblioteca_de_ejemplo');

  test('baja a un temporal propio, lo entrega en disco con su nombre, y '
      'descartarlo lo borra', () async {
    final downloader = build(
      _FakeAdapter([(status: 200, body: _pdfBytes, headers: const {})]),
    );

    final downloaded = await downloader.download(
      _pdf,
      cancellation: CancellationSignal(),
    );

    expect(downloaded.file.name, 'declaracion.pdf');
    expect(downloaded.file.sizeInBytes, _pdfBytes.length);
    expect(downloaded.file.format, FileFormat.pdf);
    expect(await downloaded.file.readAll(), _pdfBytes);
    expect(folder().listSync(), hasLength(1));

    await downloaded.discard();
    expect(folder().listSync(), isEmpty);
  });

  test('un error del servidor no deja nada en el disco y se informa con su '
      'código', () async {
    final downloader = build(
      _FakeAdapter([
        (status: 404, body: utf8.encode('<html>No</html>'), headers: const {}),
      ]),
    );

    await expectLater(
      downloader.download(_pdf, cancellation: CancellationSignal()),
      throwsA(
        isA<SampleDownloadException>().having(
          (e) => e.message,
          'message',
          'El servidor respondió 404.',
        ),
      ),
    );
    expect(folder().listSync(), isEmpty);
  });

  test('si el servidor frena con un 429, espera y vuelve a pedir', () async {
    final adapter = _FakeAdapter([
      (
        status: 429,
        body: utf8.encode('Too many requests'),
        headers: const {
          'retry-after': ['0'],
        },
      ),
      (status: 200, body: _pdfBytes, headers: const {}),
    ]);

    final downloaded = await build(
      adapter,
    ).download(_pdf, cancellation: CancellationSignal());

    expect(adapter.requested, hasLength(2));
    expect(downloaded.file.format, FileFormat.pdf);
  });

  test('si el servidor sigue frenando, se rinde y lo informa', () async {
    final adapter = _FakeAdapter([
      for (var i = 0; i < 4; i++)
        (status: 429, body: const <int>[], headers: const {}),
    ]);

    await expectLater(
      build(adapter).download(_pdf, cancellation: CancellationSignal()),
      throwsA(isA<SampleDownloadException>()),
    );
    // El primer pedido y tres reintentos.
    expect(adapter.requested, hasLength(4));
  });

  test(
    'cancelar corta la bajada en curso sin dejar nada en el disco',
    () async {
      final adapter = _FakeAdapter(const [], hangUntilCancelled: true);
      final cancellation = CancellationSignal();

      final running = build(adapter).download(_pdf, cancellation: cancellation);
      await adapter.started.future;
      cancellation.cancel();

      await expectLater(running, throwsA(isA<ProcessingCancelledException>()));
      expect(folder().listSync(), isEmpty);
    },
  );

  test('borrar los restos de una pasada anterior vacía su carpeta, y no '
      'falla si no existe', () async {
    final downloader = build(_FakeAdapter(const []));
    await downloader.clearLeftovers();

    folder().createSync();
    File('${folder().path}/a_medias.pdf').writeAsStringSync('%PDF-');
    File('${root.path}/ajeno.txt').writeAsStringSync('no se toca');

    await downloader.clearLeftovers();

    expect(folder().existsSync(), isFalse);
    expect(File('${root.path}/ajeno.txt').existsSync(), isTrue);
  });
}
