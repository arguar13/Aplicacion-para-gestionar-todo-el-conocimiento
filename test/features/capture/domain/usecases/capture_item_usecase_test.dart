import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/capture/data/adapters/file_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/plain_text_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/web_link_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/youtube_link_adapter.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter_registry.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/usecases/capture_item_usecase.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Prueba el camino completo —adaptador, guardado y lectura— contra la base
/// real, no contra un repositorio simulado.
///
/// Capturar es la única puerta de entrada de contenido a la app: si acá algo
/// se guarda mal, no hay pantalla ni función posterior que lo arregle. Con un
/// repositorio de mentira se estaría probando que el caso de uso llama a
/// alguien, no que lo capturado quede realmente guardado y se pueda
/// encontrar.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl repository;
  late InMemoryFileStore files;
  late CaptureItemUseCase captureItem;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 11, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    files = InMemoryFileStore();
    repository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: files,
    );
    ids = FakeIdGenerator();

    captureItem = CaptureItemUseCase(
      registry: SourceAdapterRegistry([
        YouTubeLinkAdapter(ids: ids, clock: () => now),
        WebLinkAdapter(ids: ids, clock: () => now),
        PlainTextAdapter(ids: ids, clock: () => now),
      ]),
      repository: repository,
    );
  });

  tearDown(() => db.close());

  Future<int> countStored() async {
    final items = (await repository.list(
      const LibraryQuery(),
    )).getRight().toNullable()!;
    return items.length;
  }

  group('archivos grandes (F21): sin tope fijo, el límite es el espacio '
      'libre', () {
    CaptureItemUseCase withFreeBytes(int? free) => CaptureItemUseCase(
      registry: SourceAdapterRegistry([
        FileAdapter(files: files, ids: ids, clock: () => now),
      ]),
      repository: repository,
      freeBytes: () async => free,
    );

    /// Un archivo que dice pesar [size] sin ocupar esa memoria de verdad.
    CapturedFile fileOfSize(String name, int size) => CapturedFile.onDisk(
      name: name,
      sizeInBytes: size,
      head: Uint8List.fromList(utf8.encode('contenido')),
      openRead: () => Stream.value(utf8.encode('contenido')),
    );

    test('un video de varios GB que entra en el espacio libre se '
        'guarda', () async {
      const gb = 1024 * 1024 * 1024;
      final result = await withFreeBytes(10 * gb)(
        CaptureRequest.file(file: fileOfSize('misa.mp4', 3 * gb)),
      );

      expect(result.isRight(), isTrue);
      expect(await countStored(), 1);
    });

    test('uno que no entra se rechaza antes de copiar nada, diciendo '
        'cuánto falta', () async {
      final result = await withFreeBytes(100 * 1024 * 1024)(
        CaptureRequest.file(file: fileOfSize('misa.mp4', 500 * 1024 * 1024)),
      );

      expect(
        result.getLeft().toNullable(),
        isA<NotEnoughSpaceFailure>()
            .having((f) => f.neededBytes, 'necesario', 500 * 1024 * 1024)
            .having((f) => f.freeBytes, 'libre', 100 * 1024 * 1024),
      );
      expect(await countStored(), 0);
    });

    test('si no se puede saber el espacio libre, no se frena nada', () async {
      final result = await withFreeBytes(null)(
        CaptureRequest.file(file: fileOfSize('misa.mp4', 1024)),
      );

      expect(result.isRight(), isTrue);
    });
  });

  group('validación', () {
    test('una entrada vacía no guarda nada', () async {
      final result = await captureItem(const CaptureRequest.text(rawInput: ''));

      expect(result.isLeft(), isTrue);
      result.getLeft().fold(
        () => fail('se esperaba un Failure'),
        (f) => expect(f, isA<ValidationFailure>()),
      );
      expect(await countStored(), 0);
    });

    test('una entrada de solo espacios tampoco', () async {
      final result = await captureItem(
        const CaptureRequest.text(rawInput: '   \n\t  '),
      );

      expect(result.isLeft(), isTrue);
      expect(await countStored(), 0);
    });
  });

  group('captura de verdad', () {
    test('una nota queda guardada, buscable y con su contenido', () async {
      await captureItem(
        const CaptureRequest.text(
          rawInput: 'La estructura de las revoluciones\n\nHabla de paradigmas.',
        ),
      );

      final found = (await repository.list(
        const LibraryQuery(searchText: 'paradigmas'),
      )).getRight().toNullable()!;

      expect(found, hasLength(1));
      expect(found.single.title, 'La estructura de las revoluciones');
      expect(found.single.source.kind, SourceKind.manualNote);
      expect(found.single.searchableText, contains('paradigmas'));
    });

    test('un enlace queda guardado con su procedencia intacta', () async {
      const url = 'https://ejemplo.org/blog/un-articulo-interesante';

      await captureItem(const CaptureRequest.text(rawInput: url));

      final found = (await repository.list(
        const LibraryQuery(),
      )).getRight().toNullable()!;

      expect(found, hasLength(1));
      // Lo que no puede perderse nunca: de dónde salió.
      expect(found.single.source.url, url);
      expect(found.single.source.kind, SourceKind.webPage);
      expect(found.single.title, 'Un articulo interesante');
    });

    test('un video de YouTube queda marcado como tal y pendiente de '
        'transcripción', () async {
      await captureItem(
        const CaptureRequest.text(
          rawInput: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
      );

      final found = (await repository.list(
        const LibraryQuery(),
      )).getRight().toNullable()!;

      expect(found.single.source.kind, SourceKind.youtube);
      expect(found.single.processingState, ProcessingState.pending);
    });

    test('capturar dos cosas guarda dos elementos distintos, no uno que pisa '
        'al otro', () async {
      await captureItem(const CaptureRequest.text(rawInput: 'primera nota'));
      await captureItem(const CaptureRequest.text(rawInput: 'segunda nota'));

      expect(await countStored(), 2);
    });

    test('la nota del usuario se guarda aparte del contenido', () async {
      await captureItem(
        const CaptureRequest.text(
          rawInput: 'https://ejemplo.org/algo-util',
          note: 'me lo recomendó Ana',
        ),
      );

      final found = (await repository.list(
        const LibraryQuery(),
      )).getRight().toNullable()!;

      expect(found.single.notes, 'me lo recomendó Ana');
    });

    test('lo capturado se puede filtrar por su tipo de fuente', () async {
      await captureItem(const CaptureRequest.text(rawInput: 'una nota'));
      await captureItem(
        const CaptureRequest.text(rawInput: 'https://ejemplo.org/a'),
      );
      await captureItem(
        const CaptureRequest.text(rawInput: 'https://youtu.be/dQw4w9WgXcQ'),
      );

      final videos = (await repository.list(
        const LibraryQuery(sourceKinds: {SourceKind.youtube}),
      )).getRight().toNullable()!;

      expect(videos, hasLength(1));
      expect(videos.single.source.kind, SourceKind.youtube);
    });

    test('lo pendiente se puede separar de lo que ya está listo', () async {
      await captureItem(const CaptureRequest.text(rawInput: 'una nota'));
      await captureItem(
        const CaptureRequest.text(rawInput: 'https://ejemplo.org/a'),
      );

      final pending = (await repository.list(
        const LibraryQuery(processingStates: {ProcessingState.pending}),
      )).getRight().toNullable()!;

      expect(pending, hasLength(1));
      expect(pending.single.source.kind, SourceKind.webPage);
    });
  });

  group('el tema elegido al capturar', () {
    Future<void> seedSpace(String id, String name) => db
        .into(db.spaces)
        .insert(SpacesCompanion.insert(id: id, name: name, createdAt: now));

    test('lo guardado queda en ese tema, en el mismo guardado', () async {
      await seedSpace('tema-historia', 'Historia');

      final result = await captureItem(
        const CaptureRequest.text(
          rawInput: 'https://ejemplo.org/roma',
          spaceId: 'tema-historia',
        ),
      );

      expect(result.getRight().toNullable()!.spaceId, 'tema-historia');
      final inSpace = (await repository.list(
        const LibraryQuery(spaceId: 'tema-historia'),
      )).getRight().toNullable()!;
      expect(inSpace, hasLength(1));
    });

    test('un archivo también', () async {
      await seedSpace('tema-tesis', 'Tesis');
      final withFiles = CaptureItemUseCase(
        registry: SourceAdapterRegistry([
          FileAdapter(files: files, ids: ids, clock: () => now),
        ]),
        repository: repository,
      );

      final result = await withFiles(
        CaptureRequest.file(
          file: CapturedFile(
            name: 'capitulo.pdf',
            bytes: Uint8List.fromList(utf8.encode('%PDF-1.7 el contenido')),
          ),
          spaceId: 'tema-tesis',
        ),
      );

      expect(result.getRight().toNullable()!.spaceId, 'tema-tesis');
    });

    test('sin tema, queda sin clasificar', () async {
      final result = await captureItem(
        const CaptureRequest.text(rawInput: 'una nota suelta'),
      );

      expect(result.getRight().toNullable()!.spaceId, isNull);
    });

    test('un tema que ya no existe no deja nada guardado a medias', () async {
      // Asignarlo en un segundo paso podría dejar el elemento guardado sin
      // su tema; yendo en el mismo guardado, o queda todo o no queda nada.
      final result = await captureItem(
        const CaptureRequest.text(
          rawInput: 'algo para un tema borrado',
          spaceId: 'tema-que-no-existe',
        ),
      );

      expect(result.isLeft(), isTrue);
      expect(await countStored(), 0);
    });
  });
}
