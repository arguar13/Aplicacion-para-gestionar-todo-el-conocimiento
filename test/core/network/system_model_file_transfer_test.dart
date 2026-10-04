import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/core/network/system_downloads.dart';
import 'package:sinapsis/core/network/system_model_file_transfer.dart';

import '../../support/fake_system_downloads.dart';

/// Las descargas de los modelos con el gestor del sistema (F29), contra un
/// sistema de mentira: la app pide, sigue, se cierra y se vuelve a abrir
/// —otra instancia sobre el mismo sistema y el mismo disco—.
void main() {
  const url = 'https://huggingface.co/org/repo/resolve/main/modelo.litertlm';
  final content = List<int>.generate(10, (i) => i + 1);

  late Directory tempDir;
  late FakeSystemDownloads system;
  late File target;

  /// La app, abierta: una instancia nueva cada vez que "se vuelve a abrir".
  SystemModelFileTransfer openApp() => SystemModelFileTransfer(
    downloads: system,
    pollInterval: const Duration(milliseconds: 1),
  );

  File sibling(String suffix) => File('${target.path}$suffix');

  /// Espera a que [condition] se cumpla: el seguimiento le pregunta al
  /// sistema cada milisegundo.
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 500 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(condition(), isTrue);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sinapsis_system_dl_');
    system = FakeSystemDownloads(tempDir);
    target = File(p.join(tempDir.path, 'modelos', 'gemma', 'modelo.litertlm'));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('sigue con la app cerrada: no hace falta mantenerla viva', () {
    expect(openApp().continuesWithAppClosed, isTrue);
  });

  test('le pide la dirección de Hugging Face —no la del CDN— con el token, '
      'y al terminar le da su nombre definitivo', () async {
    final progress = <(int, int?)>[];
    final done = openApp().fetch(
      url: url,
      target: target,
      headers: {'authorization': 'Bearer hf_x'},
      label: 'language_model',
      onProgress: (received, total) => progress.add((received, total)),
    );
    await until(() => system.enqueued.isNotEmpty);

    final pedido = system.enqueued.single;
    expect(pedido.url, url);
    expect(pedido.headers, {'authorization': 'Bearer hf_x'});
    expect(pedido.label, 'language_model');
    expect(pedido.destination.path, sibling('.descargando').path);
    expect(sibling('.descarga').readAsLinesSync(), ['${system.onlyId}', url]);

    final id = system.onlyId;
    system.progress(id, content.take(4).toList(), 10);
    await until(() => progress.contains((4, 10)));
    system.finish(id, content);

    expect(await done, 10);
    expect(target.readAsBytesSync(), content);
    expect(sibling('.descargando').existsSync(), isFalse);
    expect(sibling('.descarga').existsSync(), isFalse);
    // Olvidada en el sistema después del cambio de nombre: no borra nada.
    expect(system.removed, [id]);
  });

  group('al volver a abrir la app', () {
    /// Lo que deja una sesión anterior que pidió la descarga y se cerró: el
    /// pedido en el sistema y su número anotado junto al destino.
    Future<int> requestedBeforeClosing() async {
      target.parent.createSync(recursive: true);
      final id = await system.enqueue(
        url: url,
        destination: sibling('.descargando'),
      );
      sibling('.descarga').writeAsStringSync('$id\n$url');
      return id;
    }

    test('se engancha a la descarga en curso, sin pedir otra', () async {
      final id = await requestedBeforeClosing();
      system.progress(id, content.take(3).toList(), 10);

      final reopened = openApp();
      expect(await reopened.isInFlight(target), isTrue);
      final progress = <int>[];
      final done = reopened.fetch(
        url: url,
        target: target,
        onProgress: (received, _) => progress.add(received),
      );
      await until(() => progress.contains(3));
      system.finish(id, content);

      expect(await done, 10);
      expect(system.enqueued, hasLength(1));
      expect(target.readAsBytesSync(), content);
    });

    test(
      'lo que terminó con la app cerrada se recoge, sin bajar nada',
      () async {
        final id = await requestedBeforeClosing();
        system.finish(id, content);

        final reopened = openApp();
        expect(await reopened.isInFlight(target), isTrue);
        expect(await reopened.fetch(url: url, target: target), 10);
        expect(target.readAsBytesSync(), content);
        expect(system.enqueued, hasLength(1));
        expect(await reopened.isInFlight(target), isFalse);
      },
    );

    test('si se cerró justo después de darle su nombre, lo da por '
        'terminado', () async {
      final id = await requestedBeforeClosing();
      system.finish(id, content);
      sibling('.descargando').renameSync(target.path);

      expect(await openApp().fetch(url: url, target: target), 10);
      expect(sibling('.descarga').existsSync(), isFalse);
      expect(system.removed, [id]);
    });

    test('si falló con la app cerrada, dice por qué y la olvida: el próximo '
        'intento pide una nueva', () async {
      final id = await requestedBeforeClosing();
      system.fail(id, httpStatus: 401);

      final reopened = openApp();
      await expectLater(
        reopened.fetch(url: url, target: target),
        throwsA(
          isA<ModelDownloadHttpException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
      expect(sibling('.descarga').existsSync(), isFalse);
      expect(await reopened.isInFlight(target), isFalse);

      final retry = reopened.fetch(url: url, target: target);
      await until(() => system.enqueued.length == 2);
      system.finish(system.onlyId, content);
      expect(await retry, 10);
    });

    test('una descarga que el sistema olvidó no cuenta como en curso: '
        'engancharse empezaría una que nadie pidió', () async {
      target.parent.createSync(recursive: true);
      sibling('.descarga').writeAsStringSync('99\n$url');

      expect(await openApp().isInFlight(target), isFalse);
      expect(sibling('.descarga').existsSync(), isFalse);
    });
  });

  test('sin lugar para el modelo no se pide nada', () async {
    system.free = 50;

    await expectLater(
      openApp().fetch(url: url, target: target, expectedBytes: 100),
      throwsA(
        isA<InsufficientStorageException>()
            .having((e) => e.requiredBytes, 'requiredBytes', 100)
            .having((e) => e.availableBytes, 'availableBytes', 50),
      ),
    );
    expect(system.enqueued, isEmpty);
  });

  test('si el sistema se queda sin lugar a mitad, también lo dice', () async {
    final done = openApp().fetch(url: url, target: target, expectedBytes: 10);
    await until(() => system.enqueued.isNotEmpty);
    system.fail(system.onlyId, error: SystemDownloadError.insufficientSpace);

    await expectLater(done, throwsA(isA<InsufficientStorageException>()));
  });

  test('tocar «Descargar» dos veces espera la misma descarga', () async {
    final transfer = openApp();
    final first = transfer.fetch(url: url, target: target);
    final second = transfer.fetch(url: url, target: target);
    await until(() => system.enqueued.isNotEmpty);
    system.finish(system.onlyId, content);

    expect(await Future.wait([first, second]), [10, 10]);
    expect(system.enqueued, hasLength(1));
  });

  test('cancelar la corta en el sistema, borra lo bajado y quien esperaba se '
      'entera', () async {
    final transfer = openApp();
    final done = transfer.fetch(url: url, target: target);
    await until(() => system.enqueued.isNotEmpty);
    final id = system.onlyId;
    system.progress(id, content.take(5).toList(), 10);

    await transfer.cancel(target);

    await expectLater(done, throwsA(isA<ModelDownloadCancelledException>()));
    expect(system.removed, [id]);
    expect(sibling('.descargando').existsSync(), isFalse);
    expect(sibling('.descarga').existsSync(), isFalse);
    expect(await transfer.isInFlight(target), isFalse);
  });

  test('pedida para otra dirección: se olvida la vieja y se pide la '
      'nueva', () async {
    target.parent.createSync(recursive: true);
    final old = await system.enqueue(
      url: 'https://huggingface.co/otra/url',
      destination: sibling('.descargando'),
    );
    sibling(
      '.descarga',
    ).writeAsStringSync('$old\nhttps://huggingface.co/otra/url');

    final transfer = openApp();
    final done = transfer.fetch(url: url, target: target);
    await until(() => system.enqueued.length == 2);

    expect(system.removed, [old]);
    expect(system.enqueued.last.url, url);
    system.finish(system.downloads.keys.last, content);
    expect(await done, 10);
  });

  test('lo que no pasa la comprobación se borra y no toma su nombre', () async {
    final done = openApp().fetch(
      url: url,
      target: target,
      verify: (_) async => throw const FormatException('huella distinta'),
    );
    await until(() => system.enqueued.isNotEmpty);
    system.finish(system.onlyId, content);

    await expectLater(done, throwsA(isA<FormatException>()));
    expect(target.existsSync(), isFalse);
    expect(sibling('.descargando').existsSync(), isFalse);
    expect(sibling('.descarga').existsSync(), isFalse);
  });

  test('lo que había con el nombre definitivo sin estar entero se descarta '
      'antes de pedirlo: el sistema no escribe sobre un archivo', () async {
    target
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([9, 9]);

    final done = openApp().fetch(url: url, target: target);
    await until(() => system.enqueued.isNotEmpty);

    expect(target.existsSync(), isFalse);
    system.finish(system.onlyId, content);
    expect(await done, 10);
    expect(target.readAsBytesSync(), content);
  });
}
