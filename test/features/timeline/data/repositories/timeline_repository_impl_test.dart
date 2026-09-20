import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/timeline/data/repositories/timeline_repository_impl.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../timeline_fixtures.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

class MockLibraryRepository extends Mock implements LibraryRepository {}

/// La lectura de eventos contra SQLite real: los elementos se guardan y se
/// fechan por el camino de la app, para que las filas sean las que produce de
/// verdad y no una simulación.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late OrganizeRepositoryImpl organize;
  late TimelineRepositoryImpl timeline;
  late String fechaId;
  late String temaId;

  final now = DateTime(2026, 9, 11, 10);

  setUpAll(() => registerFallbackValue(const LibraryQuery()));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(),
      clock: () => now,
    );
    timeline = TimelineRepositoryImpl(
      database: db,
      library: library,
      telemetry: MockTelemetryService(),
    );

    Future<String> systemCategory(String name) async {
      final row =
          await (db.select(db.propertyDefinitions)
                ..where((d) => d.isSystem.equals(true) & d.name.equals(name)))
              .getSingle();
      return row.id;
    }

    fechaId = await systemCategory(kFechaDelHechoCategoryName);
    temaId = await systemCategory(kTemaCategoryName);
  });

  tearDown(() => db.close());

  Future<void> seedItem(
    String id, {
    String? title,
    SourceKind kind = SourceKind.webPage,
  }) async {
    final isNote = kind == SourceKind.manualNote;
    await library.save(
      KnowledgeItem(
        id: id,
        title: title ?? 'Elemento $id',
        source: Source(
          id: 'src-$id',
          kind: kind,
          capturedAt: now,
          url: isNote ? null : 'https://ejemplo.org/$id',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          if (isNote)
            Rendition.text(
              id: 'rend-$id',
              itemId: id,
              kind: RenditionKind.blocks,
              content: encodeContentBlocks([
                const ContentBlock.paragraph(text: 'texto'),
              ]),
              isPrimary: true,
              createdAt: now,
            ),
        ],
      ),
    );
  }

  Future<void> setDate(
    String itemId,
    HistoricalDate date, {
    String? definitionId,
  }) async {
    final target = definitionId ?? fechaId;
    final value = (await organize.getOrCreateHistoricalPropertyValue(
      definitionId: target,
      date: date,
    )).getRight().toNullable()!;
    await organize.assignProperty(
      itemId: itemId,
      definitionId: target,
      value: value.value,
    );
  }

  Future<List<TimelineEvent>> read([
    LibraryQuery filter = const LibraryQuery(),
  ]) => timeline.watchEvents(filter).first;

  List<String> ids(List<TimelineEvent> events) =>
      events.map((e) => e.itemId).toList();

  group('lectura', () {
    test('sin ninguna fecha puesta no hay eventos', () async {
      await seedItem('a');

      expect(await read(), isEmpty);
    });

    test('un elemento con fecha es un evento con su título, su fecha y de '
        'qué es', () async {
      await seedItem('roma', title: 'Caída de Roma');
      await setDate('roma', dateOf(476));

      final events = await read();

      expect(events, hasLength(1));
      expect(events.single.itemId, 'roma');
      expect(events.single.title, 'Caída de Roma');
      expect(events.single.date, dateOf(476));
      expect(events.single.sourceKind, SourceKind.webPage);
      expect(events.single.noteKind, isNull);
    });

    test('el título y el tipo de fuente salen de item y de source, no de las '
        'tablas viejas', () async {
      await seedItem('roma', title: 'Roma');
      await setDate('roma', dateOf(476));
      // Se cambia SOLO el modelo nuevo: si la lectura saliera del viejo, no se
      // vería.
      await (db.update(db.knowledgeEntries)..where((e) => e.id.equals('roma')))
          .write(const KnowledgeEntriesCompanion(title: Value('De ahora')));
      await (db.update(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals('roma'))).write(
        const KnowledgeSourcesCompanion(sourceType: Value(SourceKind.document)),
      );

      final event = (await read()).single;

      expect(event.title, 'De ahora');
      expect(event.sourceKind, SourceKind.document);
    });

    test('una nota trae su subtipo', () async {
      await seedItem('n', kind: SourceKind.manualNote);
      await setDate('n', dateOf(1453));

      final events = await read();

      expect(events.single.sourceKind, SourceKind.manualNote);
      expect(events.single.noteKind, NoteKind.living);
    });

    test('con dos fechas, dos eventos del mismo elemento', () async {
      await seedItem('roma');
      await setDate('roma', dateOf(753, bce: true));
      await setDate('roma', dateOf(476));

      final events = await read();

      expect(ids(events), ['roma', 'roma']);
      expect(events.map((e) => e.date), [dateOf(753, bce: true), dateOf(476)]);
    });

    test('sale en orden cronológico: a.C. antes que d.C., sin saltos en el '
        'cero', () async {
      for (final (id, date) in [
        ('constantinopla', dateOf(1453)),
        ('caida', dateOf(476)),
        ('era', dateOf(1)),
        ('cesar', dateOf(44, bce: true)),
        ('cristo', dateOf(1, bce: true)),
      ]) {
        await seedItem(id);
        await setDate(id, date);
      }

      expect(ids(await read()), [
        'cesar',
        'cristo',
        'era',
        'caida',
        'constantinopla',
      ]);
    });

    test('conserva la precisión, el mes, el día y el circa', () async {
      const dates = {
        'dia': HistoricalDate(
          year: 1969,
          precision: DatePrecision.day,
          month: 7,
          day: 20,
        ),
        'mes': HistoricalDate(
          year: 44,
          precision: DatePrecision.month,
          month: 3,
          isBce: true,
        ),
        'decada': HistoricalDate(year: 1920, precision: DatePrecision.decade),
        'siglo': HistoricalDate(
          year: 200,
          precision: DatePrecision.century,
          isBce: true,
          isCirca: true,
        ),
      };
      for (final entry in dates.entries) {
        await seedItem(entry.key);
        await setDate(entry.key, entry.value);
      }

      final byItem = {for (final e in await read()) e.itemId: e.date};

      expect(byItem, dates);
    });

    test('las fechas de otra categoría de tipo fecha no cuentan', () async {
      // Categoría de usuario: la línea de tiempo es de "Fecha del hecho".
      final nacimiento = (await organize.getOrCreatePropertyDefinition(
        'Nacimiento',
        type: PropertyValueType.date,
      )).getRight().toNullable()!;
      await seedItem('a');
      await setDate('a', dateOf(1809), definitionId: nacimiento.id);

      expect(await read(), isEmpty);
    });

    test('un valor de la categoría que no es una fecha no cuenta ni '
        'rompe la lectura', () async {
      await seedItem('a');
      await organize.assignProperty(
        itemId: 'a',
        definitionId: fechaId,
        value: 'hace mucho',
      );
      await seedItem('b');
      await setDate('b', dateOf(476));

      expect(ids(await read()), ['b']);
    });
  });

  group('filtros de la biblioteca', () {
    setUp(() async {
      await seedItem('web', title: 'Imperio romano en la web');
      await seedItem(
        'nota',
        title: 'Imperio bizantino',
        kind: SourceKind.manualNote,
      );
      await seedItem('otro', title: 'Revolución francesa');
      await setDate('web', dateOf(476));
      await setDate('nota', dateOf(1453));
      await setDate('otro', dateOf(1789));
    });

    test('sin filtro entran todos', () async {
      expect(ids(await read()), ['web', 'nota', 'otro']);
    });

    test('por tipo de fuente', () async {
      final events = await read(
        const LibraryQuery(sourceKinds: {SourceKind.manualNote}),
      );

      expect(ids(events), ['nota']);
    });

    test('por texto', () async {
      final events = await read(const LibraryQuery(searchText: 'imperio'));

      expect(ids(events), ['web', 'nota']);
    });

    test('por propiedad', () async {
      await organize.assignProperty(
        itemId: 'otro',
        definitionId: temaId,
        value: 'Historia moderna',
      );
      final valueId =
          await (db.select(db.propertyValues)..where(
                (v) =>
                    v.definitionId.equals(temaId) &
                    v.value.equals('Historia moderna'),
              ))
              .map((v) => v.id)
              .getSingle();

      final events = await read(LibraryQuery(propertyValueIds: {valueId}));

      expect(ids(events), ['otro']);
    });

    test('los filtros se combinan: cumple todos', () async {
      final events = await read(
        const LibraryQuery(
          searchText: 'imperio',
          sourceKinds: {SourceKind.webPage},
        ),
      );

      expect(ids(events), ['web']);
    });

    test('un filtro que no deja pasar nada da una lista vacía', () async {
      final events = await read(const LibraryQuery(searchText: 'inexistente'));

      expect(events, isEmpty);
    });

    test('el orden y la página de la consulta no recortan el eje', () async {
      final events = await read(
        const LibraryQuery(limit: 1, offset: 1, sortBy: LibrarySort.title),
      );

      expect(ids(events), ['web', 'nota', 'otro']);
    });

    test('un elemento con varias fechas aparece una vez por fecha dentro del '
        'filtro', () async {
      await setDate('otro', dateOf(1799));

      final events = await read(
        const LibraryQuery(sourceKinds: {SourceKind.webPage}),
      );

      // "web" y las dos fechas de "otro"; la nota queda fuera.
      expect(ids(events), ['web', 'otro', 'otro']);
    });
  });

  group('actualización', () {
    test('poner una fecha emite el evento nuevo', () async {
      await seedItem('roma');

      final emissions = timeline.watchEvents(const LibraryQuery());
      final expectation = expectLater(
        emissions,
        emitsThrough(
          predicate<List<TimelineEvent>>(
            (events) => events.length == 1 && events.single.itemId == 'roma',
          ),
        ),
      );
      await setDate('roma', dateOf(476));

      await expectation.timeout(const Duration(seconds: 5));
    });

    test('borrar el elemento saca su evento', () async {
      await seedItem('roma');
      await setDate('roma', dateOf(476));

      final emissions = timeline.watchEvents(const LibraryQuery());
      final expectation = expectLater(emissions, emitsThrough(isEmpty));
      await library.delete('roma');

      await expectation.timeout(const Duration(seconds: 5));
    });

    test('cambiar el título del elemento lo refleja el evento', () async {
      await seedItem('roma', title: 'Roma');
      await setDate('roma', dateOf(476));

      final emissions = timeline.watchEvents(const LibraryQuery());
      final expectation = expectLater(
        emissions,
        emitsThrough(
          predicate<List<TimelineEvent>>(
            (events) => events.single.title == 'Caída de Roma',
          ),
        ),
      );
      final item = (await library.findById('roma')).getRight().toNullable()!;
      await library.save(item.copyWith(title: 'Caída de Roma'));

      await expectation.timeout(const Duration(seconds: 5));
    });
  });

  group('cuando la biblioteca no puede resolver el filtro', () {
    test('el stream lo avisa como error y no queda esperando', () async {
      final failing = MockLibraryRepository();
      when(() => failing.matchingIds(any())).thenAnswer(
        (_) async => left(const Failure.unexpected(message: 'sin base')),
      );
      final repository = TimelineRepositoryImpl(
        database: db,
        library: failing,
        telemetry: MockTelemetryService(),
      );

      await expectLater(
        repository.watchEvents(const LibraryQuery(searchText: 'algo')),
        emitsError(
          isA<Exception>().having(
            (e) => e.toString(),
            'mensaje',
            contains('sin base'),
          ),
        ),
      );
    });

    test('sin filtro ni siquiera se le pregunta a la biblioteca', () async {
      final unused = MockLibraryRepository();
      final repository = TimelineRepositoryImpl(
        database: db,
        library: unused,
        telemetry: MockTelemetryService(),
      );

      await repository.watchEvents(const LibraryQuery()).first;

      verifyNever(() => unused.matchingIds(any()));
    });
  });
}
