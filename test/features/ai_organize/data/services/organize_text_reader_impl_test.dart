import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/note_text.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/processed_reading.dart';
import 'package:sinapsis/features/ai_organize/data/services/organize_text_reader_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/services/organize_text.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/processed_rows.dart';

/// El texto que la IA lee de un documento procesado (F41, paso 6): solo lo
/// que se eligió, armado como lo leen los vectores, y lo que se encuentra en
/// una parte copiada tal cual se cita en la fuente, en su lugar.
void main() {
  late AiOrganizeHarness vault;
  late AppDatabase db;

  setUp(() {
    vault = AiOrganizeHarness();
    db = vault.db;
  });

  tearDown(() => vault.close());

  /// El texto de la fuente: dos «páginas» seguidas y una oración del resumen.
  const sourceText =
      'Darwin nació en 1809 en Shrewsbury. '
      'En 1859 publicó El origen de las especies. '
      'Murió en 1882.';

  Future<void> seedSource() async {
    await insertItemRows(db, id: 'fuente', title: 'Darwin');
    await db
        .into(db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'texto',
            itemId: 'fuente',
            kind: RenditionKind.plainText,
            content: const Value(sourceText),
            isPrimary: true,
            createdAt: vault.now,
          ),
        );
  }

  Future<void> part(
    String id,
    ProcessedSection section,
    int position,
    String content, {
    int? sourceStart,
    bool edited = false,
    bool user = false,
  }) => db
      .into(db.processedParts)
      .insert(
        ProcessedPartsCompanion.insert(
          id: id,
          documentId: 'p',
          section: section,
          position: position,
          content: content,
          origin: user ? ProcessedPartOrigin.user : ProcessedPartOrigin.copied,
          edited: Value(edited),
          sourceRenditionId: Value(user ? null : 'texto'),
          sourceStart: Value(user ? null : sourceStart),
          sourceEnd: Value(user ? null : sourceStart! + content.length),
          createdAt: vault.now,
          updatedAt: vault.now,
        ),
      );

  /// El procesado `p` de la fuente, sin partes: cada prueba pone las suyas.
  Future<void> seedDocument() async {
    await seedSource();
    await insertProcessedDocument(
      db,
      id: 'p',
      title: 'Darwin',
      sections: const {},
      sourceKind: SourceKind.document,
    );
    await (db.update(
      db.processedDocuments,
    )..where((d) => d.itemId.equals('p'))).write(
      const ProcessedDocumentsCompanion(sourceItemId: Value('fuente')),
    );
  }

  Future<OrganizeText> read(String itemId) async =>
      OrganizeTextReaderImpl(db).textOf(await vault.reload(itemId));

  const page1 = 'Darwin nació en 1809 en Shrewsbury. ';
  const page2 = 'En 1859 publicó El origen de las especies. ';

  test('lee las partes en el orden de lectura: las páginas pegadas, lo demás '
      'separado', () async {
    await seedDocument();
    // Fuera de orden a propósito: el lector las ordena.
    await part('nota', ProcessedSection.notes, 0, 'Mi idea.', user: true);
    await part('p2', ProcessedSection.text, 1, page2, sourceStart: 36);
    await part('p1', ProcessedSection.text, 0, page1, sourceStart: 0);
    await part(
      'r1',
      ProcessedSection.summary,
      0,
      'Murió en 1882.',
      sourceStart: 79,
    );

    final text = await read('p');

    expect(text.text, '$page1$page2\n\nMurió en 1882.\n\nMi idea.');
    expect(text.processed, isTrue);
    expect(text.ownRenditionId, isNull);
    // El mismo texto que describen sus vectores.
    expect(await noteTextOf(db, 'p'), text.text);
  });

  group('la cita', () {
    test('en una parte copiada tal cual va a la fuente, en su lugar', () async {
      await seedDocument();
      await part('p1', ProcessedSection.text, 0, page1, sourceStart: 0);
      await part('p2', ProcessedSection.text, 1, page2, sourceStart: 36);
      await part(
        'r1',
        ProcessedSection.summary,
        0,
        'Murió en 1882.',
        sourceStart: 79,
      );
      final text = await read('p');

      final quote = text.text.indexOf('En 1859');
      final cited = text.cite(quote, quote + 'En 1859 publicó'.length)!;
      expect(cited.renditionId, 'texto');
      expect(sourceText.substring(cited.start, cited.end), 'En 1859 publicó');

      final death = text.text.indexOf('Murió');
      final deathCited = text.cite(death, death + 'Murió en 1882'.length)!;
      expect(
        sourceText.substring(deathCited.start, deathCited.end),
        'Murió en 1882',
      );
    });

    test('un tramo que cruza dos páginas pegadas y seguidas en la fuente '
        'sigue siendo una cita', () async {
      await seedDocument();
      await part('p1', ProcessedSection.text, 0, page1, sourceStart: 0);
      await part('p2', ProcessedSection.text, 1, page2, sourceStart: 36);
      final text = await read('p');

      final start = text.text.indexOf('Shrewsbury');
      final end = text.text.indexOf(' publicó');
      final cited = text.cite(start, end)!;

      expect(
        sourceText.substring(cited.start, cited.end),
        'Shrewsbury. En 1859',
      );
    });

    test('no se cita lo que la fuente no tiene así: una parte editada, una '
        'nota, o un tramo que salta de una oración a otra', () async {
      await seedDocument();
      await part(
        'r1',
        ProcessedSection.summary,
        0,
        'Darwin nació en 1809.',
        sourceStart: 0,
        edited: true,
      );
      await part(
        'r2',
        ProcessedSection.summary,
        1,
        'Murió en 1882.',
        sourceStart: 79,
      );
      await part(
        'nota',
        ProcessedSection.notes,
        0,
        'En 1860 lo leí.',
        user: true,
      );
      final text = await read('p');

      int at(String s) => text.text.indexOf(s);
      expect(text.cite(at('1809'), at('1809') + 4), isNull);
      expect(text.cite(at('1860'), at('1860') + 4), isNull);
      // De la editada a la siguiente: hay un renglón en blanco en el medio y
      // párrafos de distancia en el original.
      expect(text.cite(at('1809'), at('1882') + 4), isNull);
      expect(text.cite(at('1882'), at('1882') + 4), isNotNull);
      // Fuera del texto, nada.
      expect(text.cite(-1, 3), isNull);
      expect(text.cite(0, text.text.length + 1), isNull);
    });

    test(
      'dos oraciones del resumen seguidas en la fuente no se citan juntas: '
      'entre ellas hay un renglón en blanco que el original no tiene',
      () async {
        await seedDocument();
        await part('r1', ProcessedSection.summary, 0, page1, sourceStart: 0);
        await part('r2', ProcessedSection.summary, 1, page2, sourceStart: 36);
        final text = await read('p');

        final start = text.text.indexOf('Shrewsbury');
        final end = text.text.indexOf(' publicó');

        expect(text.cite(start, end), isNull);
      },
    );

    test(
      'dos páginas pegadas que no eran seguidas en la fuente tampoco',
      () async {
        await seedDocument();
        await part('p1', ProcessedSection.text, 0, page1, sourceStart: 0);
        // La persona editó una página del medio y se paginó alrededor: la que
        // sigue empieza más adelante en el original.
        await part(
          'p2',
          ProcessedSection.text,
          1,
          'Murió en 1882.',
          sourceStart: 79,
        );
        final text = await read('p');

        final start = text.text.indexOf('Shrewsbury');
        final end = text.text.indexOf(' en 1882');

        expect(text.cite(start, end), isNull);
        expect(text.cite(end - 5, end), isNotNull);
      },
    );

    test('si la forma de la fuente se fue, no hay a dónde llevar', () async {
      await seedDocument();
      await part('p1', ProcessedSection.text, 0, page1, sourceStart: 0);
      await (db.update(db.processedParts)..where((p) => p.id.equals('p1')))
          .write(const ProcessedPartsCompanion(sourceRenditionId: Value(null)));
      final text = await read('p');

      expect(text.cite(0, 6), isNull);
    });
  });

  test('de una fuente o una nota, el texto de siempre: su forma, con sus '
      'posiciones', () async {
    await vault.source('s', title: 'S', content: 'En 1859 publicó.');

    final text = await read('s');

    expect(text.text, 'En 1859 publicó.');
    expect(text.processed, isFalse);
    expect(text.ownRenditionId, 'rend-s');
    expect(text.cite(3, 7), (renditionId: 'rend-s', start: 3, end: 7));
  });

  test('lee una vez por elemento: los pasos de una pasada comparten lo '
      'leído', () async {
    await seedDocument();
    await part('p1', ProcessedSection.text, 0, page1, sourceStart: 0);
    final reader = OrganizeTextReaderImpl(db);
    final item = await vault.reload('p');

    final first = await reader.textOf(item);
    await part('p2', ProcessedSection.text, 1, page2, sourceStart: 36);

    expect(identical(await reader.textOf(item), first), isTrue);
    expect((await reader.textOf(await vault.reload('p'))).text, page1 + page2);
  });

  test(
    'el comienzo de un libro procesado lee solo las primeras partes',
    () async {
      await seedDocument();
      for (var i = 0; i < 50; i++) {
        await part(
          'pagina-$i',
          ProcessedSection.text,
          i,
          'Página $i. ',
          sourceStart: i * 10,
        );
      }

      final head = await noteTextOf(db, 'p', upTo: 20);

      // Dos páginas de diez ya son los veinte caracteres pedidos.
      expect(head, 'Página 0. Página 1. ');
      expect(await noteTextOf(db, 'p'), startsWith(head!));
    },
  );

  test('joinProcessedParts dice dónde empieza cada parte y cuál va pegada', () {
    final joined = joinProcessedParts(const [
      (section: ProcessedSection.text, content: 'ab'),
      (section: ProcessedSection.text, content: 'cd'),
      (section: ProcessedSection.summary, content: 'ef'),
    ]);

    expect(joined.text, 'abcd\n\nef');
    expect(joined.starts, [0, 2, 6]);
    expect(joined.glued, [false, true, false]);
  });
}
