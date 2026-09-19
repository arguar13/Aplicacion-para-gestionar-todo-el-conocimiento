import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/migrations/backfill_inline_links_v15.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

import '../../support/fake_id_generator.dart';
import '../../support/silent_logger.dart';

class _RecordingLogger extends SilentLogger {
  _RecordingLogger();

  final infos = <String>[];

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) =>
      infos.add(message);
}

/// El registro de los `[[Título]]` de las notas que ya existían (F9): el plan
/// que se calcula sin escribir, su aplicación y el informe de lo que quedó
/// roto. Probado contra SQLite real.
void main() {
  late AppDatabase db;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 19, 10);
  final jan1 = DateTime(2026);
  final jan2 = DateTime(2026, 1, 2);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator(prefix: 'gen');
  });

  tearDown(() => db.close());

  Future<void> seedItem(String id, String title, {DateTime? createdAt}) async {
    final at = createdAt ?? now;
    await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            id: 'src-$id',
            kind: SourceKind.webPage,
            capturedAt: at,
          ),
        );
    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            title: title,
            sourceId: 'src-$id',
            processingState: ProcessingState.ready,
            createdAt: at,
            updatedAt: at,
          ),
        );
  }

  Future<void> addRendition(
    String itemId,
    RenditionKind kind,
    String content,
  ) => db
      .into(db.renditions)
      .insert(
        RenditionsCompanion.insert(
          id: 'r-$itemId-${kind.name}',
          itemId: itemId,
          kind: kind,
          content: Value(content),
          isPrimary: true,
          createdAt: now,
        ),
      );

  /// Una nota armada con bloques: un párrafo por cada texto de [paragraphs].
  Future<void> seedNote(
    String id,
    String title,
    List<String> paragraphs, {
    DateTime? createdAt,
  }) async {
    await seedItem(id, title, createdAt: createdAt);
    await addRendition(
      id,
      RenditionKind.blocks,
      encodeContentBlocks([
        for (final text in paragraphs) ContentBlock.paragraph(text: text),
      ]),
    );
  }

  Future<Set<(String, String, String?)>> registered() async => {
    for (final link in await db.select(db.inlineLinks).get())
      (link.fromItemId, link.normalizedTitle, link.toItemId),
  };

  Future<Set<String>> issueIds() async => {
    for (final issue in await db.select(db.migrationIssues).get()) issue.id,
  };

  group('planInlineLinkBackfill', () {
    test('no escribe nada: es el ensayo de la migración', () async {
      await seedItem('roma', 'Roma');
      await seedNote('n1', 'Viaje', ['Fui a [[Roma]] y a [[Cartago]].']);

      final plan = await planInlineLinkBackfill(db);

      expect(plan.links, hasLength(2));
      expect(await db.select(db.inlineLinks).get(), isEmpty);
      expect(await db.select(db.migrationIssues).get(), isEmpty);
    });

    test('resuelve el enlace contra el título de otro elemento, sin distinguir '
        'mayúsculas ni espacios en los bordes', () async {
      await seedItem('roma', 'Roma');
      await seedNote('n1', 'Viaje', ['Fui a [[  roMA ]].']);

      final plan = await planInlineLinkBackfill(db);

      expect(plan.links, hasLength(1));
      final link = plan.links.single;
      expect(link.fromItemId, 'n1');
      // El título se guarda como se escribió, recortado; comparar, se compara
      // en minúsculas.
      expect(link.title, 'roMA');
      expect(link.normalizedTitle, 'roma');
      expect(link.toItemId, 'roma');
      expect((plan.resolved, plan.broken), (1, 0));
    });

    test('un enlace sin ningún elemento con ese título queda roto', () async {
      await seedNote('n1', 'Viaje', ['Fui a [[Cartago]].']);

      final plan = await planInlineLinkBackfill(db);

      expect(plan.links.single.toItemId, isNull);
      expect((plan.resolved, plan.broken), (0, 1));
    });

    test('si varios elementos se llaman igual, el destino es el más '
        'antiguo, no el primero que devuelva la base', () async {
      // El más antiguo tiene el id MAYOR: no gana por orden alfabético ni por
      // orden de inserción.
      await seedItem('z-roma', 'Roma', createdAt: jan1);
      await seedItem('a-roma', 'Roma', createdAt: jan2);
      await seedNote('n1', 'Viaje', ['[[Roma]]']);

      final plan = await planInlineLinkBackfill(db);

      expect(plan.links.single.toItemId, 'z-roma');
    });

    test('con la misma antigüedad desempata el id menor', () async {
      await seedItem('b-igual', 'Igual', createdAt: jan1);
      await seedItem('a-igual', 'Igual', createdAt: jan1);
      await seedNote('n1', 'Viaje', ['[[Igual]]']);

      final plan = await planInlineLinkBackfill(db);

      expect(plan.links.single.toItemId, 'a-igual');
    });

    test('una nota que se enlaza a sí misma no registra ese enlace', () async {
      await seedNote('yo', 'Yo', ['Hablo de [[yo]].']);

      final plan = await planInlineLinkBackfill(db);

      expect(plan.links, isEmpty);
      expect(plan.selfLinks, 1);
      expect(plan.hasWork, isFalse);
    });

    test('un homónimo de la propia nota sí es un destino válido', () async {
      // La nota más antigua se llama "Tema" y se enlaza a "Tema": el destino
      // es el OTRO elemento con ese título, no ella.
      await seedNote('n', 'Tema', ['[[tema]]'], createdAt: jan1);
      await seedItem('otro', 'Tema', createdAt: jan2);

      final plan = await planInlineLinkBackfill(db);

      expect(plan.links.single.toItemId, 'otro');
      expect(plan.selfLinks, 0);
    });

    test('el mismo destino escrito en dos bloques es un solo enlace', () async {
      await seedItem('roma', 'Roma');
      await seedNote('n1', 'Viaje', [
        'Fui a [[Roma]].',
        'Volvería a [[roma]].',
      ]);

      final plan = await planInlineLinkBackfill(db);

      expect(plan.links, hasLength(1));
    });

    test('lee solo las notas de bloques: el Markdown no se toca', () async {
      await seedItem('roma', 'Roma');
      await seedItem('md', 'Un artículo');
      await addRendition(
        'md',
        RenditionKind.markdown,
        'Un texto ajeno con [[Roma]] escrito.',
      );

      final plan = await planInlineLinkBackfill(db);

      expect(plan.notesScanned, 0);
      expect(plan.links, isEmpty);
    });

    test('recorre todas las notas aunque no quepan en una página', () async {
      await seedItem('destino', 'Destino');
      const notes = 450; // más de dos páginas de 200.
      await db.batch((batch) {
        for (var i = 0; i < notes; i++) {
          batch
            ..insert(
              db.sources,
              SourcesCompanion.insert(
                id: 'src-n$i',
                kind: SourceKind.webPage,
                capturedAt: now,
              ),
            )
            ..insert(
              db.items,
              ItemsCompanion.insert(
                id: 'n$i',
                title: 'Nota $i',
                sourceId: 'src-n$i',
                processingState: ProcessingState.ready,
                createdAt: now,
                updatedAt: now,
              ),
            )
            ..insert(
              db.renditions,
              RenditionsCompanion.insert(
                id: 'r-n$i',
                itemId: 'n$i',
                kind: RenditionKind.blocks,
                content: Value(
                  encodeContentBlocks(const [
                    ContentBlock.paragraph(text: 'Ver [[Destino]].'),
                  ]),
                ),
                isPrimary: true,
                createdAt: now,
              ),
            );
        }
      });

      final plan = await planInlineLinkBackfill(db);

      expect(plan.notesScanned, notes);
      expect(plan.links, hasLength(notes));
      expect(plan.links.every((l) => l.toItemId == 'destino'), isTrue);
    });

    test('una nota con bloques ilegibles se informa y no frena a las '
        'demás', () async {
      await seedItem('roma', 'Roma');
      await seedItem('mala', 'Nota rota');
      await addRendition('mala', RenditionKind.blocks, 'esto no es json');
      await seedNote('buena', 'Nota buena', ['[[Roma]]']);

      final plan = await planInlineLinkBackfill(db);

      expect(plan.unreadable, ['mala']);
      expect(plan.notesScanned, 2);
      expect(plan.links.single.fromItemId, 'buena');
    });

    test('no repite un enlace que ya estaba registrado', () async {
      await seedItem('roma', 'Roma');
      await seedNote('n1', 'Viaje', ['[[Roma]] y [[Cartago]]']);
      await db
          .into(db.inlineLinks)
          .insert(
            InlineLinksCompanion.insert(
              id: 'previo',
              fromItemId: 'n1',
              targetTitle: 'Roma',
              normalizedTitle: 'roma',
              toItemId: const Value('roma'),
              createdAt: now,
            ),
          );

      final plan = await planInlineLinkBackfill(db);

      expect(plan.alreadyRegistered, 1);
      expect(plan.links.map((l) => l.normalizedTitle), ['cartago']);
    });

    test('el resumen cuenta lo que hará', () async {
      await seedItem('roma', 'Roma');
      await seedNote('n1', 'Viaje', ['[[Roma]] y [[Cartago]]']);

      final plan = await planInlineLinkBackfill(db);

      expect(plan.summary(), contains('2 enlaces por registrar'));
      expect(plan.summary(), contains('1 con destino, 1 rotos'));
    });
  });

  group('backfillInlineLinks', () {
    Future<InlineLinkBackfillPlan> run({_RecordingLogger? logger}) =>
        backfillInlineLinks(
          db,
          ids: ids,
          logger: logger ?? _RecordingLogger(),
          clock: () => now,
        );

    test('registra cada enlace, con su destino o roto', () async {
      await seedItem('roma', 'Roma');
      await seedNote('n1', 'Viaje', ['[[Roma]] y [[Cartago]]']);

      await run();

      expect(await registered(), {
        ('n1', 'roma', 'roma'),
        ('n1', 'cartago', null),
      });
      final links = await db.select(db.inlineLinks).get();
      expect(links.map((l) => l.createdAt).toSet(), {now});
    });

    test('deja en MigrationIssues solo los enlaces rotos', () async {
      await seedItem('roma', 'Roma');
      await seedNote('n1', 'Viaje', ['[[Roma]] y [[Cartago]]']);

      await run();

      final issues = await db.select(db.migrationIssues).get();
      expect(issues, hasLength(1));
      final issue = issues.single;
      expect(issue.migration, 'f9_inline_links');
      expect(issue.stage, 'broken_inline_link');
      expect(issue.itemId, 'n1');
      expect(issue.message, contains('[[Cartago]]'));
    });

    test('las notas ilegibles quedan informadas, con su id', () async {
      await seedItem('mala', 'Nota rota');
      await addRendition('mala', RenditionKind.blocks, '{"no": "es lista"}');

      await run();

      final issues = await db.select(db.migrationIssues).get();
      expect(issues.map((i) => (i.stage, i.itemId)), [
        ('unreadable_blocks', 'mala'),
      ]);
      expect(await db.select(db.inlineLinks).get(), isEmpty);
    });

    test(
      'no crea relaciones: registra lo que el texto dice, nada más',
      () async {
        await seedItem('roma', 'Roma');
        await seedNote('n1', 'Viaje', ['[[Roma]]']);

        await run();

        expect(await db.select(db.relations).get(), isEmpty);
      },
    );

    test('es idempotente: una segunda corrida no escribe nada', () async {
      await seedItem('roma', 'Roma');
      await seedNote('n1', 'Viaje', ['[[Roma]] y [[Cartago]]']);
      await seedItem('mala', 'Nota rota');
      await addRendition('mala', RenditionKind.blocks, 'esto no es json');

      await run();
      final linksAfterFirst = await registered();
      final issuesAfterFirst = await issueIds();
      // Un enlace roto y una nota ilegible: dos informes.
      expect(issuesAfterFirst, hasLength(2));

      final second = await run();

      expect(second.links, isEmpty);
      expect(second.alreadyRegistered, 2);
      expect(await registered(), linksAfterFirst);
      // Ni el enlace roto ni la nota ilegible se informan de nuevo.
      expect(await issueIds(), issuesAfterFirst);
    });

    test(
      'registra en el log lo que va a hacer, y calla si no hay nada',
      () async {
        await seedItem('roma', 'Roma');
        await seedNote('n1', 'Viaje', ['[[Roma]]']);

        final first = _RecordingLogger();
        await run(logger: first);
        expect(first.infos, hasLength(1));
        expect(first.infos.single, contains('1 enlaces por registrar'));

        final second = _RecordingLogger();
        await run(logger: second);
        expect(second.infos, isEmpty);
      },
    );

    test('una bóveda sin notas no escribe ni informa', () async {
      await seedItem('roma', 'Roma');

      final plan = await run();

      expect(plan.hasWork, isFalse);
      expect(await db.select(db.inlineLinks).get(), isEmpty);
      expect(await db.select(db.migrationIssues).get(), isEmpty);
    });
  });

  group('la tabla inline_link', () {
    Future<void> link(String id, String from, String title, {String? to}) => db
        .into(db.inlineLinks)
        .insert(
          InlineLinksCompanion.insert(
            id: id,
            fromItemId: from,
            targetTitle: title,
            normalizedTitle: title.toLowerCase(),
            toItemId: Value(to),
            createdAt: now,
          ),
        );

    test('borrar el destino deja el enlace roto: no lo borra', () async {
      await seedItem('roma', 'Roma');
      await seedItem('n1', 'Viaje');
      await link('l1', 'n1', 'Roma', to: 'roma');

      await (db.delete(db.items)..where((i) => i.id.equals('roma'))).go();

      final links = await db.select(db.inlineLinks).get();
      expect(links, hasLength(1));
      expect(links.single.toItemId, isNull);
      // El texto de la nota sigue diciendo [[Roma]]: el título se conserva.
      expect(links.single.targetTitle, 'Roma');
    });

    test('borrar la nota borra los enlaces que contenía', () async {
      await seedItem('roma', 'Roma');
      await seedItem('n1', 'Viaje');
      await link('l1', 'n1', 'Roma', to: 'roma');

      await (db.delete(db.items)..where((i) => i.id.equals('n1'))).go();

      expect(await db.select(db.inlineLinks).get(), isEmpty);
    });

    test(
      'la misma nota no puede registrar dos veces el mismo destino',
      () async {
        await seedItem('n1', 'Viaje');
        await link('l1', 'n1', 'Roma');

        await expectLater(
          link('l2', 'n1', 'Roma'),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('dos notas sí pueden enlazar al mismo destino', () async {
      await seedItem('n1', 'Uno');
      await seedItem('n2', 'Dos');
      await link('l1', 'n1', 'Roma');
      await link('l2', 'n2', 'Roma');

      expect(await db.select(db.inlineLinks).get(), hasLength(2));
    });
  });
}
