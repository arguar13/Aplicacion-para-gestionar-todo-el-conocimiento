import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/resumable_download.dart';

import '../../support/fake_file_server.dart';

void main() {
  const url = 'https://huggingface.co/org/repo/resolve/main/modelo.bin';
  final content = List<int>.generate(10, (i) => i + 1);

  late Directory tempDir;
  late File partial;
  late FakeFileServer server;
  late ResumableDownload download;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sinapsis_descarga_');
    partial = File('${tempDir.path}${Platform.pathSeparator}modelo.bin.part');
    server = FakeFileServer({url: content});
    download = ResumableDownload(
      dio: Dio()..httpClientAdapter = server,
      // Los reintentos de verdad esperan segundos; acá no hace falta.
      retryDelay: (_) => Duration.zero,
      stallTimeout: const Duration(milliseconds: 100),
    );
  });

  tearDown(() {
    server.close();
    tempDir.deleteSync(recursive: true);
  });

  test(
    'sin nada bajado, baja el archivo entero y devuelve su tamaño',
    () async {
      final progress = <(int, int?)>[];

      final total = await download.fetch(
        url: url,
        partial: partial,
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(total, 10);
      expect(partial.readAsBytesSync(), content);
      expect(server.ranges, [null]);
      expect(progress.last, (10, 10));
    },
  );

  test(
    'con un archivo a medias, pide el resto con Range y lo agrega',
    () async {
      partial.writeAsBytesSync(content.take(4).toList());

      final total = await download.fetch(url: url, partial: partial);

      expect(total, 10);
      expect(partial.readAsBytesSync(), content);
      expect(server.ranges, ['bytes=4-']);
    },
  );

  test('con el archivo ya entero, el 416 del servidor es «ya está», no un '
      'error que se reintenta', () async {
    partial.writeAsBytesSync(content);

    final total = await download.fetch(url: url, partial: partial);

    expect(total, 10);
    expect(partial.readAsBytesSync(), content);
    // Un solo pedido: antes eran ocho, unos 84 s, y terminaba en error.
    expect(server.requests, hasLength(1));
  });

  test('un 416 con otro tamaño —lo local no es de este archivo— borra y '
      'empieza de cero', () async {
    partial.writeAsBytesSync(List<int>.filled(12, 0));

    final total = await download.fetch(url: url, partial: partial);

    expect(total, 10);
    expect(partial.readAsBytesSync(), content);
    expect(server.ranges, ['bytes=12-', null]);
  });

  test('si el servidor ignora el rango y manda el archivo entero, lo '
      'reescribe en vez de duplicar bytes', () async {
    partial.writeAsBytesSync([9, 9, 9]);
    server.acceptsRanges = false;

    await download.fetch(url: url, partial: partial);

    expect(partial.readAsBytesSync(), content);
  });

  test('una conexión que se cierra antes de tiempo no da el archivo por '
      'entero: se retoma desde donde quedó', () async {
    server.misbehaviors.add(const Misbehavior.cut(6));

    final total = await download.fetch(url: url, partial: partial);

    expect(total, 10);
    expect(partial.readAsBytesSync(), content);
    expect(server.ranges, [null, 'bytes=6-']);
  });

  test('una conexión que se queda callada a mitad del cuerpo se corta y se '
      'retoma, en vez de esperar para siempre', () async {
    server.misbehaviors.add(const Misbehavior.stall());

    final total = await download.fetch(url: url, partial: partial);

    expect(total, 10);
    expect(partial.readAsBytesSync(), content);
    expect(server.ranges, [null, 'bytes=1-']);
  });

  test('un 5xx se reintenta', () async {
    server.misbehaviors.add(const Misbehavior.status(503));

    await download.fetch(url: url, partial: partial);

    expect(partial.readAsBytesSync(), content);
    expect(server.requests, hasLength(2));
  });

  test('un 403 —repositorio protegido— no se reintenta', () async {
    server.misbehaviors.add(const Misbehavior.status(403));

    await expectLater(
      download.fetch(url: url, partial: partial),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'estado',
          403,
        ),
      ),
    );
    expect(server.requests, hasLength(1));
  });

  test('agotados los intentos, el último error llega a quien llamó', () async {
    final impatient = ResumableDownload(
      dio: Dio()..httpClientAdapter = server,
      maxAttempts: 2,
      retryDelay: (_) => Duration.zero,
    );
    server.misbehaviors.addAll([
      const Misbehavior.status(500),
      const Misbehavior.status(500),
    ]);

    await expectLater(
      impatient.fetch(url: url, partial: partial),
      throwsA(isA<DioException>()),
    );
    expect(server.requests, hasLength(2));
  });

  test('con el tamaño esperado ya en el disco, ni le pregunta al '
      'servidor', () async {
    partial.writeAsBytesSync(content);

    final total = await download.fetch(
      url: url,
      partial: partial,
      expectedBytes: 10,
    );

    expect(total, 10);
    expect(server.requests, isEmpty);
  });

  test('si el archivo cambió en el servidor desde que se empezó, no le pega '
      'lo nuevo a lo viejo: empieza de cero', () async {
    partial.writeAsBytesSync([7, 7, 7]);
    final totals = <int>[];

    await download.fetch(
      url: url,
      partial: partial,
      // Lo que dijo el servidor cuando se empezó a bajar.
      expectedBytes: 20,
      onTotal: totals.add,
    );

    expect(partial.readAsBytesSync(), content);
    expect(server.ranges, ['bytes=3-', null]);
    expect(totals.last, 10);
  });

  test('avisa el total apenas el servidor lo dice', () async {
    final totals = <int>[];

    await download.fetch(url: url, partial: partial, onTotal: totals.add);

    expect(totals, [10]);
  });
}
