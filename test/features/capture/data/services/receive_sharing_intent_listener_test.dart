import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:sinapsis/features/capture/data/services/receive_sharing_intent_listener.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';

void main() {
  // El plugin habla por un MethodChannel/EventChannel de verdad, y eso
  // necesita el binding de Flutter inicializado aunque estas sean pruebas de
  // Dart puro sin un solo widget.
  TestWidgetsFlutterBinding.ensureInitialized();

  const listener = ReceiveSharingIntentListener();
  // La instancia real, capturada antes de que ningún test la reemplace con
  // `setMockValues`: es lo único que permite reproducir "no hay plugin del
  // otro lado" sin depender de una clase interna del paquete.
  final realInstance = ReceiveSharingIntent.instance;
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sinapsis_shared_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
    // El mock del plugin es un estado global: sin resetearlo, lo que deja
    // una prueba seguiría contestando en la siguiente.
    ReceiveSharingIntent.setMockValues(
      initialMedia: const [],
      mediaStream: const Stream.empty(),
    );
  });

  File writeFile(String name, String content) =>
      File('${tempDir.path}/$name')..writeAsStringSync(content);

  /// Un archivo del tamaño que se pida, sin escribir de verdad esos bytes
  /// en disco: `truncateSync` extiende el archivo a [length] dejando un
  /// hueco, no reservando contenido — de sobra para que `File.lengthSync()`
  /// —lo único que lee el chequeo de tamaño— informe lo que hace falta.
  File writeFileOfSize(String name, int length) {
    final file = File('${tempDir.path}/$name')..createSync();
    file.openSync(mode: FileMode.write)
      ..truncateSync(length)
      ..closeSync();
    return file;
  }

  group('initial()', () {
    test('un enlace compartido se ofrece como texto, igual que si se '
        'hubiera pegado a mano', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(
            path: 'https://ejemplo.org/articulo',
            type: SharedMediaType.url,
          ),
        ],
        mediaStream: const Stream.empty(),
      );

      final requests = await listener.initial();

      expect(requests, [
        const CaptureRequest.text(rawInput: 'https://ejemplo.org/articulo'),
      ]);
    });

    test('un texto suelto compartido también se ofrece como texto', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(path: 'una idea suelta', type: SharedMediaType.text),
        ],
        mediaStream: const Stream.empty(),
      );

      final requests = await listener.initial();

      expect(requests, [
        const CaptureRequest.text(rawInput: 'una idea suelta'),
      ]);
    });

    test('una imagen compartida se lee de la copia temporal que hizo el '
        'plugin', () async {
      final file = writeFile('foto.jpg', 'contenido de mentira');
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(
            path: file.path,
            type: SharedMediaType.image,
            mimeType: 'image/jpeg',
          ),
        ],
        mediaStream: const Stream.empty(),
      );

      final requests = await listener.initial();

      expect(requests, hasLength(1));
      final captured = requests.single.asFile;
      expect(captured?.name, 'foto.jpg');
      expect(await captured?.readAll(), utf8.encode('contenido de mentira'));
    });

    test(
      'un archivo cualquiera, no solo imagen o video, se lee igual',
      () async {
        final file = writeFile('apuntes.pdf', 'no es un PDF de verdad');
        ReceiveSharingIntent.setMockValues(
          initialMedia: [
            SharedMediaFile(path: file.path, type: SharedMediaType.file),
          ],
          mediaStream: const Stream.empty(),
        );

        final requests = await listener.initial();

        expect(requests.single.asFile?.name, 'apuntes.pdf');
      },
    );

    test('un archivo cuya copia temporal ya no está se descarta en vez de '
        'reventar', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(
            path: '${tempDir.path}/ya-no-existe.pdf',
            type: SharedMediaType.file,
          ),
        ],
        mediaStream: const Stream.empty(),
      );

      final requests = await listener.initial();

      expect(requests, isEmpty);
    });

    test('un archivo más pesado que 500 MB se ofrece igual, sin leerlo '
        'entero', () async {
      // Antes se descartaba en silencio: todo se cargaba en memoria. Ahora
      // se guarda por partes (F21): de acá solo sale su tamaño y su
      // comienzo.
      final file = writeFileOfSize('misa.mp4', CapturedFile.maxBytes + 1);
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(path: file.path, type: SharedMediaType.video),
        ],
        mediaStream: const Stream.empty(),
      );

      final requests = await listener.initial();

      final captured = requests.single.asFile!;
      expect(captured.name, 'misa.mp4');
      expect(captured.sizeInBytes, CapturedFile.maxBytes + 1);
      expect(captured.head.length, CapturedFile.headBytes);
    });

    test('varias cosas compartidas juntas se ofrecen todas, no solo la '
        'primera', () async {
      final file = writeFile('foto.png', 'bytes');
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(
            path: 'https://ejemplo.org',
            type: SharedMediaType.url,
          ),
          SharedMediaFile(path: file.path, type: SharedMediaType.image),
        ],
        mediaStream: const Stream.empty(),
      );

      final requests = await listener.initial();

      expect(requests, hasLength(2));
    });

    test('preguntar dos veces no repite lo mismo', () async {
      // Sin este aviso al plugin, lo que arrancó la app se procesaría de
      // nuevo cada vez que algo más vuelva a preguntar por getInitialMedia().
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(
            path: 'https://ejemplo.org',
            type: SharedMediaType.url,
          ),
        ],
        mediaStream: const Stream.empty(),
      );

      await listener.initial();
      final second = await listener.initial();

      expect(second, isEmpty);
    });

    test('sin nada del otro lado del canal —sin configurar en esta '
        'plataforma, o corriendo en un test— no revienta', () async {
      // A propósito, sin `setMockValues`: reproduce exactamente lo que pasa
      // en una plataforma donde el plugin nativo no tiene con qué contestar.
      ReceiveSharingIntent.instance = realInstance;

      expect(await listener.initial(), isEmpty);
    });
  });

  group('stream', () {
    test('lo que llega mientras la app está abierta se ofrece igual que lo '
        'inicial', () async {
      final controller = StreamController<List<SharedMediaFile>>();
      addTearDown(controller.close);
      ReceiveSharingIntent.setMockValues(
        initialMedia: const [],
        mediaStream: controller.stream,
      );

      final events = <List<CaptureRequest>>[];
      final subscription = listener.stream.listen(events.add);
      addTearDown(subscription.cancel);

      controller.add([
        SharedMediaFile(
          path: 'una nota compartida',
          type: SharedMediaType.text,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(events, [
        [const CaptureRequest.text(rawInput: 'una nota compartida')],
      ]);
    });

    test('un lote que queda vacío tras descartar archivos rotos no se '
        'ofrece', () async {
      final controller = StreamController<List<SharedMediaFile>>();
      addTearDown(controller.close);
      ReceiveSharingIntent.setMockValues(
        initialMedia: const [],
        mediaStream: controller.stream,
      );

      final events = <List<CaptureRequest>>[];
      final subscription = listener.stream.listen(events.add);
      addTearDown(subscription.cancel);

      controller.add([
        SharedMediaFile(
          path: '${tempDir.path}/no-existe.jpg',
          type: SharedMediaType.image,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });
  });
}
