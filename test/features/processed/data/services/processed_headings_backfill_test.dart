import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/processed/data/services/processed_headings_backfill.dart';
import 'package:sinapsis/features/processed/data/services/processed_headings_backfill_keeper.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';

import '../../../../support/index_fakes.dart';
import '../../../../support/processed_rows.dart';
import '../../processed_harness.dart';

class _Telemetry extends Mock implements TelemetryService {}

/// El relleno del Índice (F46, paso 2, decisión F): lo que ya estaba
/// procesado se indexa por tandas, con el punto de retome en la base misma;
/// es idempotente, se puede borrar y rehacer entero, y de la Biblioteca no
/// toca nada.
void main() {
  late ProcessedHarness h;
  late FakeHeadingsExtractor extractor;
  late FakePdfOutlineReader outlines;

  setUp(() async {
    extractor = FakeHeadingsExtractor();
    outlines = FakePdfOutlineReader();
    h = await ProcessedHarness.create(headings: extractor, outlines: outlines);
  });
  tearDown(() => h.close());

  ProcessedHeadingsBackfill backfill({int documentsPerRead = 2}) =>
      ProcessedHeadingsBackfill(
        database: h.db,
        indexer: h.indexer!,
        documentsPerRead: documentsPerRead,
        imagesPerBatch: 2,
      );

  /// Un documento como lo deja una base de antes de v51: con texto y sin
  /// entradas.
  Future<void> document(String id, String text, {DateTime? createdAt}) =>
      insertProcessedRows(
        h.db,
        id: id,
        title: 'Documento $id',
        createdAt: createdAt,
        parts: {
          ProcessedSection.text: [text],
        },
      );

  /// Una imagen sin titular, como las de antes de v51: con el nombre con que
  /// la ofrecía la fuente ([alt]) en su forma.
  Future<void> image(
    String documentId,
    String id, {
    required String file,
    String? alt,
    String? title,
  }) async {
    await h.db
        .into(h.db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: id,
            itemId: documentId,
            kind: RenditionKind.image,
            relativePath: Value('originales/$documentId/imagenes/$id.jpg'),
            isPrimary: false,
            title: Value(alt),
            createdAt: h.vault.now,
          ),
        );
    await h.db
        .into(h.db.processedImages)
        .insert(
          ProcessedImagesCompanion.insert(
            renditionId: id,
            documentId: documentId,
            position: 0,
            sourceFilePath: file,
            sourceFileSize: 1,
            copiedAt: h.vault.now,
            title: Value(title),
          ),
        );
  }

  Future<Map<String, int>> textEntries() async => {
    for (final row
        in await h.db
            .customSelect(
              'SELECT document_id, COUNT(*) AS n FROM processed_headings '
              "WHERE origin <> 'image' GROUP BY document_id",
            )
            .get())
      row.read<String>('document_id'): row.read<int>('n'),
  };

  Future<Map<String, String?>> imageTitles() async => {
    for (final row in await h.db.select(h.db.processedImages).get())
      row.renditionId: row.title,
  };

  test('indexa lo que estaba sin indexar y titula las imágenes: lo que dice '
      'la fuente, o el nombre del archivo limpio, o nada', () async {
    await document('a', '# Uno\n## Dos');
    await document('b', 'Sin títulos.');
    await insertProcessedRows(h.db, id: 'fotos', title: 'Fotos');
    await image('fotos', 'alt', file: 'contenido/x.jpg', alt: 'Mapa de Roma');
    await image(
      'fotos',
      'archivo',
      file: 'contenido/mapa_imperio-romano_02.jpg',
    );
    await image('fotos', 'nada', file: 'contenido/IMG_20231014_101530.jpg');

    final report = await backfill().run();

    expect(report.documentsIndexed, 2);
    expect(report.imagesTitled, 3);
    expect(await textEntries(), {'a': 2, 'b': 1});
    expect(await imageTitles(), {
      'alt': 'Mapa de Roma',
      'archivo': 'Mapa imperio romano',
      'nada': '',
    });
    // Cada imagen titulada —también la que no dice nada— tiene su entrada.
    expect(
      await (h.db.select(
        h.db.processedHeadings,
      )..where((e) => e.origin.equalsValue(IndexEntryOrigin.image))).get(),
      hasLength(3),
    );
    expect(await backfill().hasPendingWork(), isFalse);
  });

  test('es idempotente: la segunda pasada no hace nada', () async {
    await document('a', '# Uno');
    final first = backfill();
    await first.run();

    final again = await backfill().run();

    expect(
      (again.documentsIndexed, again.documentsSkipped, again.imagesTitled),
      (0, 0, 0),
    );
    expect(extractor.calls, hasLength(1));
  });

  test('se retoma desde donde quedó: lo hecho no se vuelve a hacer', () async {
    for (final id in ['a', 'b', 'c', 'd']) {
      await document(id, '# $id');
    }
    // La app se cierra después del segundo.
    await backfill(
      documentsPerRead: 1,
    ).run(shouldStop: () => extractor.calls.length >= 2);
    expect(await textEntries(), hasLength(2));

    extractor.calls.clear();
    await backfill().run();

    expect((await textEntries()).keys.toSet(), {'a', 'b', 'c', 'd'});
    expect(extractor.calls, hasLength(2));
  });

  test('los vivos y los más recientes primero; los de la papelera también, '
      'para que vuelvan listos', () async {
    await document('viejo', '# v', createdAt: DateTime(2026, 2, 3));
    await document('nuevo', '# n', createdAt: DateTime(2026, 3, 4));
    await document('borrado', '# b', createdAt: DateTime(2026, 5, 6));
    await h.vault.writer.trash(['borrado']);
    final order = <String>[];
    extractor.during = (source) async => order.add(source.pages.single);

    await backfill(documentsPerRead: 1).run();

    expect(order, ['# n', '# v', '# b']);
  });

  test('uno que falla se saltea en este relleno, sin vueltas sin fin; el '
      'siguiente lo vuelve a intentar', () async {
    await document('a', '# Uno');
    extractor.failWith = Exception('no');
    final first = backfill();

    final report = await first.run();
    expect(report.documentsSkipped, 1);
    expect(await first.hasPendingWork(), isFalse);
    expect(await first.run(), isA<HeadingsBackfillReport>());
    expect(extractor.calls, hasLength(1));

    extractor.failWith = null;
    expect((await backfill().run()).documentsIndexed, 1);
  });

  test(
    'una imagen ya titulada —renombrada mientras tanto— no se pisa',
    () async {
      await insertProcessedRows(h.db, id: 'fotos', title: 'Fotos');
      await image('fotos', 'mia', file: 'contenido/x.jpg', title: 'La mía');

      expect((await backfill().run()).imagesTitled, 0);
      expect(await imageTitles(), {'mia': 'La mía'});
    },
  );

  test(
    'un PDF: sus marcadores se leen antes, afuera de la transacción',
    () async {
      outlines.outlines['libro.pdf'] = PdfOutline(
        pageCount: 10,
        bookmarks: const [PdfBookmark(title: 'Prólogo', depth: 1, page: 2)],
      );
      await document('libro', 'Texto del libro.');
      await h.vault.writeOriginal('originales/libro/libro.pdf', '%PDF');
      await h.db
          .into(h.db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'copia',
              itemId: 'libro',
              kind: RenditionKind.pdf,
              relativePath: const Value('originales/libro/libro.pdf'),
              isPrimary: false,
              createdAt: h.vault.now,
            ),
          );
      await h.db
          .into(h.db.processedOriginals)
          .insert(
            ProcessedOriginalsCompanion.insert(
              documentId: 'libro',
              renditionId: 'copia',
              sourceFilePath: 'originales/libro/libro.pdf',
              sourceFileSize: 4,
              copiedAt: h.vault.now,
            ),
          );

      await backfill().run();

      final entry = await h.db.select(h.db.processedHeadings).getSingle();
      expect(
        (entry.origin, entry.title, entry.pdfPage),
        (IndexEntryOrigin.bookmark, 'Prólogo', 2),
      );
    },
  );

  test('se puede borrar y rehacer entero, y queda igual', () async {
    await document('a', '# Uno\n## Dos');
    await insertProcessedRows(h.db, id: 'fotos', title: 'Fotos');
    await image('fotos', 'f', file: 'contenido/mapa.jpg');
    final relleno = backfill();
    await relleno.run();
    List<Object?> rows(List<ProcessedHeadingRow> all) => [
      for (final r in all)
        (r.documentId, r.origin, r.level, r.position, r.title, r.imageId),
    ];
    final before = rows(await h.db.select(h.db.processedHeadings).get());

    await relleno.rebuildAll();
    expect(await textEntries(), isEmpty);
    expect(await relleno.hasPendingWork(), isTrue);
    await relleno.run();

    expect(rows(await h.db.select(h.db.processedHeadings).get()), before);
    final found = await h.db
        .customSelect(
          'SELECT COUNT(*) AS n FROM processed_heading_search '
          "WHERE processed_heading_search MATCH 'dos OR mapa'",
        )
        .getSingle();
    expect(found.read<int>('n'), 2);
  });

  test('de la Biblioteca no toca nada', () async {
    await h.vault.saveSource('fuente', text: '# Fuente');
    final source = await h.sourceSnapshot('fuente');
    await insertProcessedRows(
      h.db,
      id: 'doc',
      title: 'Doc',
      sourceItemId: 'fuente',
      parts: {
        ProcessedSection.text: ['# Uno'],
      },
    );

    await backfill().run();

    expect(await h.sourceSnapshot('fuente'), source);
  });

  group('quien lo hace correr', () {
    test('al empezar hace lo que quedó, y después lo que llega sin que nadie '
        'lo indexe —una unión de bóvedas—', () async {
      await document('a', '# Uno');
      final keeper = ProcessedHeadingsBackfillKeeper(
        database: h.db,
        backfill: backfill(),
        telemetry: _Telemetry(),
      )..start();
      addTearDown(keeper.stop);
      await pumpEventQueue();
      await keeper.current;
      expect(await textEntries(), {'a': 1});

      // Lo que escribe la unión, con SQL crudo, avisando las tablas.
      await document('b', '# Dos');
      await pumpEventQueue();
      await keeper.current;
      await pumpEventQueue();

      expect(await textEntries(), {'a': 1, 'b': 1});
    });

    test('lo que llega cuando la pasada ya miró por última vez, y antes de '
        'que termine, también se hace', () async {
      await document('a', '# Uno');
      late _LateArrival late;
      late = _LateArrival(
        database: h.db,
        indexer: h.indexer!,
        arrive: () async {
          await document('tarde', '# Tarde');
          // El aviso de la base llega mientras la pasada todavía corre.
          await pumpEventQueue();
        },
      );
      final keeper = ProcessedHeadingsBackfillKeeper(
        database: h.db,
        backfill: late,
        telemetry: _Telemetry(),
      )..start();
      addTearDown(keeper.stop);
      await pumpEventQueue();
      while (keeper.current != null) {
        await keeper.current;
        await pumpEventQueue();
      }

      expect(late.runs, greaterThanOrEqualTo(2));
      expect(await textEntries(), {'a': 1, 'tarde': 1});
    });

    test('al pararlo, deja de mirar', () async {
      final keeper = ProcessedHeadingsBackfillKeeper(
        database: h.db,
        backfill: backfill(),
        telemetry: _Telemetry(),
      )..start();
      await keeper.stop();

      await document('a', '# Uno');
      await pumpEventQueue();

      expect(await textEntries(), isEmpty);
    });
  });
}

/// Un relleno al que le llega algo justo después de su última mirada: la
/// primera pasada termina sin verlo, como si hubiera llegado en ese instante.
class _LateArrival extends ProcessedHeadingsBackfill {
  _LateArrival({
    required super.database,
    required super.indexer,
    required this.arrive,
  });

  final Future<void> Function() arrive;
  int runs = 0;

  @override
  Future<HeadingsBackfillReport> run({bool Function()? shouldStop}) async {
    runs++;
    final report = await super.run(shouldStop: shouldStop);
    if (runs == 1) await arrive();
    return report;
  }
}
