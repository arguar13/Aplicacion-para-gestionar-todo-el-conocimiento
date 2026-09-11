import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/capture/data/adapters/plain_text_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/web_link_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/youtube_link_adapter.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter_registry.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
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
}
