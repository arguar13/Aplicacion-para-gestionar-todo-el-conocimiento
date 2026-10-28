import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_organize/data/services/organize_text_reader_impl.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_dates_step.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/timeline/data/repositories/dated_event_repository_impl.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_draft.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_events_extractor.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_passage_selector.dart';
import 'package:sinapsis/features/timeline/domain/services/temporal_expressions.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/processed_rows.dart';

/// El modelo de fechas de mentira: por cada fecha de los pasajes que lee, un
/// hecho citado tal cual está en el texto. Anota cada pedido
/// que recibe, y puede leer menos pasajes de los que le llegan —una ventana
/// chica— o fallar en un pedido.
class _FakeDatesModel implements DatedEventsExtractor {
  _FakeDatesModel(this.text);

  /// El texto del que son las posiciones.
  String text;

  int budget = 600;

  @override
  int get datedPartCharBudget => budget;

  /// Cada pedido que recibió, en orden.
  final requests = <DatedTextPart>[];

  /// Cuántos pasajes lee, como mucho, de cada pedido; `null`, todos.
  int? readsAtMost;

  /// Si lee los pasajes pero no encuentra ningún hecho.
  bool silent = false;

  /// El pedido (desde 1) que lanza esto, una sola vez.
  int? failAt;

  /// Lo que lanza ese pedido: sin cuota, salvo que la prueba diga otra cosa.
  Never Function() failure = _outOfQuota;

  static Never _outOfQuota() =>
      throw const CloudModelException(CloudModelFailure.quotaExhausted);

  @override
  Future<DatedEventsOutcome> datedEventsOf(DatedTextPart part) async {
    requests.add(part);
    if (requests.length == failAt) {
      failAt = null;
      failure();
    }
    final read = math.min(
      readsAtMost ?? part.passages.length,
      part.passages.length,
    );
    return DatedEventsOutcome(
      analyzed: read,
      events: [
        for (final passage in part.passages.take(read))
          for (final e
              in silent ? const <TemporalExpression>[] : passage.expressions)
            DatedEventDraft(
              date: e.date,
              endDate: e.endDate,
              title: 'Hecho de ${text.substring(e.start, e.end)}',
              start: e.start,
              end: e.end,
              excerpt: text.substring(e.start, e.end),
            ),
      ],
    );
  }
}

/// El mismo modelo, que anota cada vez que le preguntan cuánto lee por pedido:
/// una por cada vez que se lee el texto de un elemento.
class _CountingBudget implements DatedEventsExtractor {
  _CountingBudget(this._model, this._onBudget);

  final _FakeDatesModel _model;
  final void Function() _onBudget;

  @override
  int get datedPartCharBudget {
    _onBudget();
    return _model.datedPartCharBudget;
  }

  @override
  Future<DatedEventsOutcome> datedEventsOf(DatedTextPart part) =>
      _model.datedEventsOf(part);
}

/// Un texto con [years] sucesos, cada uno en su oración y con su año, separados
/// por oraciones sin fecha: cada suceso es un pasaje aparte.
String _chronicle(int years, {int from = 1500}) => [
  for (var i = 0; i < years; i++) ...[
    'En el año ${from + i} ocurrió un suceso en la región del norte.',
    'El camino era largo y difícil para todos.',
    'Pocos viajeros se animaban a recorrerlo.',
    'Las noches eran frías en la montaña.',
  ],
].join(' ');

