import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show right;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_run_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/timeline/data/repositories/dated_event_repository_impl.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// Los hechos fechados que pone la IA (F40) cuentan en «Lo que hizo la IA» y
/// se deshacen con su pasada, sin llevarse lo que la persona adoptó ni lo que
/// puso ella.
void main() {
  late AppDatabase db;
  late AiRunRepositoryImpl runs;
  late DatedEventRepositoryImpl facts;
  final now = DateTime(2026, 10, 26, 10);

  HistoricalDate year(int y) =>
      HistoricalDate(year: y, precision: DatePrecision.year);

  DatedEventInput draft(String title, int y) =>
      DatedEventInput(title: title, date: year(y), excerpt: 'cita $title');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ids = FakeIdGenerator();
    final telemetry = _MockTelemetryService();
    runs = AiRunRepositoryImpl(
      database: db,
      telemetry: telemetry,
      ids: ids,
      clock: () => now,
    );
    facts = DatedEventRepositoryImpl(
      database: db,
      telemetry: telemetry,
      ids: ids,
      clock: () => now,
    );
    await insertItemRows(db, id: 'libro', title: 'Darwin');
    await insertItemRows(db, id: 'otro', title: 'Otro');
  });

  tearDown(() => db.close());

  Future<String> startRun([String item = 'libro']) async =>
      (await runs.startRun(item, model: 'gemma')).getOrElse((f) => fail('$f'));

  /// Una pasada que pone tres hechos.
  Future<String> datesRun() async {
    final run = await startRun();
    await facts.addFromAi(
      itemId: 'libro',
      runId: run,
      drafts: [
        draft('Nace', 1809),
        draft('Zarpa', 1831),
        draft('Publica', 1859),
      ],
    );
    return run;
  }

  Future<List<String>> titles() async =>
      [for (final e in await db.select(db.datedEvents).get()) e.title]..sort();

  test('terminar la pasada cuenta las fechas que puso', () async {
    final run = await datesRun();

    final tally = await runs.finishRun(run);

    expect(tally, right<Failure, AiRunTally>(const AiRunTally(dates: 3)));
    expect((await db.select(db.aiRuns).getSingle()).datesCreated, 3);
  });

  test('la lista dice cuántas puso y cuántas siguen siendo de la IA', () async {
    final run = await datesRun();
    await runs.finishRun(run);
    // La persona edita una y quita otra.
    final events = await db.select(db.datedEvents).get();
    final byTitle = {for (final e in events) e.title: e.id};
    await facts.update(byTitle['Nace']!, title: 'Nace', date: year(1809));
    await facts.remove(byTitle['Zarpa']!);

    final listed = (await runs.listRuns()).getOrElse((f) => fail('$f')).single;

    expect(listed.created.dates, 3);
    expect(listed.remaining.dates, 1);
    expect(listed.created.total, 3);
    expect(listed.remaining.reviewable, 0);
  });

  group('deshacer la pasada', () {
    test('saca los hechos que siguen siendo de la IA, y los cuenta', () async {
      final run = await datesRun();
      await runs.finishRun(run);

      final tally = await runs.undoRun(run);

      expect(tally, right<Failure, AiRunTally>(const AiRunTally(dates: 3)));
      expect(await titles(), isEmpty);
      expect((await db.select(db.aiRuns).getSingle()).undoneAt, now);
    });

    test('no se lleva lo que la persona adoptó, puso ni lo de otra '
        'pasada', () async {
      final run = await datesRun();
      await runs.finishRun(run);
      final events = await db.select(db.datedEvents).get();
      final adopted = events.firstWhere((e) => e.title == 'Nace');
      await facts.update(adopted.id, title: 'Nace', date: year(1809));
      await facts.add('libro', DatedEventInput(title: 'Mío', date: year(1900)));
      final later = await startRun();
      await facts.addFromAi(
        itemId: 'libro',
        runId: later,
        drafts: [draft('Muere', 1882)],
      );

      final tally = await runs.undoRun(run);

      expect(tally, right<Failure, AiRunTally>(const AiRunTally(dates: 2)));
      expect(await titles(), unorderedEquals(['Mío', 'Muere', 'Nace']));
      final kept = await (db.select(
        db.datedEvents,
      )..where((e) => e.title.equals('Nace'))).getSingle();
      expect((kept.origin, kept.aiRunId), (ContentOrigin.user, null));
    });

    test('deshacer todo lo de un elemento incluye sus fechas', () async {
      await datesRun();
      await facts.addFromAi(
        itemId: 'libro',
        runId: await startRun(),
        drafts: [draft('Muere', 1882)],
      );
      // Y las de otro elemento no se tocan.
      final other = await startRun('otro');
      await facts.addFromAi(
        itemId: 'otro',
        runId: other,
        drafts: [draft('Cae', 1789)],
      );

      final tally = await runs.undoItem('libro');

      expect(tally, right<Failure, AiRunTally>(const AiRunTally(dates: 4)));
      expect(await titles(), ['Cae']);
    });
  });

  test('un hecho de la IA que se quitó no se cuenta ni vuelve con otra '
      'pasada', () async {
    final run = await datesRun();
    await runs.finishRun(run);
    final zarpa = await (db.select(
      db.datedEvents,
    )..where((e) => e.title.equals('Zarpa'))).getSingle();
    await facts.remove(zarpa.id);

    final again = await startRun();
    final added = await facts.addFromAi(
      itemId: 'libro',
      runId: again,
      drafts: [draft('Zarpa', 1831), draft('Publica', 1859)],
    );

    // «Zarpa» ya no vuelve y «Publica» ya estaba.
    expect(added, right<Failure, int>(0));
  });
}
