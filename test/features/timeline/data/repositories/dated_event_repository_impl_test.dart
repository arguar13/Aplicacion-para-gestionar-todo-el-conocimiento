import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/timeline/data/repositories/dated_event_repository_impl.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';

import '../../../../support/item_rows.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

class _CountingIds implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'h${_n++}';
}

/// Los hechos fechados dentro de un documento (F40), contra SQLite real.
void main() {
  late AppDatabase db;
  late DatedEventRepositoryImpl repository;
  var now = DateTime(2026, 10, 26, 10);

  const text =
      'Darwin nació en 1809. En 1831 zarpó en el Beagle. '
      'En 1859 publicó El origen de las especies.';

  const darwin = DatePrecision.year;
  HistoricalDate year(int y, {bool bce = false, bool circa = false}) =>
      HistoricalDate(year: y, precision: darwin, isBce: bce, isCirca: circa);

  /// Un borrador con la cita [quote] ubicada en [text]; [copied] es cómo
  /// quedó copiado el fragmento si no es igual.
  DatedEventInput draft(
    String title,
    HistoricalDate date,
    String quote, {
    HistoricalDate? end,
    String rendition = 'texto',
    String? copied,
  }) {
    final start = text.indexOf(quote);
    return DatedEventInput(
      title: title,
      date: date,
      end: end,
      renditionId: rendition,
      startOffset: start,
      endOffset: start + quote.length,
      excerpt: copied ?? quote,
    );
  }

  Future<String> startRun([String itemId = 'libro']) async {
    final id = 'pasada-${(await db.select(db.aiRuns).get()).length}';
    await db
        .into(db.aiRuns)
        .insert(AiRunsCompanion.insert(id: id, itemId: itemId, startedAt: now));
    return id;
  }

  Future<List<DatedEvent>> eventsOf(String itemId) =>
      repository.watchForItem(itemId).first;

  setUp(() async {
    now = DateTime(2026, 10, 26, 10);
    db = AppDatabase(NativeDatabase.memory());
    repository = DatedEventRepositoryImpl(
      database: db,
      telemetry: _SilentTelemetry(),
      ids: _CountingIds(),
      clock: () => now,
    );
    await insertItemRows(
      db,
      id: 'libro',
      title: 'Darwin',
      kind: SourceKind.document,
    );
    await insertItemRows(
      db,
      id: 'otro',
      title: 'Otro',
      kind: SourceKind.document,
    );
    for (final (id, item) in [('texto', 'libro'), ('ajeno', 'otro')]) {
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: id,
              itemId: item,
              kind: RenditionKind.plainText,
              content: const Value(text),
              isPrimary: true,
              createdAt: now,
            ),
          );
    }
  });

  tearDown(() => db.close());

  group('a mano', () {
    test('un hecho con su cita es de la persona y queda guardado', () async {
      final saved = await repository.add(
        'libro',
        draft('Publica El origen', year(1859), 'En 1859 publicó'),
      );

      final event = saved.getOrElse((f) => fail('$f'));
      expect(event.origin, ContentOrigin.user);
      expect(event.aiRunId, isNull);
      expect(event.date, year(1859));
      expect(event.end, isNull);
      expect(event.excerpt, 'En 1859 publicó');
      expect(event.hasAnchor, isTrue);
      expect(event.createdAt, now);
      expect(await eventsOf('libro'), [event]);
    });

    test('puede no tener cita ni texto', () async {
      final saved = await repository.add(
        'libro',
        DatedEventInput(title: '  Nace Darwin ', date: year(1809)),
      );

      final event = saved.getOrElse((f) => fail('$f'));
      expect(event.title, 'Nace Darwin');
      expect(event.hasAnchor, isFalse);
      expect(event.renditionId, isNull);
    });

    test(
      'guarda la fecha como el primer día que cubre, y la devuelve igual',
      () async {
        const march = HistoricalDate(
          year: 1914,
          precision: DatePrecision.month,
          month: 3,
          isCirca: true,
        );
        final saved = await repository.add(
          'libro',
          const DatedEventInput(title: 'Marzo', date: march),
        );

        expect(saved.getOrElse((f) => fail('$f')).date, march);
        final row = await db.select(db.datedEvents).getSingle();
        expect(
          (row.dateFromYear, row.dateFromMonth, row.dateFromDay),
          (1914, 3, 1),
        );
        expect(row.dateIsCirca, isTrue);
        // Una década guarda el año de inicio, con 1/1, como «Fecha del hecho».
        final decade = await repository.add(
          'libro',
          const DatedEventInput(
            title: 'Los veinte',
            date: HistoricalDate(year: 1920, precision: DatePrecision.decade),
          ),
        );
        expect(
          decade.getOrElse((f) => fail('$f')).date,
          const HistoricalDate(year: 1920, precision: DatePrecision.decade),
        );
      },
    );

    test('a.C. cruza el cero: se guarda el año astronómico', () async {
      await repository.add(
        'libro',
        DatedEventInput(title: 'Muere César', date: year(44, bce: true)),
      );

      expect((await db.select(db.datedEvents).getSingle()).dateFromYear, -43);
      expect((await eventsOf('libro')).single.date, year(44, bce: true));
    });

    test('un tramo guarda su fin', () async {
      final saved = await repository.add(
        'libro',
        DatedEventInput(
          title: 'La Gran Guerra',
          date: year(1914),
          end: year(1918),
        ),
      );

      final event = saved.getOrElse((f) => fail('$f'));
      expect(event.end, year(1918));
      expect(event.isRange, isTrue);
      final row = await db.select(db.datedEvents).getSingle();
      expect(row.dateEndYear, 1918);
      expect(row.dateEndPrecision, DatePrecision.year);
    });

    test('el fin conserva su propia precisión, mes y día', () async {
      const start = HistoricalDate(
        year: 1914,
        precision: DatePrecision.month,
        month: 7,
      );
      const end = HistoricalDate(
        year: 1918,
        precision: DatePrecision.day,
        month: 11,
        day: 11,
      );
      await repository.add(
        'libro',
        const DatedEventInput(title: 'La Gran Guerra', date: start, end: end),
      );

      final event = (await eventsOf('libro')).single;

      expect(event.date, start);
      expect(event.end, end);
      final row = await db.select(db.datedEvents).getSingle();
      expect(
        (
          row.dateEndYear,
          row.dateEndMonth,
          row.dateEndDay,
          row.dateEndPrecision,
        ),
        (1918, 11, 11, DatePrecision.day),
      );
    });

    test('un tramo que termina el mismo año que empieza está bien', () async {
      const august = HistoricalDate(
        year: 1914,
        precision: DatePrecision.month,
        month: 8,
      );
      final saved = await repository.add(
        'libro',
        DatedEventInput(title: 'Estalla', date: august, end: year(1914)),
      );
      expect(saved.isRight(), isTrue);
    });

    test('el orden por fecha cruza a.C. y d.C.', () async {
      for (final (title, date) in [
        ('c', year(1859)),
        ('a', year(44, bce: true)),
        ('b', year(476)),
      ]) {
        await repository.add(
          'libro',
          DatedEventInput(title: title, date: date),
        );
      }

      expect(
        [for (final e in await eventsOf('libro')) e.title],
        ['a', 'b', 'c'],
      );
    });
  });

  group('las invariantes', () {
    Future<void> expectRejected(DatedEventInput input, String why) async {
      final result = await repository.add('libro', input);
      expect(result.isLeft(), isTrue, reason: why);
      expect(await db.select(db.datedEvents).get(), isEmpty, reason: why);
    }

    test('sin título no hay hecho', () async {
      await expectRejected(
        DatedEventInput(title: '   ', date: year(1809)),
        'título vacío',
      );
    });

    test('el fin no puede ser anterior al inicio', () async {
      await expectRejected(
        DatedEventInput(title: 'x', date: year(1918), end: year(1914)),
        'fin antes del inicio',
      );
      await expectRejected(
        DatedEventInput(
          title: 'x',
          date: year(44, bce: true),
          end: year(50, bce: true),
        ),
        'fin a.C. antes del inicio',
      );
    });

    test('una fecha que no existe se rechaza', () async {
      await expectRejected(
        const DatedEventInput(
          title: 'x',
          date: HistoricalDate(
            year: 1900,
            precision: DatePrecision.day,
            month: 2,
            day: 29,
          ),
        ),
        '29 de febrero de un año no bisiesto',
      );
      await expectRejected(
        const DatedEventInput(
          title: 'x',
          date: HistoricalDate(year: 1900, precision: DatePrecision.month),
        ),
        'mes sin mes',
      );
    });

    test(
      'la posición de la cita viene entera y es de un texto del elemento',
      () async {
        await expectRejected(
          DatedEventInput(title: 'x', date: year(1809), startOffset: 3),
          'un extremo solo',
        );
        await expectRejected(
          DatedEventInput(
            title: 'x',
            date: year(1809),
            startOffset: 3,
            endOffset: 9,
            excerpt: 'Darwin',
          ),
          'posición sin texto',
        );
        await expectRejected(
          DatedEventInput(
            title: 'x',
            date: year(1809),
            renditionId: 'texto',
            startOffset: 9,
            endOffset: 9,
            excerpt: 'Darwin',
          ),
          'tramo vacío',
        );
        await expectRejected(
          DatedEventInput(
            title: 'x',
            date: year(1809),
            renditionId: 'texto',
            startOffset: 0,
            endOffset: 6,
          ),
          'posición sin fragmento',
        );
        await expectRejected(
          draft('x', year(1809), 'Darwin nació', rendition: 'ajeno'),
          'texto de otro elemento',
        );
      },
    );
  });

  group('de la IA', () {
    test('agrega los hechos de la pasada, con su cita y su pasada', () async {
      final run = await startRun();

      final added = await repository.addFromAi(
        itemId: 'libro',
        runId: run,
        drafts: [
          draft('Nace Darwin', year(1809), 'Darwin nació en 1809'),
          draft('Zarpa en el Beagle', year(1831), 'En 1831 zarpó'),
          draft('Publica El origen', year(1859), 'En 1859 publicó'),
        ],
      );

      expect(added, right<Failure, int>(3));
      final events = await eventsOf('libro');
      expect(events.map((e) => e.date.year), [1809, 1831, 1859]);
      expect(events.every((e) => e.isAi && e.aiRunId == run), isTrue);
      expect(events.every((e) => e.hasAnchor), isTrue);
    });

    test('no repite lo que ya está, venga de quien venga', () async {
      final run = await startRun();
      await repository.add(
        'libro',
        draft('Lo puse yo', year(1809), 'Darwin nació en 1809'),
      );

      final added = await repository.addFromAi(
        itemId: 'libro',
        runId: run,
        drafts: [
          // Lo mismo que puso la persona, con la cita copiada distinto.
          draft(
            'Nace Darwin',
            year(1809),
            'Darwin nació en 1809',
            copied: 'darwin  NACIÓ en 1809',
          ),
          draft('Zarpa', year(1831), 'En 1831 zarpó'),
        ],
      );
      expect(added, right<Failure, int>(1));

      // Otra pasada con lo mismo: nada nuevo.
      final again = await repository.addFromAi(
        itemId: 'libro',
        runId: await startRun(),
        drafts: [
          draft(
            'Zarpa otra vez',
            year(1831),
            'En 1831 zarpó',
            copied: 'EN 1831 ZARPÓ',
          ),
        ],
      );
      expect(again, right<Failure, int>(0));
      expect(await eventsOf('libro'), hasLength(2));
    });

    test('la misma fecha con otra cita es otro hecho', () async {
      final run = await startRun();

      final added = await repository.addFromAi(
        itemId: 'libro',
        runId: run,
        drafts: [
          draft('Zarpa', year(1831), 'En 1831 zarpó'),
          draft('Otro de 1831', year(1831), 'el Beagle'),
        ],
      );

      expect(added, right<Failure, int>(2));
    });

    test('repetido dentro de la misma tanda: entra una vez', () async {
      final run = await startRun();

      final added = await repository.addFromAi(
        itemId: 'libro',
        runId: run,
        drafts: [
          draft('Zarpa', year(1831), 'En 1831 zarpó'),
          draft('Zarpa (otra vez)', year(1831), 'En 1831 zarpó'),
        ],
      );

      expect(added, right<Failure, int>(1));
    });

    test('lo que la persona quitó no vuelve', () async {
      final run = await startRun();
      await repository.addFromAi(
        itemId: 'libro',
        runId: run,
        drafts: [draft('Zarpa', year(1831), 'En 1831 zarpó')],
      );
      final event = (await eventsOf('libro')).single;
      await repository.remove(event.id);
      expect(await eventsOf('libro'), isEmpty);

      final added = await repository.addFromAi(
        itemId: 'libro',
        runId: await startRun(),
        drafts: [
          // Con otro título y otro fin, pero la misma fecha y la misma cita.
          draft('Sale en barco', year(1831), 'En 1831 zarpó', end: year(1836)),
        ],
      );

      expect(added, right<Failure, int>(0));
      expect(await eventsOf('libro'), isEmpty);
    });

    test(
      'deja pasar un hecho de otra fecha con la misma cita quitada',
      () async {
        final run = await startRun();
        await repository.addFromAi(
          itemId: 'libro',
          runId: run,
          drafts: [draft('Zarpa', year(1831), 'En 1831 zarpó')],
        );
        await repository.remove((await eventsOf('libro')).single.id);

        final added = await repository.addFromAi(
          itemId: 'libro',
          runId: await startRun(),
          drafts: [draft('Zarpa', year(1832), 'En 1831 zarpó')],
        );

        expect(added, right<Failure, int>(1));
      },
    );

    test('descarta lo inválido y sigue con lo demás', () async {
      final run = await startRun();

      final added = await repository.addFromAi(
        itemId: 'libro',
        runId: run,
        drafts: [
          // Sin cita: la IA siempre cita.
          DatedEventInput(title: 'Sin cita', date: year(1900)),
          DatedEventInput(
            title: 'Cita en blanco',
            date: year(1900),
            excerpt: ' ',
          ),
          // El fin antes del inicio.
          draft('Al revés', year(1918), 'En 1859 publicó', end: year(1914)),
          // Con un texto de otro elemento.
          draft('Ajeno', year(1809), 'Darwin nació', rendition: 'ajeno'),
          draft('Bueno', year(1859), 'En 1859 publicó'),
        ],
      );

      expect(added, right<Failure, int>(1));
      expect((await eventsOf('libro')).single.title, 'Bueno');
    });

    test(
      'una pasada de otro elemento o inexistente se rechaza entera',
      () async {
        final foreign = await startRun('otro');

        for (final run in [foreign, 'no-existe']) {
          final result = await repository.addFromAi(
            itemId: 'libro',
            runId: run,
            drafts: [draft('Zarpa', year(1831), 'En 1831 zarpó')],
          );
          expect(result.isLeft(), isTrue, reason: run);
        }
        expect(await db.select(db.datedEvents).get(), isEmpty);
      },
    );
  });

  group('editar y quitar', () {
    late String run;
    late DatedEvent aiEvent;

    setUp(() async {
      run = await startRun();
      await repository.addFromAi(
        itemId: 'libro',
        runId: run,
        drafts: [draft('Zarpa', year(1831), 'En 1831 zarpó')],
      );
      aiEvent = (await eventsOf('libro')).single;
    });

    test('editar uno de la IA lo vuelve de la persona', () async {
      now = DateTime(2026, 10, 27, 9);

      final updated = await repository.update(
        aiEvent.id,
        title: 'Sale hacia las Galápagos',
        date: year(1831),
        end: year(1836),
      );

      final event = updated.getOrElse((f) => fail('$f'));
      expect(event.origin, ContentOrigin.user);
      expect(event.aiRunId, isNull);
      expect(event.title, 'Sale hacia las Galápagos');
      expect(event.end, year(1836));
      expect(event.updatedAt, now);
      expect(event.createdAt, aiEvent.createdAt);
      // Lo que no se edita se queda: la cita sigue ahí.
      expect(event.excerpt, 'En 1831 zarpó');
      expect(event.hasAnchor, isTrue);
    });

    test('se puede sacar el fin', () async {
      await repository.update(
        aiEvent.id,
        title: 'x',
        date: year(1831),
        end: year(1836),
      );

      final updated = await repository.update(
        aiEvent.id,
        title: 'x',
        date: year(1831),
      );

      expect(updated.getOrElse((f) => fail('$f')).end, isNull);
      expect((await db.select(db.datedEvents).getSingle()).dateEndYear, isNull);
    });

    test('editar con datos inválidos no cambia nada', () async {
      final result = await repository.update(
        aiEvent.id,
        title: 'x',
        date: year(1918),
        end: year(1914),
      );

      expect(result.isLeft(), isTrue);
      expect(await eventsOf('libro'), [aiEvent]);
    });

    test('editar uno que ya no está es un error', () async {
      final result = await repository.update(
        'nada',
        title: 'x',
        date: year(1831),
      );
      expect(result.isLeft(), isTrue);
    });

    test('quitar uno de la IA lo anota como «no era»', () async {
      final removal = (await repository.remove(
        aiEvent.id,
      )).getOrElse((f) => fail('$f'));

      expect(removal.event, aiEvent);
      expect(removal.rejectionId, isNotNull);
      expect(await eventsOf('libro'), isEmpty);
      final memory = await db.select(db.aiRejections).getSingle();
      expect(memory.kind, AiRejectionKind.datedEvent);
      expect(memory.itemId, 'libro');
      expect(memory.subjectId, aiEvent.id);
      expect(
        memory.fingerprint,
        datedEventRejectionFingerprint(
          date: year(1831),
          excerpt: 'En 1831 zarpó',
        ),
      );
    });

    test('quitar uno de la persona no deja memoria', () async {
      final mine = (await repository.add(
        'libro',
        DatedEventInput(title: 'Mío', date: year(1809)),
      )).getOrElse((f) => fail('$f'));

      final removal = (await repository.remove(
        mine.id,
      )).getOrElse((f) => fail('$f'));

      expect(removal.rejectionId, isNull);
      expect(await db.select(db.aiRejections).get(), isEmpty);
      expect((await eventsOf('libro')).map((e) => e.id), [aiEvent.id]);
    });

    test(
      'uno de la IA que se editó y se quitó ya no cuenta como «no era»',
      () async {
        await repository.update(aiEvent.id, title: 'Mío', date: year(1831));

        await repository.remove(aiEvent.id);

        expect(await db.select(db.aiRejections).get(), isEmpty);
      },
    );

    test('quitar uno que ya no está es un error', () async {
      expect((await repository.remove('nada')).isLeft(), isTrue);
    });

    test('deshacer devuelve el hecho tal cual y olvida el «no era»', () async {
      final removal = (await repository.remove(
        aiEvent.id,
      )).getOrElse((f) => fail('$f'));

      final undone = await repository.undoRemove(removal);

      expect(undone.isRight(), isTrue);
      expect(await eventsOf('libro'), [aiEvent]);
      expect(await db.select(db.aiRejections).get(), isEmpty);
    });

    test(
      'deshacer cuando la pasada o el texto se fueron lo devuelve sin ellos',
      () async {
        final removal = (await repository.remove(
          aiEvent.id,
        )).getOrElse((f) => fail('$f'));
        await db.customStatement('DELETE FROM ai_runs');
        await (db.delete(
          db.renditions,
        )..where((r) => r.id.equals('texto'))).go();

        await repository.undoRemove(removal);

        final event = (await eventsOf('libro')).single;
        expect(event.id, aiEvent.id);
        expect(event.aiRunId, isNull);
        expect(event.renditionId, isNull);
        expect(event.startOffset, isNull);
        expect(event.excerpt, 'En 1831 zarpó');
      },
    );
  });

  group('con su elemento y su texto', () {
    test(
      'van a la papelera del elemento sin borrarse, y se van con él',
      () async {
        await repository.add(
          'libro',
          DatedEventInput(title: 'x', date: year(1809)),
        );

        await trashItemRows(db, 'libro');
        expect(await eventsOf('libro'), hasLength(1));

        await deleteItemRows(db, 'libro');
        expect(await db.select(db.datedEvents).get(), isEmpty);
      },
    );

    test(
      'soltar el texto se lleva los hechos que lo citan, no los sueltos',
      () async {
        await repository.add(
          'libro',
          draft('Citado', year(1859), 'En 1859 publicó'),
        );
        await repository.add(
          'libro',
          DatedEventInput(title: 'Suelto', date: year(1809)),
        );

        await (db.delete(
          db.renditions,
        )..where((r) => r.id.equals('texto'))).go();

        expect([for (final e in await eventsOf('libro')) e.title], ['Suelto']);
      },
    );
  });

  test('el stream emite de nuevo cuando cambia', () async {
    final emissions = <List<String>>[];
    final sub = repository
        .watchForItem('libro')
        .listen((events) => emissions.add([for (final e in events) e.title]));
    addTearDown(sub.cancel);
    await pumpEventQueue();

    await repository.add(
      'libro',
      DatedEventInput(title: 'Uno', date: year(1809)),
    );
    await pumpEventQueue();
    await repository.add(
      'libro',
      DatedEventInput(title: 'Dos', date: year(1831)),
    );
    await pumpEventQueue();

    expect(emissions.first, isEmpty);
    expect(emissions.last, ['Uno', 'Dos']);
  });
}