void main() {
  late AiOrganizeHarness vault;
  late DatedEventRepositoryImpl events;
  late _FakeDatesModel model;
  late AutoDatesStep step;

  setUp(() {
    vault = AiOrganizeHarness();
    events = DatedEventRepositoryImpl(
      database: vault.db,
      telemetry: vault.telemetry,
      ids: vault.ids,
      clock: vault.clock,
    );
    model = _FakeDatesModel('');
    step = AutoDatesStep(extractor: model, events: events);
  });

  tearDown(() => vault.close());

  Future<List<DatedEventRow>> stored() => (vault.db.select(
    vault.db.datedEvents,
  )..orderBy([(e) => OrderingTerm.asc(e.dateFromYear)])).get();

  Future<KnowledgeItem> chronicle(
    String id, {
    int years = 12,
    String? text,
  }) async {
    final content = text ?? _chronicle(years);
    model.text = content;
    return vault.source(id, title: 'Crónica $id', content: content);
  }

  test(
    'es el paso de las fechas: su interruptor y su paso de «Cómo lo hace»',
    () {
      expect(step.toggle, AiOrganizeToggle.dates);
      expect(step.toggle.taskStep, AiTaskStepKind.organizeDates);
    },
  );

  group('de un documento procesado (F41, paso 6)', () {
    test('lee lo elegido, y la cita de una parte copiada tal cual va a la '
        'fuente, en su lugar; la de una nota, sin lugar', () async {
      const source = 'Darwin nació en 1809. Murió en 1882.';
      await vault.source('fuente', title: 'Darwin', content: source);
      await insertProcessedDocument(
        vault.db,
        id: 'p',
        title: 'Darwin',
        sections: const {},
      );
      await (vault.db.update(
        vault.db.processedDocuments,
      )..where((d) => d.itemId.equals('p'))).write(
        const ProcessedDocumentsCompanion(sourceItemId: Value('fuente')),
      );
      Future<void> part(
        String id,
        ProcessedSection section,
        String content, {
        int? at,
      }) => vault.db
          .into(vault.db.processedParts)
          .insert(
            ProcessedPartsCompanion.insert(
              id: id,
              documentId: 'p',
              section: section,
              position: 0,
              content: content,
              origin: at == null
                  ? ProcessedPartOrigin.user
                  : ProcessedPartOrigin.copied,
              sourceRenditionId: Value(at == null ? null : 'rend-fuente'),
              sourceStart: Value(at),
              sourceEnd: Value(at == null ? null : at + content.length),
              createdAt: vault.now,
              updatedAt: vault.now,
            ),
          );
      await part('t', ProcessedSection.text, 'Murió en 1882.', at: 22);
      await part('n', ProcessedSection.notes, 'Lo leí en 1990.');
      final item = await vault.reload('p');
      final texts = OrganizeTextReaderImpl(vault.db);
      model.text = (await texts.textOf(item)).text;
      step = AutoDatesStep(extractor: model, events: events, texts: texts);

      await step.organize(item, runId: await vault.startRun('p'));

      final facts = await stored();
      expect(facts.map((f) => f.itemId).toSet(), {'p'});
      final death = facts.firstWhere((f) => f.dateFromYear == 1882);
      expect(death.renditionId, 'rend-fuente');
      expect(source.substring(death.startOffset!, death.endOffset), '1882');
      final note = facts.firstWhere((f) => f.dateFromYear == 1990);
      expect(note.renditionId, isNull);
      expect(note.startOffset, isNull);
    });
  });

  group('lo que lee del texto', () {
    test('un texto sin fechas no le manda nada al modelo', () async {
      final item = await chronicle(
        'a',
        text: 'Una receta de pan con harina, agua y sal. Se amasa y se hornea.',
      );

      expect(await step.mentionsDates(item), isFalse);
      final report = await step.organize(
        item,
        runId: await vault.startRun('a'),
      );

      expect(report, AiStepReport.nothing);
      expect(model.requests, isEmpty);
      expect(await stored(), isEmpty);
    });

    test('un elemento sin texto tampoco', () async {
      final item = await chronicle('a', text: '   ');

      expect(await step.mentionsDates(item), isFalse);
      await step.organize(item, runId: await vault.startRun('a'));

      expect(model.requests, isEmpty);
    });

    test('con fechas, las oraciones fechadas se reparten en pedidos del tamaño '
        'que lee el modelo elegido', () async {
      final item = await chronicle('a', years: 30);
      model.budget = 500;
      final expected = selectDatedParts(
        item.renditions.whereType<TextRendition>().single.content,
        maxChars: 500,
      );

      expect(await step.mentionsDates(item), isTrue);
      await step.organize(item, runId: await vault.startRun('a'));

      expect(expected.length, greaterThan(2));
      expect(model.requests, expected);
      for (final part in model.requests) {
        expect(part.chars, lessThanOrEqualTo(500));
      }
    });

    test('un libro largo se lee en otro hilo y da los mismos pedidos que uno '
        'corto: mismo texto, mismas partes', () async {
      final item = await chronicle('a', years: 400);
      final text = item.renditions.whereType<TextRendition>().single.content;
      model.budget = 3000;

      // Más de lo que se lee sin salir del hilo de la interfaz.
      expect(text.length, greaterThan(40000));
      expect(await step.mentionsDates(item), isTrue);
      await step.organize(item, runId: await vault.startRun('a'));

      expect(model.requests, selectDatedParts(text, maxChars: 3000));
      expect(await stored(), hasLength(400));
    });

    test(
      'preguntar si hay fechas y pedirlas lee el texto una sola vez',
      () async {
        final item = await chronicle('a', years: 20);
        model.budget = 500;
        var asked = 0;
        final counting = _CountingBudget(model, () => asked++);
        step = AutoDatesStep(extractor: counting, events: events);

        await step.mentionsDates(item);
        await step.organize(item, runId: await vault.startRun('a'));

        expect(asked, 1);
      },
    );

    test('lee el mismo texto que abre la lectura —la forma principal—, no la '
        'suma de todas las que tiene el elemento', () async {
      const main = 'Nació en 1809 en Shrewsbury.';
      const other = 'Un resumen que habla de 1900.';
      model.text = main;
      final at = vault.now;
      final item = KnowledgeItem(
        id: 'a',
        title: 'Darwin',
        source: Source(
          id: 'src-a',
          kind: SourceKind.webPage,
          capturedAt: at,
          url: 'https://e.org/a',
        ),
        processingState: ProcessingState.ready,
        createdAt: at,
        updatedAt: at,
        renditions: [
          Rendition.text(
            id: 'rend-main',
            itemId: 'a',
            kind: RenditionKind.plainText,
            content: main,
            isPrimary: true,
            createdAt: at,
          ),
          Rendition.text(
            id: 'rend-other',
            itemId: 'a',
            kind: RenditionKind.plainText,
            content: other,
            isPrimary: false,
            createdAt: at,
          ),
        ],
      );
      await vault.library.save(item);

      await step.organize(item, runId: await vault.startRun('a'));

      final row = (await stored()).single;
      expect(row.excerpt, '1809');
      expect(row.renditionId, 'rend-main');
    });

    test('el texto de una página o una nota se parte como Markdown; el de '
        'un documento o una transcripción, no', () async {
      const text = '# Darwin\nNació en 1809 en Shrewsbury.';
      final page = await vault.source('p', title: 'P', content: text);
      final audio = await vault.source(
        'q',
        title: 'Q',
        content: text,
        kind: SourceKind.audio,
      );
      model.text = text;

      await step.organize(page, runId: await vault.startRun('p'));
      final asPage = [...model.requests];
      model.requests.clear();
      await step.organize(audio, runId: await vault.startRun('q'));

      expect(asPage, selectDatedParts(text, maxChars: 600, markdown: true));
      expect(model.requests, selectDatedParts(text, maxChars: 600));
      // Es una diferencia de verdad: el título queda afuera del Markdown.
      expect(asPage, isNot(model.requests));
    });

    test('el tamaño se pregunta al modelo en cada elemento: cambiar de modelo '
        'vale desde el próximo', () async {
      final first = await chronicle('a', years: 30);
      model.budget = 3000;
      await step.organize(first, runId: await vault.startRun('a'));
      final big = model.requests.length;

      model.requests.clear();
      model.budget = 400;
      final second = await vault.source(
        'b',
        title: 'B',
        content: _chronicle(30),
      );
      await step.organize(second, runId: await vault.startRun('b'));

      expect(model.requests.length, greaterThan(big));
    });
  });

  group('lo que guarda', () {
    test('cada hecho con su fecha, su cita y la forma del texto, marcado como '
        'de la IA y de esa pasada', () async {
      final item = await chronicle('a', years: 5);
      final run = await vault.startRun('a');
      final text = item.renditions.whereType<TextRendition>().single.content;

      final report = await step.organize(item, runId: run);

      expect(report, const AiStepReport(applied: 5));
      final rows = await stored();
      expect(rows, hasLength(5));
      for (final row in rows) {
        expect(row.itemId, 'a');
        expect(row.origin, ContentOrigin.ai);
        expect(row.aiRunId, run);
        expect(row.renditionId, 'rend-a');
        // La cita es el tramo del texto entero que la posición dice.
        expect(text.substring(row.startOffset!, row.endOffset), row.excerpt);
        expect(row.title, 'Hecho de ${row.excerpt}');
      }
      expect(rows.map((r) => r.dateFromYear), [1500, 1501, 1502, 1503, 1504]);
    });

    test('un tramo se guarda con su fin', () async {
      final item = await chronicle(
        'a',
        text: 'La guerra duró de 1914 a 1918 y cambió Europa.',
      );

      await step.organize(item, runId: await vault.startRun('a'));

      final row = (await stored()).single;
      expect((row.dateFromYear, row.dateEndYear), (1914, 1918));
    });

    test('una nota de bloques no tiene un texto que abrir: queda la cita, sin '
        'posición ni forma', () async {
      const content = 'Nació en 1809 en Shrewsbury.';
      model.text = content;
      final at = vault.now;
      final note = KnowledgeItem(
        id: 'n',
        title: 'Darwin',
        source: Source(
          id: 'src-n',
          kind: SourceKind.manualNote,
          capturedAt: at,
        ),
        processingState: ProcessingState.ready,
        createdAt: at,
        updatedAt: at,
        renditions: [
          Rendition.text(
            id: 'rend-n',
            itemId: 'n',
            kind: RenditionKind.blocks,
            content: encodeContentBlocks([
              const ContentBlock.paragraph(text: content),
            ]),
            isPrimary: true,
            createdAt: at,
          ),
        ],
      );
      await vault.library.save(note);

      await step.organize(note, runId: await vault.startRun('n'));

      final row = (await stored()).single;
      expect(row.excerpt, '1809');
      expect(row.renditionId, isNull);
      expect(row.startOffset, isNull);
      expect(row.endOffset, isNull);
      expect(row.origin, ContentOrigin.ai);
    });

    test('no repite lo que ya está ni lo que la persona quitó', () async {
      final item = await chronicle('a', years: 4);
      await step.organize(item, runId: await vault.startRun('a'));
      final first = await stored();
      expect(first, hasLength(4));

      // Otra pasada sobre lo mismo: nada nuevo.
      final again = await step.organize(item, runId: await vault.startRun('a'));
      expect(again, AiStepReport.nothing);
      expect(await stored(), hasLength(4));

      // Quitar uno de la IA lo anota como «no era»: la pasada siguiente no lo
      // vuelve a poner.
      await events.remove(first.first.id);
      await step.organize(item, runId: await vault.startRun('a'));
      expect(await stored(), hasLength(3));
    });
  });

  group('por partes', () {
    test('un modelo que no alcanza a leer el pedido entero sigue con lo que '
        'falta: ningún pasaje se pierde ni se repite', () async {
      final item = await chronicle('a', years: 9);
      model
        ..budget = 3000
        ..readsAtMost = 2;
      final text = item.renditions.whereType<TextRendition>().single.content;
      final parts = selectDatedParts(text, maxChars: 3000);
      final passages = parts.expand((p) => p.passages).length;

      final report = await step.organize(
        item,
        runId: await vault.startRun('a'),
      );

      expect(passages, 9);
      // De a dos pasajes por pedido: más pedidos que partes, y cada pasaje se
      // leyó una sola vez —cada pedido trae lo que falta, y el modelo lee los
      // dos primeros—.
      expect(model.requests.length, greaterThan(parts.length));
      expect(
        model.requests.expand((p) => p.passages.take(2)).toList(),
        parts.expand((p) => p.passages).toList(),
      );
      expect(report.applied, 9);
      expect(await stored(), hasLength(9));
    });

    test('un modelo que no alcanza a leer ni un pasaje igual avanza, de a '
        'uno: no se traba', () async {
      final item = await chronicle('a', years: 5);
      model
        ..budget = 3000
        ..readsAtMost = 0;

      final report = await step.organize(
        item,
        runId: await vault.startRun('a'),
      );

      expect(model.requests, hasLength(5));
      expect(report, AiStepReport.nothing);
      expect(await stored(), isEmpty);
    });

    test('si el modelo lee todo y no encuentra ningún hecho, no guarda nada ni '
        'cuenta nada', () async {
      final item = await chronicle('a', years: 5);
      model.silent = true;

      final report = await step.organize(
        item,
        runId: await vault.startRun('a'),
      );

      expect(model.requests, isNotEmpty);
      expect(report, AiStepReport.nothing);
      expect(await stored(), isEmpty);
    });

    test('guarda al terminar cada pedido: los hechos aparecen a medida que se '
        'leen', () async {
      final item = await chronicle('a', years: 9);
      model
        ..budget = 500
        ..failAt = 3
        ..failure = () => throw StateError('se cortó');

      await expectLater(
        step.organize(item, runId: await vault.startRun('a')),
        throwsStateError,
      );

      final before = model.requests.take(2).expand((p) => p.passages).length;
      expect(before, greaterThan(0));
      expect(await stored(), hasLength(before));
    });

    test('dice cuántas partes lleva, para el porcentaje de «Ahora»', () async {
      final item = await chronicle('a', years: 30);
      model.budget = 500;
      final tracker = AiTaskTracker(clock: vault.clock);
      addTearDown(tracker.dispose);
      final task = tracker.begin(kind: AiTaskKind.organize, title: 'Crónica');
      final seen = <AiTaskProgress>[];
      tracker.tasks.addListener(() {
        final progress = tracker.tasks.value.firstOrNull?.partProgress;
        if (progress != null && (seen.isEmpty || seen.last != progress)) {
          seen.add(progress);
        }
      });
      final total = selectDatedParts(
        item.renditions.whereType<TextRendition>().single.content,
        maxChars: 500,
      ).length;

      await task.run(
        () async => step.organize(item, runId: await vault.startRun('a')),
      );

      expect(total, greaterThan(2));
      expect(
        seen.first,
        AiTaskProgress(done: 0, total: total, unit: AiTaskUnit.part),
      );
      expect(
        seen.last,
        AiTaskProgress(done: total, total: total, unit: AiTaskUnit.part),
      );
      expect(seen.map((p) => p.done), [for (var i = 0; i <= total; i++) i]);
    });
  });

  group('retomar', () {
    late KnowledgeItem item;
    late String run;
    late int total;

    setUp(() async {
      item = await chronicle('a', years: 30);
      // Con varios pasajes en cada pedido: hay dónde quedar a mitad de uno.
      model.budget = 1600;
      run = await vault.startRun('a');
      final parts = selectDatedParts(
        item.renditions.whereType<TextRendition>().single.content,
        maxChars: 1600,
      );
      total = parts.length;
      expect(total, greaterThan(3));
      expect(parts.first.passages.length, greaterThan(2));
    });

    test('si el modelo deja de contestar, retoma en la misma pasada desde el '
        'pasaje donde quedó: lo leído no se paga dos veces', () async {
      model.failAt = 3;

      await expectLater(
        step.findDates(item, runId: run),
        throwsA(isA<CloudModelException>()),
      );
      final readBefore = model.requests
          .take(2)
          .expand((p) => p.passages)
          .toList();
      expect(await stored(), hasLength(readBefore.length));

      model.requests.clear();
      final report = await step.findDates(item, runId: run);

      // Lo que se pide al retomar empieza donde quedó: ningún pasaje de los ya
      // leídos vuelve al modelo.
      final asked = model.requests.expand((p) => p.passages).toList();
      expect(asked.any(readBefore.contains), isFalse);
      expect(asked.first.start, greaterThanOrEqualTo(readBefore.last.end));
      // Y no falta ninguno: quedan los 30, cada uno una vez.
      expect(await stored(), hasLength(30));
      expect(report.applied, 30 - readBefore.length);
    });

    test('un tramo largo de oraciones fechadas, cortado en pasajes que se '
        'tocan, se retoma sin perder ninguno', () async {
      final text = [
        for (var i = 0; i < 40; i++) 'En el año ${1600 + i} pasó algo grande.',
      ].join(' ');
      final dense = await chronicle('b', text: text);
      model.budget = 500;
      final parts = selectDatedParts(text, maxChars: 500);
      final passages = parts.expand((p) => p.passages).toList();
      final other = await vault.startRun('b');
      expect(parts.length, greaterThan(2));
      // Pasajes de un mismo tramo: cada uno empieza donde termina el anterior
      // o cerca.
      expect(passages.length, greaterThan(2));
      model.failAt = 3;
      await expectLater(
        step.findDates(dense, runId: other),
        throwsA(isA<CloudModelException>()),
      );

      await step.findDates(dense, runId: other);

      expect((await stored()).map((e) => e.dateFromYear).toSet(), {
        for (var i = 0; i < 40; i++) 1600 + i,
      });
    });

    test('con otro error, que no es esperar al modelo, la próxima vez empieza '
        'de cero', () async {
      model
        ..failAt = 3
        ..failure = () => throw StateError('la respuesta vino rota');
      await expectLater(step.findDates(item, runId: run), throwsStateError);

      model.requests.clear();
      await step.findDates(item, runId: run);

      expect(model.requests.first.passages.first.start, 0);
      expect(await stored(), hasLength(30));
    });

    test('terminada la pasada, olvida hasta dónde llegó: pedirla de nuevo con '
        'el mismo identificador empieza de cero', () async {
      await step.findDates(item, runId: run);
      model.requests.clear();

      await step.findDates(item, runId: run);

      expect(model.requests.first.passages.first.start, 0);
    });

    test('si el texto cambió de forma —otra extracción, otro '
        'identificador—, también empieza de cero', () async {
      model.failAt = 3;
      await expectLater(
        step.findDates(item, runId: run),
        throwsA(isA<CloudModelException>()),
      );
      final reExtracted = item.copyWith(
        renditions: [
          (item.renditions.single as TextRendition).copyWith(id: 'rend-nueva'),
        ],
      );
      model.requests.clear();

      await step.findDates(reExtracted, runId: run);

      expect(model.requests.first.passages.first.start, 0);
    });

    test('si el texto cambió mientras esperaba, las posiciones ya no valen: '
        'empieza de cero', () async {
      model.failAt = 3;
      await expectLater(
        step.findDates(item, runId: run),
        throwsA(isA<CloudModelException>()),
      );

      // Se volvió a extraer: otro texto en la misma forma.
      final longer = '${_chronicle(30)} En el año 1999 se cerró la crónica.';
      model.text = longer;
      await vault.library.save(
        item.copyWith(
          renditions: [
            (item.renditions.single as TextRendition).copyWith(content: longer),
          ],
        ),
      );
      final changed = await vault.reload('a');
      model.requests.clear();

      await step.findDates(changed, runId: run);

      expect(model.requests.first.passages.first.start, 0);
    });
  });

  group('en la pasada', () {
    test(
      'la pasada cuenta sus fechas al cerrarse y deshacerla las saca todas',
      () async {
        final item = await chronicle('a', years: 6);
        final run = await vault.startRun('a');
        await step.organize(item, runId: run);

        final tally = (await vault.runs.finishRun(
          run,
        )).getOrElse((f) => fail('$f'));
        expect(tally.dates, 6);
        final listed = (await vault.runs.listRuns(
          itemId: 'a',
        )).getOrElse((f) => fail('$f')).single;
        expect(listed.created.dates, 6);
        expect(listed.remaining.dates, 6);

        final undone = (await vault.runs.undoRun(
          run,
        )).getOrElse((f) => fail('$f'));
        expect(undone.dates, 6);
        expect(await stored(), isEmpty);
      },
    );

    test(
      'lo que la persona editó ya es suyo: deshacer la pasada lo deja',
      () async {
        final item = await chronicle('a', years: 3);
        final run = await vault.startRun('a');
        await step.organize(item, runId: run);
        final mine = (await stored()).first;
        await events.update(
          mine.id,
          title: 'Mi título',
          date: (await events.watchForItem('a').first).first.date,
        );

        await vault.runs.undoRun(run);

        final left = await stored();
        expect(left.single.title, 'Mi título');
        expect(left.single.origin, ContentOrigin.user);
      },
    );
  });
}
