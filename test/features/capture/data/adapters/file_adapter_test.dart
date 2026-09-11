import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/capture/data/adapters/file_adapter.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/sample_files.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);
  late InMemoryFileStore files;
  late FileAdapter adapter;

  setUp(() {
    files = InMemoryFileStore();
    adapter = FileAdapter(
      files: files,
      ids: FakeIdGenerator(),
      clock: () => now,
    );
  });

  CaptureRequest capture(
    Uint8List bytes, {
    String name = 'apunte.pdf',
    String? title,
    String? note,
  }) => CaptureRequest.file(
    file: CapturedFile(name: name, bytes: bytes),
    title: title,
    note: note,
  );

  Uint8List pdf() => Uint8List.fromList(utf8.encode('%PDF-1.7 contenido'));

  group('a qué se aplica', () {
    test('a una captura de archivo', () {
      expect(adapter.canHandle(capture(pdf())), isTrue);
    });

    test('NO a una captura de texto', () {
      const texto = CaptureRequest.text(rawInput: 'https://ejemplo.org/a');

      expect(adapter.canHandle(texto), isFalse);
    });
  });

  group('el archivo se guarda antes que el elemento', () {
    test('los bytes quedan en el almacen', () async {
      // El archivo ES la fuente: no hay ningun sitio al que volver si se
      // pierde. Y la ruta por la que llego suele ser temporal —el sistema la
      // borra en cuanto la app que lo compartio termina— asi que copiarlo es
      // lo unico que garantiza que sobreviva.
      final item = await adapter.adapt(capture(pdf()));

      final path = item.source.originalFilePath;
      expect(path, isNotNull);
      expect(await files.read(path!), pdf());
    });

    test('el elemento apunta al archivo guardado, no al de origen', () async {
      final item = await adapter.adapt(capture(pdf()));

      expect(item.source.originalFilePath, startsWith('originales/'));
    });

    test('no inventa un enlace de origen', () async {
      // Un PDF del disco no vino de ninguna direccion web. Rellenar `url` con
      // algo haria que el detalle ofreciera "abrir el original" y llevara a
      // ninguna parte.
      final item = await adapter.adapt(capture(pdf()));

      expect(item.source.url, isNull);
    });
  });

  group('de que clase de fuente se trata', () {
    test('un PDF es un documento', () async {
      final item = await adapter.adapt(capture(pdf()));

      expect(item.source.kind, SourceKind.document);
      expect(item.subtitle, 'PDF');
    });

    test('un EPUB tambien, y se distingue en el subtitulo', () async {
      final item = await adapter.adapt(
        capture(buildEpub(), name: 'un-libro.epub'),
      );

      expect(item.source.kind, SourceKind.document);
      expect(item.subtitle, 'EPUB');
    });

    test('una imagen es una imagen', () async {
      final item = await adapter.adapt(
        capture(
          withSignature([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
          name: 'captura.png',
        ),
      );

      expect(item.source.kind, SourceKind.image);
      expect(item.subtitle, 'Imagen');
    });

    test('lo decide el contenido, no la extension', () async {
      // Un PDF renombrado a .txt sigue siendo un PDF.
      final item = await adapter.adapt(capture(pdf(), name: 'apunte.txt'));

      expect(item.subtitle, 'PDF');
    });

    test('lo que no se reconoce se guarda igual', () async {
      // Perder el archivo seria lo peor que podria pasar. Que no se le pueda
      // sacar texto es otro problema, y menor.
      final item = await adapter.adapt(
        capture(Uint8List.fromList([1, 2, 3]), name: 'cosa.xyz'),
      );

      expect(item.subtitle, 'Archivo');
      expect(await files.read(item.source.originalFilePath!), isNotNull);
    });
  });

  group('el titulo provisional', () {
    test('sale del nombre del archivo, legible', () async {
      final item = await adapter.adapt(
        capture(pdf(), name: 'informe_final_v3_DEFINITIVO.pdf'),
      );

      expect(item.title, 'Informe final v3 DEFINITIVO');
    });

    test('un titulo escrito a mano gana sobre el deducido', () async {
      final item = await adapter.adapt(
        capture(pdf(), name: 'doc1.pdf', title: 'La tesis de Ana'),
      );

      expect(item.title, 'La tesis de Ana');
    });

    test('un titulo en blanco no gana: se usa el deducido', () async {
      final item = await adapter.adapt(
        capture(pdf(), name: 'la-tesis.pdf', title: '   '),
      );

      expect(item.title, 'La tesis');
    });

    test('un archivo sin nombre no queda con el titulo vacio', () async {
      final item = await adapter.adapt(capture(pdf(), name: ''));

      expect(item.title, 'Archivo sin nombre');
    });
  });

  group('lo demas', () {
    test('queda pendiente: el texto lo extrae la transformacion', () async {
      final item = await adapter.adapt(capture(pdf()));

      expect(item.processingState, ProcessingState.pending);
      expect(item.renditions, isEmpty);
    });

    test('la nota del usuario se conserva', () async {
      final item = await adapter.adapt(capture(pdf(), note: 'para el jueves'));

      expect(item.notes, 'para el jueves');
    });

    test('la fecha de captura es la del reloj', () async {
      final item = await adapter.adapt(capture(pdf()));

      expect(item.source.capturedAt, now);
      expect(item.createdAt, now);
    });
  });
}
