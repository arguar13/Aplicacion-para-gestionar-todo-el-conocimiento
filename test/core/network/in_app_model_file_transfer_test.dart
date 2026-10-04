import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';

import '../../support/fake_file_server.dart';

/// La descarga de un modelo dentro de la app —el escritorio, las pruebas—,
/// detrás de la misma interfaz que la del sistema (F29).
void main() {
  const url = 'https://huggingface.co/org/repo/resolve/main/modelo.bin';
  final content = List<int>.generate(10, (i) => i + 1);

  late Directory tempDir;
  late FakeFileServer server;
  late InAppModelFileTransfer transfer;
  late File target;

  File sibling(String suffix) => File('${target.path}$suffix');

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sinapsis_in_app_dl_');
    server = FakeFileServer({url: content});
    transfer = InAppModelFileTransfer(
      dio: Dio()..httpClientAdapter = server,
      retryDelay: (_) => Duration.zero,
    );
    target = File(p.join(tempDir.path, 'modelos', 'modelo.bin'));
  });

  tearDown(() {
    server.close();
    tempDir.deleteSync(recursive: true);
  });

  test('no sigue con la app cerrada: hay que mantenerla viva', () {
    expect(transfer.continuesWithAppClosed, isFalse);
  });

  test('baja aparte y recién entero le da su nombre', () async {
    expect(await transfer.fetch(url: url, target: target), 10);

    expect(target.readAsBytesSync(), content);
    expect(sibling('.descargando').existsSync(), isFalse);
    expect(sibling('.source').existsSync(), isFalse);
  });

  test('dos pedidos del mismo archivo esperan la misma descarga', () async {
    final both = await Future.wait([
      transfer.fetch(url: url, target: target),
      transfer.fetch(url: url, target: target),
    ]);

    expect(both, [10, 10]);
    expect(server.requests, hasLength(1));
  });

  /// Hasta que el servidor recibe el pedido: antes hay disco de por medio.
  Future<void> requested() async {
    for (var i = 0; i < 200 && server.requests.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('en curso mientras baja, y no después', () async {
    server.misbehaviors.add(const Misbehavior.stall());
    final done = transfer.fetch(url: url, target: target);
    await requested();

    expect(await transfer.isInFlight(target), isTrue);
    await transfer.cancel(target);
    await expectLater(done, throwsA(isA<ModelDownloadCancelledException>()));
    expect(await transfer.isInFlight(target), isFalse);
  });

  test('cancelar corta sin reintentar y borra lo bajado', () async {
    server.misbehaviors.add(const Misbehavior.stall());
    final done = transfer.fetch(url: url, target: target);
    await requested();

    await transfer.cancel(target);

    await expectLater(done, throwsA(isA<ModelDownloadCancelledException>()));
    expect(server.requests, hasLength(1));
    expect(sibling('.descargando').existsSync(), isFalse);
    expect(sibling('.source').existsSync(), isFalse);
    expect(target.existsSync(), isFalse);
  });

  test('lo que no pasa la comprobación se borra y no toma su nombre', () async {
    await expectLater(
      transfer.fetch(
        url: url,
        target: target,
        verify: (_) async => throw const FormatException('huella distinta'),
      ),
      throwsA(isA<FormatException>()),
    );

    expect(target.existsSync(), isFalse);
    expect(sibling('.descargando').existsSync(), isFalse);
  });

  test('lo que había con el nombre definitivo se retoma: si estaba entero, '
      'no se baja nada', () async {
    target
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(content);

    expect(await transfer.fetch(url: url, target: target), 10);
    expect(server.ranges, ['bytes=10-']);
    expect(target.readAsBytesSync(), content);
  });
}
