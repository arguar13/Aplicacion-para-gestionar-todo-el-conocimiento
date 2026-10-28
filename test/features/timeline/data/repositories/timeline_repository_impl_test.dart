import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
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
import 'package:sinapsis/features/timeline/data/repositories/dated_event_repository_impl.dart';
import 'package:sinapsis/features/timeline/data/repositories/timeline_repository_impl.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_axis.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/processed_rows.dart';
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

  /// Un documento procesado de una fuente de tipo [kind]: lo que la línea de
  /// tiempo lee desde F41 (paso 6).
  Future<void> seedItem(
    String id, {
    String? title,
    SourceKind kind = SourceKind.webPage,
  }) => insertProcessedDocument(
    db,
    id: id,
    title: title ?? 'Elemento $id',
    createdAt: now,
    sourceKind: kind,
  );

  /// Una fuente de la Biblioteca, por el camino de la app: no entra.
  Future<void> seedLibrarySource(String id) async {
    await library.save(
      KnowledgeItem(
        id: id,
        title: 'Fuente $id',
        source: Source(
          id: 'src-$id',
          kind: SourceKind.webPage,
          capturedAt: now,
          url: 'https://ejemplo.org/$id',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Una nota de la persona, por el camino de la app.
  Future<void> seedNote(String id) async {
    await library.save(
      KnowledgeItem(
        id: id,
        title: 'Nota $id',
        source: Source(
          id: 'src-$id',
          kind: SourceKind.manualNote,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
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

  /// Lo que muestra la línea de tiempo: lo procesado, con [filter].
  Future<List<TimelineEvent>> read([
    LibraryQuery filter = const LibraryQuery(),
  ]) => timeline
      .watchEvents(filter.copyWith(scope: LibraryScope.processed))
      .first;

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
      expect(events.single.noteKind, NoteKind.processed);
    });

    test('el título sale de item y el tipo, del de la fuente que guardó el '
        'procesado', () async {
      await seedItem('roma', title: 'Roma');
      await setDate('roma', dateOf(476));
      // Se cambia SOLO el modelo nuevo: si la lectura saliera del viejo, no se
      // vería.
      await (db.update(db.knowledgeEntries)..where((e) => e.id.equals('roma')))
          .write(const KnowledgeEntriesCompanion(title: Value('De ahora')));
      await (db.update(
        db.processedDocuments,
      )..where((d) => d.itemId.equals('roma'))).write(
        const ProcessedDocumentsCompanion(
          sourceKind: Value(SourceKind.document),
        ),
      );

      final event = (await read()).single;

      expect(event.title, 'De ahora');
      expect(event.sourceKind, SourceKind.document);
    });

    test(
      'un documento procesado trae su subtipo y el tipo de su fuente',
      () async {
        await seedItem('p', kind: SourceKind.youtube);
        await setDate('p', dateOf(1453));

        final events = await read();

        expect(events.single.sourceKind, SourceKind.youtube);
        expect(events.single.noteKind, NoteKind.processed);
      },
    );

    test('lo de la Biblioteca no entra, ni su «Fecha del hecho» ni sus hechos '
        'de la IA: empieza de cero (F41, paso 6)', () async {
      await seedLibrarySource('fuente');
      await setDate('fuente', dateOf(476));
      await seedNote('nota');
      await setDate('nota', dateOf(1453));

      expect(await read(), isEmpty);
    });

    test('el calendario de la Biblioteca lee lo suyo: sus fuentes y sus notas, '
        'con sus fechas y sus hechos, y no lo procesado', () async {
      await seedLibrarySource('fuente');
      await setDate('fuente', dateOf(476));
      await seedNote('nota');
      await setDate('nota', dateOf(1453));
      await seedItem('procesado');
      await setDate('procesado', dateOf(1789));
      await db
          .into(db.datedEvents)
          .insert(
            DatedEventsCompanion.insert(
              id: 'de-la-ia',
              itemId: 'fuente',
              title: 'Un hecho de la fuente',
              dateFromYear: 1859,
              dateFromMonth: 1,
              dateFromDay: 1,
              datePrecision: DatePrecision.year,
              origin: const Value(ContentOrigin.ai),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final library = await timeline.watchEvents(const LibraryQuery()).first;

      expect(
        library.map((e) => e.itemId),
        unorderedEquals(['fuente', 'nota', 'fuente']),
      );
      expect(library.map((e) => e.datedEventId), contains('de-la-ia'));
      // Con un filtro, lo resuelve la Biblioteca en su corpus.
      expect(
        (await timeline
                .watchEvents(
                  const LibraryQuery(sourceKinds: {SourceKind.webPage}),
                )
                .first)
            .map((e) => e.itemId)
            .toSet(),
        {'fuente'},
      );
      expect(ids(await read()), ['procesado']);
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

      final emissions = timeline.watchEvents(
        const LibraryQuery(scope: LibraryScope.processed),
      );
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

      final emissions = timeline.watchEvents(
        const LibraryQuery(scope: LibraryScope.processed),
      );
      final expectation = expectLater(emissions, emitsThrough(isEmpty));
      await library.delete('roma');

      await expectation.timeout(const Duration(seconds: 5));
    });

    test('cambiar el título del elemento lo refleja el evento', () async {
      await seedItem('roma', title: 'Roma');
      await setDate('roma', dateOf(476));

      final emissions = timeline.watchEvents(
        const LibraryQuery(scope: LibraryScope.processed),
      );
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

  group('la papelera (F11)', () {
    test('lo que está en la papelera no es un evento, y vuelve al '
        'restaurarlo', () async {
      await seedItem('roma', title: 'Caída de Roma');
      await seedItem('egipto', title: 'Ramsés');
      await setDate('roma', dateOf(476));
      await setDate('egipto', dateOf(1279, bce: true));
      await trashItemRows(db, 'roma');

      expect(ids(await read()), ['egipto']);

      await restoreItemRows(db, 'roma');

      expect(ids(await read()), unorderedEquals(['roma', 'egipto']));
    });

    test('con un filtro de la biblioteca tampoco', () async {
      await seedItem('roma');
      await setDate('roma', dateOf(476));
      await trashItemRows(db, 'roma');

      expect(
        await read(const LibraryQuery(sourceKinds: {SourceKind.webPage})),
        isEmpty,
      );
    });
  });

  group('hechos fechados dentro de un documento (F40)', () {
    late DatedEventRepositoryImpl facts;

    setUp(() {
      facts = DatedEventRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        ids: FakeIdGenerator(),
        clock: () => now,
      );
    });

    Future<DatedEvent> addFact(
      String itemId,
      String title,
      HistoricalDate date, {
      HistoricalDate? end,
    }) async => (await facts.add(
      itemId,
      DatedEventInput(title: title, date: date, end: end),
    )).getOrElse((f) => fail('$f'));

    test('un elemento sin «Fecha del hecho» aparece por sus hechos, con el '
        'título del hecho', () async {
      await seedItem('darwin', title: 'Biografía de Darwin');
      await addFact('darwin', 'Publica El origen', dateOf(1859));

      final event = (await read()).single;

      expect(event.title, 'Publica El origen');
      expect(event.itemTitle, 'Biografía de Darwin');
      expect(event.documentTitle, 'Biografía de Darwin');
      expect(event.itemId, 'darwin');
      expect(event.isDatedEvent, isTrue);
      expect(event.origin, ContentOrigin.user);
      expect(event.sourceKind, SourceKind.webPage);
    });

    test('los dos orígenes conviven en orden cronológico', () async {
      await seedItem('roma', title: 'Caída de Roma');
      await setDate('roma', dateOf(476));
      await seedItem('darwin', title: 'Darwin');
      await addFact('darwin', 'Nace', dateOf(1809));
      await addFact('darwin', 'Zarpa', dateOf(1831));
      await addFact('darwin', 'Cae un imperio', dateOf(100, bce: true));

      final events = await read();

      expect(events.map((e) => e.title), [
        'Cae un imperio',
        'Caída de Roma',
        'Nace',
        'Zarpa',
      ]);
      expect(events.map((e) => e.datedEventId == null), [
        false,
        true,
        false,
        false,
      ]);
      // La «Fecha del hecho» se lee como siempre: sin cita ni origen.
      final roma = events.firstWhere((e) => e.itemId == 'roma');
      expect(roma.itemTitle, isNull);
      expect(roma.origin, isNull);
      expect(roma.end, isNull);
    });

    test('un hecho con fin ocupa de donde empieza a donde termina', () async {
      await seedItem('guerra');
      final fact = await addFact(
        'guerra',
        'La Gran Guerra',
        dateOf(1914),
        end: dateOf(1918),
      );

      final event = (await read()).single;

      expect(event.datedEventId, fact.id);
      expect(event.end, dateOf(1918));
      expect(event.isRange, isTrue);
      expect(event.isPeriod, isFalse);
      expect(event.from, 1914.0);
      expect(event.to, 1919.0);
    });

    test(
      'el fin conserva su precisión: noviembre de 1918 termina donde empieza '
      'diciembre',
      () async {
        await seedItem('guerra');
        await addFact(
          'guerra',
          'La Gran Guerra',
          dateOf(1914),
          end: const HistoricalDate(
            year: 1918,
            precision: DatePrecision.month,
            month: 11,
          ),
        );

        final event = (await read()).single;

        expect(event.end?.precision, DatePrecision.month);
        expect(event.to, axisStartOfMonth(1918, 12));
      },
    );

    test(
      'el circa difumina por la precisión de la fecha, no por el tramo',
      () async {
        await seedItem('x');
        await addFact(
          'x',
          'Hacia',
          dateOf(1500, circa: true),
          end: dateOf(1520),
        );

        final event = (await read()).single;

        expect(event.fuzz, 0.5);
      },
    );

    test('trae la cita y el texto, y los de la IA se distinguen', () async {
      await seedItem('darwin');
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'texto',
              itemId: 'darwin',
              kind: RenditionKind.plainText,
              content: const Value('En 1859 publicó su libro.'),
              isPrimary: true,
              createdAt: now,
            ),
          );
      await db
          .into(db.aiRuns)
          .insert(
            AiRunsCompanion.insert(
              id: 'pasada',
              itemId: 'darwin',
              startedAt: now,
            ),
          );
      await facts.addFromAi(
        itemId: 'darwin',
        runId: 'pasada',
        drafts: [
          DatedEventInput(
            title: 'Publica',
            date: dateOf(1859),
            renditionId: 'texto',
            startOffset: 0,
            endOffset: 7,
            excerpt: 'En 1859',
          ),
        ],
      );

      final event = (await read()).single;

      expect(event.isAi, isTrue);
      expect(event.renditionId, 'texto');
      expect((event.startOffset, event.endOffset), (0, 7));
      expect(event.excerpt, 'En 1859');
      expect(event.hasAnchor, isTrue);
    });

    test('los filtros de la biblioteca valen para los dos orígenes', () async {
      await seedItem('web', title: 'Imperio romano');
      await seedItem(
        'nota',
        title: 'Imperio bizantino',
        kind: SourceKind.manualNote,
      );
      await seedItem('otro', title: 'Revolución francesa');
      await setDate('web', dateOf(476));
      await setDate('nota', dateOf(1453));
      await setDate('otro', dateOf(1789));
      await addFact('web', 'Odoacro depone a Rómulo', dateOf(476));
      await addFact('nota', 'Cae Constantinopla', dateOf(1453));
      await addFact('otro', 'Toma de la Bastilla', dateOf(1789));

      List<String> titles(List<TimelineEvent> events) => [
        for (final e in events) e.title,
      ];

      expect(await read(), hasLength(6));
      expect(
        titles(await read(const LibraryQuery(searchText: 'Imperio'))),
        unorderedEquals([
          'Imperio romano',
          'Odoacro depone a Rómulo',
          'Imperio bizantino',
          'Cae Constantinopla',
        ]),
      );
      expect(
        titles(
          await read(const LibraryQuery(sourceKinds: {SourceKind.manualNote})),
        ),
        unorderedEquals(['Imperio bizantino', 'Cae Constantinopla']),
      );
      expect(
        titles(await read(const LibraryQuery(ids: {'otro'}))),
        unorderedEquals(['Revolución francesa', 'Toma de la Bastilla']),
      );
      expect(await read(const LibraryQuery(ids: {})), isEmpty);
    });

    test('lo de un elemento en la papelera no aparece, y vuelve al '
        'restaurarlo', () async {
      await seedItem('darwin');
      await seedItem('otro');
      await addFact('darwin', 'Nace', dateOf(1809));
      await addFact('otro', 'Cae', dateOf(1789));
      await trashItemRows(db, 'darwin');

      expect((await read()).map((e) => e.title), ['Cae']);

      await restoreItemRows(db, 'darwin');

      expect((await read()).map((e) => e.title), ['Cae', 'Nace']);
    });

    test('dos hechos del mismo documento en la misma fecha salen siempre '
        'en el mismo orden', () async {
      await seedItem('x');
      final first = await addFact('x', 'Uno', dateOf(1900));
      final second = await addFact('x', 'Dos', dateOf(1900));

      final events = await read();

      expect(
        events.map((e) => e.datedEventId),
        ([first.id, second.id]..sort()),
      );
    });

    test('agregar, editar y quitar un hecho emite de nuevo', () async {
      await seedItem('darwin');
      final seen = <List<String>>[];
      final sub = timeline
          .watchEvents(const LibraryQuery(scope: LibraryScope.processed))
          .listen((events) => seen.add([for (final e in events) e.title]));
      addTearDown(sub.cancel);
      await pumpEventQueue();

      final fact = await addFact('darwin', 'Nace', dateOf(1809));
      await pumpEventQueue();
      await facts.update(
        fact.id,
        title: 'Nace en Shrewsbury',
        date: dateOf(1809),
      );
      await pumpEventQueue();
      await facts.remove(fact.id);
      await pumpEventQueue();

      expect(seen.first, isEmpty);
      expect(seen, contains(equals(['Nace'])));
      expect(seen, contains(equals(['Nace en Shrewsbury'])));
      expect(seen.last, isEmpty);
    });

    group('lo procesado y lo de la persona (F41, paso 6)', () {
      Future<void> fact(
        String id,
        String itemId, {
        ContentOrigin origin = ContentOrigin.user,
        String? renditionId,
      }) => db
          .into(db.datedEvents)
          .insert(
            DatedEventsCompanion.insert(
              id: id,
              itemId: itemId,
              title: 'Hecho $id',
              dateFromYear: 1859,
              dateFromMonth: 1,
              dateFromDay: 1,
              datePrecision: DatePrecision.year,
              origin: Value(origin),
              renditionId: Value(renditionId),
              startOffset: Value(renditionId == null ? null : 0),
              endOffset: Value(renditionId == null ? null : 4),
              createdAt: now,
              updatedAt: now,
            ),
          );

      test(
        'los hechos que la persona escribió en una nota suya —«Hechos '
        'sueltos»— entran; los de la IA en esa nota, o en una fuente, no',
        () async {
          await seedNote('sueltos');
          await seedLibrarySource('fuente');
          await fact('a-mano', 'sueltos');
          await fact('de-la-ia', 'sueltos', origin: ContentOrigin.ai);
          await fact('de-la-fuente', 'fuente');

          final events = await read();

          expect(events.map((e) => e.datedEventId), ['a-mano']);
          // Y el chip «Documento» los encuentra: son esos, sin preguntar a lo
          // procesado.
          expect(
            (await read(
              const LibraryQuery(ids: {'sueltos'}),
            )).map((e) => e.datedEventId),
            ['a-mano'],
          );
        },
      );

      test('la cita de un procesado está en su fuente: el hecho dice de qué '
          'elemento es ese texto', () async {
        await seedLibrarySource('fuente');
        await db
            .into(db.renditions)
            .insert(
              RenditionsCompanion.insert(
                id: 'texto-fuente',
                itemId: 'fuente',
                kind: RenditionKind.plainText,
                content: const Value('1859 publica.'),
                isPrimary: true,
                createdAt: now,
              ),
            );
        await seedItem('p');
        await fact('citado', 'p', renditionId: 'texto-fuente');
        await fact('sin-cita', 'p');

        final events = {for (final e in await read()) e.datedEventId: e};

        expect(events['citado']!.quoteItemId, 'fuente');
        expect(events['citado']!.hasAnchor, isTrue);
        expect(events['sin-cita']!.quoteItemId, isNull);
      });
    });

    test('diez mil hechos se leen sin trabarse', () async {
      const items = 200;
      for (var i = 0; i < items; i++) {
        await insertProcessedDocument(db, id: 'i$i', title: 'Documento $i');
      }
      await db.batch((batch) {
        batch.insertAll(db.datedEvents, [
          for (var i = 0; i < 10000; i++)
            DatedEventsCompanion.insert(
              id: 'e$i',
              itemId: 'i${i % items}',
              title: 'Hecho $i',
              dateFromYear: 1 + (i * 7919) % 2000,
              dateFromMonth: 1,
              dateFromDay: 1,
              datePrecision: DatePrecision.year,
              createdAt: now,
              updatedAt: now,
            ),
        ]);
      });

      final watch = Stopwatch()..start();
      final events = await read();
      watch.stop();

      expect(events, hasLength(10000));
      expect(events.first.from, lessThanOrEqualTo(events.last.from));
      // Una cota holgada: es para que una consulta por hecho —en vez de una
      // sola— no pase inadvertida, no una medida.
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });
}
