import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/processed/data/services/processed_headings_indexer.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/headings/processed_headings.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../../support/index_fakes.dart';
import '../../../../support/processed_rows.dart';
import '../../processed_harness.dart';

/// Las entradas de texto del Índice (F46, paso 2) se escriben con el texto:
/// en la misma transacción que lo guarda —el PDF se lee antes—, solo las de
/// ese documento, y nunca quedan viejas: lo que cambia el texto por otro
/// camino las suelta en la misma sentencia.
void main() {
  const romaText =
      '# Roma\nLa ciudad eterna.\n## La República\nEl Senado.\n'
      '## El Imperio\nAugusto.';

  late ProcessedHarness h;
  late FakeHeadingsExtractor extractor;
  late FakePdfOutlineReader outlines;

  setUp(() async {
    extractor = FakeHeadingsExtractor();
    outlines = FakePdfOutlineReader();
    h = await ProcessedHarness.create(headings: extractor, outlines: outlines);
  });
  tearDown(() => h.close());

  ProcessedHeadingsIndexer indexer() => h.indexer!;

  /// Las entradas de [documentId] como `nivel título` —«Texto completo» por su
  /// nombre—, en su orden.
  Future<List<String>> entries(AppDatabase db, String documentId) async => [
    for (final row
        in await db
            .customSelect(
              'SELECT origin, level, title FROM processed_headings '
              "WHERE document_id = ? ORDER BY origin = 'image', position",
              variables: [Variable.withString(documentId)],
            )
            .get())
      _label(row),
  ];

  Future<String> processed(String sourceId, String text) async {
    await h.vault.saveSource(sourceId, text: text, title: 'Fuente $sourceId');
    final result = await h.process(sourceId, {
      ProcessedSection.text: SectionEdit.update(),
    });
    return result.getRight().toNullable()!.documentId;
  }

  Future<ProcessedPart> page(String documentId, [int position = 0]) async =>
      (await h.repository.partsOf(
        documentId,
        sections: {ProcessedSection.text},
      )).getRight().toNullable()!.firstWhere((p) => p.position == position);

  /// Un documento con [pages] de «Texto», como lo deja la unión o una base de
  /// antes de v51: sin entradas.
  Future<void> document(
    String id,
    List<String> pages, {
    String? sourceItemId,
  }) => insertProcessedRows(
    h.db,
    id: id,
    title: 'Documento $id',
    sourceItemId: sourceItemId,
    parts: {ProcessedSection.text: pages},
  );

  group('al guardar el texto', () {
    test('procesar una fuente escribe sus títulos, con su nivel, su tramo y '
        'su página del texto', () async {
      final roma = await processed('roma', romaText);

      final rows = await (h.db.select(
        h.db.processedHeadings,
      )..orderBy([(r) => OrderingTerm.asc(r.position)])).get();
      expect(
        [for (final r in rows) (r.level, r.title, r.textPage)],
        [(1, 'Roma', 1), (2, 'La República', 1), (2, 'El Imperio', 1)],
      );
      expect(rows.map((r) => r.origin).toSet(), {IndexEntryOrigin.textHeading});
      expect(rows.map((r) => r.documentId).toSet(), {roma});
      expect(rows.map((r) => r.position), [0, 1, 2]);
      final own = (await page(roma)).content;
      for (final row in rows) {
        expect(own.substring(row.textStart!, row.textEnd), row.title);
      }
    });

    test('el lector recibe las páginas de «Texto» en su orden y la clase de '
        'texto; sin PDF, ningún marcador', () async {
      final roma = await processed('roma', romaText);

      final source = extractor.calls.single;
      expect(source.pages, [(await page(roma)).content]);
      expect(source.kind, ProcessedTextKind.markdown);
      expect(source.pdf, isNull);
      expect(outlines.reads, isEmpty);
    });

    test('un texto sin títulos tiene una sola entrada: «Texto completo», que '
        'lo abre desde el principio', () async {
      final doc = await processed('plano', 'Una transcripción sin títulos.');

      final row = await (h.db.select(
        h.db.processedHeadings,
      )..where((r) => r.documentId.equals(doc))).getSingle();
      expect(row.origin, IndexEntryOrigin.wholeText);
      expect(row.title, '');
      expect(
        (row.level, row.textStart, row.textEnd, row.textPage),
        (1, 0, 0, 1),
      );
    });

    test('lo que devuelve el lector se sanea antes de guardarse: un título en '
        'blanco no entra, los niveles se corren y un tramo fuera del texto se '
        'pierde con su página', () async {
      extractor.answer = (_) => const [
        ProcessedHeading(
          order: 0,
          level: 1,
          title: '  ',
          origin: ProcessedHeadingOrigin.aiTitle,
        ),
        ProcessedHeading(
          order: 1,
          level: 3,
          title: ' Uno ',
          origin: ProcessedHeadingOrigin.aiTitle,
          start: 900,
          end: 910,
          textPage: 1,
          pdfPage: 4,
        ),
        ProcessedHeading(
          order: 2,
          level: 4,
          title: 'Dos',
          origin: ProcessedHeadingOrigin.aiTitle,
          start: 0,
          end: 3,
          textPage: 1,
        ),
      ];
      final doc = await processed('ia', 'Dos y algo más.');

      final rows = await (h.db.select(
        h.db.processedHeadings,
      )..where((r) => r.documentId.equals(doc))).get();
      expect(
        [
          for (final r in rows)
            (r.position, r.title, r.level, r.textStart, r.textPage, r.pdfPage),
        ],
        [(0, 'Uno', 1, null, null, 4), (1, 'Dos', 2, 0, 1, null)],
      );
      expect(rows.map((r) => r.origin).toSet(), {IndexEntryOrigin.aiTitle});
    });

    test('editar una página rehace los títulos en la MISMA transacción: desde '
        'otra conexión, mientras se leen, todavía se ve lo de antes', () async {
      await h.close();
      final dir = await Directory.systemTemp.createTemp('sinapsis_indice_');
      final file = File('${dir.path}/sinapsis.sqlite');
      h = await ProcessedHarness.create(
        executor: NativeDatabase(file),
        headings: extractor,
        outlines: outlines,
      );
      final peek = sqlite.sqlite3.open(file.path);
      addTearDown(() async {
        peek.close();
        await h.close();
        await dir.delete(recursive: true);
      });
      final roma = await processed('roma', romaText);
      final first = await page(roma);
      final seen = <(String, int)>[];
      extractor.during = (_) async {
        seen.add((
          peek.select('SELECT content FROM processed_parts WHERE id = ?', [
                first.id,
              ]).single['content']
              as String,
          peek.select(
                'SELECT COUNT(*) AS n FROM processed_headings '
                'WHERE document_id = ?',
                [roma],
              ).single['n']
              as int,
        ));
      };

      await h.repository.editPart(
        first.id,
        romaText.replaceFirst('## El Imperio', '## El Principado'),
      );

      // Desde afuera, mientras el lector trabajaba: ni el texto nuevo ni sus
      // entradas sueltas. Todo junto o nada.
      expect(seen, [(first.content, 3)]);
      expect(await entries(h.db, roma), [
        '1 Roma',
        '2 La República',
        '2 El Principado',
      ]);
      expect(
        peek
            .select('SELECT title FROM processed_headings WHERE position = 2')
            .single['title'],
        'El Principado',
      );
    });

    test(
      'quitar una página y devolverla: los títulos siguen al texto',
      () async {
        await document('doc', ['# Uno\n', '# Dos\n', 'tres']);
        await h.repository.restorePart(
          (await page('doc', 2)).copyWith(content: 'tres\n# Tres'),
        );
        expect(await entries(h.db, 'doc'), ['1 Uno', '1 Dos', '1 Tres']);

        final second = await page('doc', 1);
        await h.repository.removePart(second.id);
        expect(await entries(h.db, 'doc'), ['1 Uno', '1 Tres']);

        await h.repository.restorePart(second);
        expect(await entries(h.db, 'doc'), ['1 Uno', '1 Dos', '1 Tres']);
      },
    );

    test('deshacer lo procesado deja los títulos de antes', () async {
      final roma = await processed('roma', romaText);
      await h.vault.saveSource('roma', text: '# Cartago\nDelenda est.');
      final result = await h.process('roma', {
        ProcessedSection.text: SectionEdit.replace(
          const SectionInput.fromSource(),
        ),
      });
      expect(await entries(h.db, roma), ['1 Cartago']);

      await h.repository.undo(result.getRight().toNullable()!.undo);

      expect(await entries(h.db, roma), [
        '1 Roma',
        '2 La República',
        '2 El Imperio',
      ]);
    });

    test('solo las de ese documento: las de los demás no se tocan', () async {
      final roma = await processed('roma', romaText);
      final otro = await processed('otro', '# Otro\nalgo');
      final before = await (h.db.select(
        h.db.processedHeadings,
      )..where((r) => r.documentId.equals(otro))).get();

      await h.repository.editPart((await page(roma)).id, '# Solo Roma');

      expect(
        await (h.db.select(
          h.db.processedHeadings,
        )..where((r) => r.documentId.equals(otro))).get(),
        before,
      );
      expect(await entries(h.db, roma), ['1 Solo Roma']);
    });

    test('si el lector falla, el texto se guarda igual y el documento queda '
        'sin indexar —sin entradas viejas—', () async {
      final roma = await processed('roma', romaText);
      extractor.failWith = Exception('no');

      final edited = await h.repository.editPart(
        (await page(roma)).id,
        '# Otra cosa',
      );

      expect(edited.isRight(), isTrue);
      expect((await page(roma)).content, '# Otra cosa');
      expect(await entries(h.db, roma), isEmpty);
    });

    test('sin quien escriba el Índice, el texto se guarda y el documento '
        'queda para el relleno', () async {
      final sinIndice = await ProcessedHarness.create(deviceId: 'pc');
      addTearDown(sinIndice.close);
      await sinIndice.vault.saveSource('roma', text: romaText);
      final result = await sinIndice.process('roma', {
        ProcessedSection.text: SectionEdit.update(),
      });

      expect(result.isRight(), isTrue);
      expect(
        await entries(sinIndice.db, result.getRight().toNullable()!.documentId),
        isEmpty,
      );
    });
  });

  group('un PDF', () {
    final bookmarks = PdfOutline(
      pageCount: 300,
      bookmarks: const [
        PdfBookmark(title: 'Primera parte', depth: 1, page: 3),
        PdfBookmark(title: 'El Concilio de Nicea', depth: 2, page: 47),
      ],
    );

    Future<void> withCopy(String id, {String name = 'libro.pdf'}) async {
      await document(id, ['Texto del libro.']);
      await h.vault.writeOriginal('originales/$id/$name', '%PDF-1.4');
      await _insertOriginal(h.db, id, path: 'originales/$id/$name');
    }

    test('sus marcadores se leen ANTES de la transacción, y van con su página '
        'real', () async {
      outlines.outlines['libro.pdf'] = bookmarks;
      await withCopy('libro');

      expect(await indexer().refresh('libro'), HeadingsRefresh.deferred);
      expect(await entries(h.db, 'libro'), isEmpty);

      await indexer().prepare('libro');
      expect(await indexer().refresh('libro'), HeadingsRefresh.indexed);

      expect(extractor.calls.single.kind, ProcessedTextKind.pdf);
      expect(extractor.calls.single.pdf, bookmarks);
      final rows = await (h.db.select(
        h.db.processedHeadings,
      )..orderBy([(r) => OrderingTerm.asc(r.position)])).get();
      expect(
        [for (final r in rows) (r.origin, r.level, r.title, r.pdfPage)],
        [
          (IndexEntryOrigin.bookmark, 1, 'Primera parte', 3),
          (IndexEntryOrigin.bookmark, 2, 'El Concilio de Nicea', 47),
        ],
      );
    });

    test('lo leído se recuerda: corregir una página no vuelve a abrir el PDF, '
        'pero sí rehace las filas', () async {
      outlines.outlines['libro.pdf'] = bookmarks;
      await withCopy('libro');
      await indexer().prepare('libro');
      await indexer().refresh('libro');

      await h.repository.editPart((await page('libro')).id, 'Otro texto.');

      expect(outlines.reads, ['libro.pdf']);
      expect(extractor.calls, hasLength(2));
      expect(await entries(h.db, 'libro'), [
        '1 Primera parte',
        '2 El Concilio de Nicea',
      ]);
    });

    test('corregir una página de un PDF que nadie leyó todavía —recién '
        'abierta la app— lo lee antes de guardar', () async {
      outlines.outlines['libro.pdf'] = bookmarks;
      await withCopy('libro');

      await h.repository.editPart((await page('libro')).id, 'Otro texto.');

      expect(outlines.reads, ['libro.pdf']);
      expect(await entries(h.db, 'libro'), [
        '1 Primera parte',
        '2 El Concilio de Nicea',
      ]);
    });

    test(
      'uno que no se puede leer vale sin marcadores: los títulos de la IA',
      () async {
        outlines.unreadable.add('libro.pdf');
        await withCopy('libro');

        await indexer().prepare('libro');
        expect(await indexer().refresh('libro'), HeadingsRefresh.indexed);

        expect(extractor.calls.single.kind, ProcessedTextKind.pdf);
        expect(extractor.calls.single.pdf, isNull);
      },
    );

    test('una falla que no es del archivo no se recuerda: queda para el '
        'relleno, que lo vuelve a leer', () async {
      await withCopy('libro');
      outlines.failWith = const FileSystemException('ocupado');

      await indexer().prepare('libro');
      expect(await indexer().refresh('libro'), HeadingsRefresh.deferred);

      outlines.failWith = null;
      await indexer().prepare('libro');
      expect(await indexer().refresh('libro'), HeadingsRefresh.indexed);
      expect(outlines.reads, ['libro.pdf', 'libro.pdf']);
    });

    test('sin copia del original, el PDF de su fuente —solo se lee—', () async {
      await h.vault.writeOriginal('originales/fuente/fuente.pdf', '%PDF-1.4');
      final at = h.vault.now;
      await h.vault.library.save(
        KnowledgeItem(
          id: 'fuente',
          title: 'La fuente',
          source: Source(
            id: 'fuente',
            kind: SourceKind.document,
            capturedAt: at,
            originalFilePath: 'originales/fuente/fuente.pdf',
          ),
          processingState: ProcessingState.ready,
          createdAt: at,
          updatedAt: at,
        ),
      );
      outlines.outlines['fuente.pdf'] = bookmarks;
      await document('doc', ['Texto.'], sourceItemId: 'fuente');

      await indexer().prepare('doc');
      await indexer().refresh('doc');

      expect(outlines.reads, ['fuente.pdf']);
      expect(extractor.calls.single.pdf, bookmarks);
    });

    test('al triar con la copia del original, el repositorio la lee antes '
        'de guardar', () async {
      outlines.outlines['libro.pdf'] = bookmarks;
      await h.vault.writeOriginal('originales/libro/libro.pdf', '%PDF-1.4');
      final at = h.vault.now;
      await h.vault.library.save(
        KnowledgeItem(
          id: 'libro',
          title: 'El libro',
          source: Source(
            id: 'libro',
            kind: SourceKind.document,
            capturedAt: at,
            originalFilePath: 'originales/libro/libro.pdf',
          ),
          processingState: ProcessingState.ready,
          createdAt: at,
          updatedAt: at,
          renditions: [
            Rendition.text(
              id: 'rend-libro',
              itemId: 'libro',
              kind: RenditionKind.plainText,
              content: 'El texto del libro.',
              isPrimary: true,
              createdAt: at,
            ),
          ],
        ),
      );

      final result = await h.process('libro', {
        ProcessedSection.text: SectionEdit.update(),
      }, original: const OriginalEdit(ProcessedChange.add));

      expect(result.isRight(), isTrue);
      expect(await entries(h.db, result.getRight().toNullable()!.documentId), [
        '1 Primera parte',
        '2 El Concilio de Nicea',
      ]);
    });
  });

  group('refresh', () {
    test(
      'sin texto no hay nada que leer; ya indexado, no se vuelve a pedir',
      () async {
        await insertProcessedRows(h.db, id: 'notas', title: 'Notas');
        await document('libro', ['# Uno']);

        expect(await indexer().refresh('notas'), HeadingsRefresh.noText);
        expect(await indexer().refresh('libro'), HeadingsRefresh.indexed);
        expect(await indexer().refresh('libro'), HeadingsRefresh.upToDate);
        expect(extractor.calls, hasLength(1));
      },
    );

    test('si el lector falla, devuelve que falló y no escribe nada', () async {
      await document('libro', ['# Uno']);
      extractor.failWith = Exception('no');

      expect(await indexer().refresh('libro'), HeadingsRefresh.failed);
      expect(await entries(h.db, 'libro'), isEmpty);
    });

    test('un texto en blanco igual tiene su «Texto completo»: un documento '
        'con texto nunca queda sin entradas', () async {
      extractor.answer = (_) => const [];
      await document('blanco', ['   ']);

      expect(await indexer().refresh('blanco'), HeadingsRefresh.indexed);
      expect(await entries(h.db, 'blanco'), ['1 «Texto completo»']);
    });
  });

  group('lo que cambia el texto por otro camino suelta las entradas en la '
      'misma sentencia', () {
    setUp(() async {
      await insertProcessedRows(
        h.db,
        id: 'doc',
        title: 'Doc',
        parts: {
          ProcessedSection.text: ['# Uno\n', '# Dos\n'],
          ProcessedSection.summary: ['Un resumen.'],
        },
      );
      await indexer().refresh('doc');
      expect(await entries(h.db, 'doc'), ['1 Uno', '1 Dos']);
    });

    Future<void> sql(String statement) => h.db.customStatement(statement);

    test('una página que cambia, se mueve, entra o se va', () async {
      const relocated =
          'UPDATE processed_parts SET text_start = 3, text_end = 9 '
          "WHERE id = 'doc-text-1'";
      const reanchored =
          'UPDATE processed_parts SET source_start = 1, source_end = 2 '
          "WHERE id = 'doc-text-1'";
      // Una página que entra como la trae la unión de bóvedas.
      const merged =
          'INSERT INTO processed_parts (id, document_id, section, position, '
          'content, origin, edited, source_start, source_end, created_at, '
          "updated_at) VALUES ('nueva', 'doc', 'text', 9, '# Nueva', "
          "'copied', 0, 0, 7, 0, 0)";
      for (final statement in [
        "UPDATE processed_parts SET content = '# Otro' WHERE id = 'doc-text-0'",
        "UPDATE processed_parts SET position = 5 WHERE id = 'doc-text-1'",
        relocated,
        reanchored,
        "DELETE FROM processed_parts WHERE id = 'doc-text-1'",
        merged,
      ]) {
        await indexer().refresh('doc');
        expect(await entries(h.db, 'doc'), isNotEmpty, reason: statement);
        await sql(statement);
        expect(await entries(h.db, 'doc'), isEmpty, reason: statement);
      }
    });

    test('la copia del original que entra, cambia o se va', () async {
      await _insertOriginal(h.db, 'doc', path: 'originales/doc/a.docx');
      expect(await entries(h.db, 'doc'), isEmpty);

      await indexer().refresh('doc');
      await sql("UPDATE processed_originals SET text_hash = 'otro'");
      expect(await entries(h.db, 'doc'), isEmpty);

      await indexer().refresh('doc');
      await sql('DELETE FROM processed_originals');
      expect(await entries(h.db, 'doc'), isEmpty);
    });

    test('lo que no es la sección «Texto» no las toca', () async {
      await sql(
        "UPDATE processed_parts SET content = 'Otro resumen.' "
        "WHERE section = 'summary'",
      );
      await sql("DELETE FROM processed_parts WHERE section = 'summary'");

      expect(await entries(h.db, 'doc'), ['1 Uno', '1 Dos']);
    });
  });

  group('se van con lo suyo', () {
    test('borrar de verdad el documento se lleva sus entradas y su índice de '
        'texto', () async {
      final roma = await processed('roma', romaText);
      await h.vault.writer.trash([roma]);
      await h.vault.writer.purge(roma);

      expect(await h.db.select(h.db.processedHeadings).get(), isEmpty);
      expect(
        (await h.db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM processed_heading_search '
                  "WHERE processed_heading_search MATCH 'roma'",
                )
                .getSingle())
            .read<int>('n'),
        0,
      );
    });

    test(
      'mandarlo a la papelera las conserva: si vuelve, está listo',
      () async {
        final roma = await processed('roma', romaText);
        await h.vault.writer.trash([roma]);

        expect(await entries(h.db, roma), hasLength(3));
      },
    );
  });
}

/// Una entrada como `nivel título`, y «Texto completo» por su nombre.
String _label(QueryRow row) =>
    row.read<String>('origin') == IndexEntryOrigin.wholeText.name
    ? '1 «Texto completo»'
    : '${row.read<int>('level')} ${row.read<String>('title')}';

/// La copia del original de [documentId], escrita como la deja el
/// repositorio: su forma, con el archivo, y su fila.
Future<void> _insertOriginal(
  AppDatabase db,
  String documentId, {
  required String path,
}) async {
  final at = DateTime(2026, 11, 5);
  await db
      .into(db.renditions)
      .insert(
        RenditionsCompanion.insert(
          id: 'original-$documentId',
          itemId: documentId,
          kind: path.endsWith('.pdf')
              ? RenditionKind.pdf
              : RenditionKind.document,
          relativePath: Value(path),
          isPrimary: false,
          sizeBytes: const Value(8),
          createdAt: at,
        ),
      );
  await db
      .into(db.processedOriginals)
      .insert(
        ProcessedOriginalsCompanion.insert(
          documentId: documentId,
          renditionId: 'original-$documentId',
          sourceFilePath: path,
          sourceFileSize: 8,
          copiedAt: at,
        ),
      );
}
