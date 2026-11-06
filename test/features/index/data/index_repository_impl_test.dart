import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/index/data/repositories/index_repository_impl.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';

import '../../../support/processed_rows.dart';
import '../../../support/test_vault.dart';

class _Telemetry extends Mock implements TelemetryService {}

/// Lo que lee la pantalla del Índice (F46, paso 2): el árbol por tema y por
/// documento, las entradas de un documento, la búsqueda con sus padres y cómo
/// va el relleno, en vivo y sin lo de la papelera.
void main() {
  late TestVault vault;
  late IndexRepositoryImpl repository;

  setUp(() async {
    vault = await TestVault.create(deviceId: 'tel');
    repository = IndexRepositoryImpl(
      database: vault.db,
      telemetry: _Telemetry(),
      clock: () => vault.now,
    );
  });
  tearDown(() => vault.dispose());

  AppDatabase db() => vault.db;

  /// Un documento procesado con texto —o sin él, con [text] en `null`— y sus
  /// [chapters] como `(nivel, título)`, en su orden.
  Future<void> document(
    String id,
    String title, {
    String? text = 'Texto.',
    List<(int, String)> chapters = const [],
    Set<String> spaces = const {},
    SourceKind kind = SourceKind.webPage,
    DateTime? createdAt,
  }) async {
    await insertProcessedRows(
      db(),
      id: id,
      title: title,
      sourceKind: kind,
      createdAt: createdAt,
      parts: {
        if (text != null) ProcessedSection.text: [text],
        ProcessedSection.notes: ['Una nota.'],
      },
    );
    for (final (position, (level, chapter)) in chapters.indexed) {
      await db()
          .into(db().processedHeadings)
          .insert(
            ProcessedHeadingsCompanion.insert(
              documentId: id,
              origin: IndexEntryOrigin.textHeading,
              level: level,
              position: position,
              title: chapter,
              textStart: Value(position * 10),
              textEnd: Value(position * 10 + 5),
              textPage: const Value(1),
            ),
          );
    }
    if (spaces.isNotEmpty) await vault.writer.addSpaces([id], spaces);
  }

  Future<void> image(
    String documentId,
    String id, {
    String? title,
    int position = 0,
  }) async {
    await db()
        .into(db().renditions)
        .insert(
          RenditionsCompanion.insert(
            id: id,
            itemId: documentId,
            kind: RenditionKind.image,
            relativePath: Value('originales/$documentId/imagenes/$id.jpg'),
            isPrimary: false,
            createdAt: vault.now,
          ),
        );
    await db()
        .into(db().processedImages)
        .insert(
          ProcessedImagesCompanion.insert(
            renditionId: id,
            documentId: documentId,
            position: position,
            sourceFilePath: 'contenido/$id.jpg',
            sourceFileSize: 1,
            copiedAt: vault.now,
            title: Value(title),
          ),
        );
  }

  Future<void> topic(String id, String name) => vault.addSpace(id, name);

  group('por tema', () {
    test('cada tema con cuántos documentos del Índice tiene, de la A a la Z '
        'sin acentos, y «Sin tema» al final', () async {
      await topic('roma', 'Roma');
      await topic('egipto', 'Égipto');
      await topic('vacio', 'Vacío');
      await document('a', 'Historia de Roma', spaces: {'roma'});
      await document('b', 'Pirámides', spaces: {'egipto'});
      await document('c', 'Cleopatra', spaces: {'egipto', 'roma'});
      await document('d', 'Suelto');

      expect(await repository.watchTopics().first, [
        const IndexTopic(spaceId: 'egipto', name: 'Égipto', documentCount: 2),
        const IndexTopic(spaceId: 'roma', name: 'Roma', documentCount: 2),
        const IndexTopic(spaceId: null, name: '', documentCount: 1),
      ]);
    });

    test('solo cuentan los documentos vivos con texto o con imágenes: ni la '
        'papelera, ni uno de solo notas, ni lo de la Biblioteca', () async {
      await topic('roma', 'Roma');
      await document('vivo', 'Vivo', spaces: {'roma'});
      await document('borrado', 'Borrado', spaces: {'roma'});
      await document('notas', 'Solo notas', text: null, spaces: {'roma'});
      await document('fotos', 'Solo fotos', text: null, spaces: {'roma'});
      await image('fotos', 'f1', title: 'Coliseo');
      await vault.saveSource('fuente', title: 'Fuente', spaceId: 'roma');
      await vault.writer.trash(['borrado']);

      expect(await repository.watchTopics().first, [
        const IndexTopic(spaceId: 'roma', name: 'Roma', documentCount: 2),
      ]);
      expect(
        (await repository.watchDocumentsOf('roma').first).map((d) => d.id),
        ['fotos', 'vivo'],
      );
    });

    test('un documento con varios temas está bajo cada uno, y dice en qué '
        'otros está (decisión D)', () async {
      await topic('roma', 'Roma');
      await topic('egipto', 'Egipto');
      await document('c', 'Cleopatra', spaces: {'egipto', 'roma'});

      final underRoma =
          (await repository.watchDocumentsOf('roma').first).single;
      final underEgypt =
          (await repository.watchDocumentsOf('egipto').first).single;
      expect(underRoma.id, 'c');
      expect(underEgypt.id, 'c');
      expect(underRoma.alsoIn('roma'), ['egipto']);
      expect(underEgypt.alsoIn('egipto'), ['roma']);
    });

    test('«Sin tema»: los que no están en ninguno', () async {
      await topic('roma', 'Roma');
      await document('a', 'Con tema', spaces: {'roma'});
      await document('b', 'Sin tema');

      expect((await repository.watchDocumentsOf(null).first).map((d) => d.id), [
        'b',
      ]);
    });
  });

  group('un documento', () {
    test('su fila: título, tipo, cuándo llegó, cuántos capítulos e imágenes, '
        'si tiene texto y si ya está indexado', () async {
      final at = DateTime(2026, 11, 1, 10);
      await document(
        'libro',
        'Libro',
        chapters: [(1, 'Uno'), (2, 'Uno.1')],
        kind: SourceKind.document,
        createdAt: at,
      );
      await image('libro', 'f1', title: 'Mapa');
      await image('libro', 'f2', position: 1);
      await document('pendiente', 'Pendiente');

      final rows = {
        for (final d
            in await repository.watchDocuments(IndexDocumentOrder.title).first)
          d.id: d,
      };
      expect(
        rows['libro'],
        IndexDocument(
          id: 'libro',
          title: 'Libro',
          sourceKind: SourceKind.document,
          createdAt: at,
          chapterCount: 2,
          imageCount: 1,
          hasText: true,
          indexed: true,
          spaceIds: const [],
        ),
      );
      expect(rows['pendiente']!.indexed, isFalse);
      expect(rows['pendiente']!.chapterCount, 0);
    });

    test('por documento: de la A a la Z sin acentos, o los más recientes '
        'primero', () async {
      await document('z', 'Zama', createdAt: DateTime(2026, 1, 4));
      await document('a', 'Ágora', createdAt: DateTime(2026, 1, 2));
      await document('b', 'Bizancio', createdAt: DateTime(2026, 1, 3));

      expect(
        (await repository.watchDocuments(IndexDocumentOrder.title).first).map(
          (d) => d.title,
        ),
        ['Ágora', 'Bizancio', 'Zama'],
      );
      expect(
        (await repository.watchDocuments(IndexDocumentOrder.recent).first).map(
          (d) => d.title,
        ),
        ['Zama', 'Bizancio', 'Ágora'],
      );
    });

    test('sus entradas: los capítulos en su orden y después las imágenes, '
        'cada una en su lugar de la galería', () async {
      await document('libro', 'Libro', chapters: [(1, 'Uno'), (2, 'Dos')]);
      await image('libro', 'f2', title: 'Segunda', position: 1);
      await image('libro', 'f1', title: 'Primera');

      final entries = await repository.watchEntries('libro').first;
      expect(
        [for (final e in entries) (e.origin, e.level, e.title)],
        [
          (IndexEntryOrigin.textHeading, 1, 'Uno'),
          (IndexEntryOrigin.textHeading, 2, 'Dos'),
          (IndexEntryOrigin.image, 1, 'Primera'),
          (IndexEntryOrigin.image, 1, 'Segunda'),
        ],
      );
      expect(entries.first.textStart, 0);
      expect(entries.first.textPage, 1);
      expect(entries.last.imageId, 'f2');
    });
  });

  group('la búsqueda', () {
    test('sin mayúsculas ni acentos, el comienzo de cada palabra alcanza, y '
        'cada coincidencia con sus capítulos padres', () async {
      await document(
        'concilios',
        'Los concilios',
        chapters: [
          (1, 'Primera parte'),
          (2, 'El Concilio de Nicea'),
          (3, 'Arrio y la herejía'),
          (2, 'Constantinopla'),
          (1, 'Segunda parte'),
          (2, 'Éfeso'),
        ],
      );

      final hits = await repository.watchSearch('herejia').first;
      expect(hits.single.entry.title, 'Arrio y la herejía');
      expect(hits.single.documentTitle, 'Los concilios');
      expect(hits.single.ancestors.map((a) => a.title), [
        'Primera parte',
        'El Concilio de Nicea',
      ]);

      final efeso = await repository.watchSearch('efes').first;
      expect(efeso.single.ancestors.map((a) => a.title), ['Segunda parte']);

      expect(
        (await repository.watchSearch('PARTE').first).map(
          (h) => (h.entry.title, h.ancestors.length),
        ),
        [('Primera parte', 0), ('Segunda parte', 0)],
      );
    });

    test(
      'encuentra las imágenes por su título, y nada de la papelera',
      () async {
        await document('vivo', 'Vivo', chapters: [(1, 'El mapa del Nilo')]);
        await image('vivo', 'f1', title: 'Mapa de Roma');
        await document('borrado', 'Borrado', chapters: [(1, 'Otro mapa')]);
        await vault.writer.trash(['borrado']);

        final hits = await repository.watchSearch('mapa').first;
        expect(hits.map((h) => h.entry.title), [
          'El mapa del Nilo',
          'Mapa de Roma',
        ]);
        expect(hits.last.entry.isImage, isTrue);
        expect(hits.last.ancestors, isEmpty);
      },
    );

    test('con varias palabras, las que tienen todas; en el orden del Índice; '
        'como mucho las que se pidieron', () async {
      await document('b', 'Bizancio', chapters: [(1, 'Roma de Oriente')]);
      await document(
        'a',
        'Ágora',
        chapters: [(1, 'Roma'), (1, 'Oriente y Roma'), (1, 'Oriente')],
      );

      expect(
        (await repository.watchSearch('roma orien').first).map(
          (h) => h.entry.title,
        ),
        ['Oriente y Roma', 'Roma de Oriente'],
      );
      expect(
        await repository.watchSearch('roma', limit: 2).first,
        hasLength(2),
      );
      expect(await repository.watchSearch('   ').first, isEmpty);
      expect(await repository.watchSearch('"').first, isEmpty);
    });
  });

  group('en vivo', () {
    test(
      'lo que llega, se renombra, cambia de tema o se va se ve solo',
      () async {
        await topic('roma', 'Roma');
        await document(
          'a',
          'Historia',
          chapters: [(1, 'Uno')],
          spaces: {'roma'},
        );
        final seen = <List<String>>[];
        final sub = repository
            .watchDocumentsOf('roma')
            .listen((docs) => seen.add([for (final d in docs) d.title]));
        addTearDown(sub.cancel);
        await pumpEventQueue();

        await vault.writer.setFieldFromText(
          'a',
          EntryField.title,
          'Historia de Roma',
        );
        await pumpEventQueue();
        expect(seen.last, ['Historia de Roma']);
        await document('b', 'Anales', spaces: {'roma'});
        await pumpEventQueue();
        expect(seen.last, ['Anales', 'Historia de Roma']);
        await vault.writer.trash(['a']);
        await pumpEventQueue();
        expect(seen.last, ['Anales']);
        expect(seen.first, ['Historia']);
      },
    );

    test('las entradas de un documento cambian cuando se vuelve a indexar o se '
        'renombra una imagen', () async {
      await document('libro', 'Libro', chapters: [(1, 'Uno')]);
      await image('libro', 'f1', title: 'Mapa');
      final seen = <List<String>>[];
      final sub = repository
          .watchEntries('libro')
          .listen((entries) => seen.add([for (final e in entries) e.title]));
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await repository.renameImage('f1', 'El mapa');
      await pumpEventQueue();
      expect(seen.last, ['Uno', 'El mapa']);
      await db().customStatement(
        "UPDATE processed_parts SET content = 'Otro.' "
        "WHERE document_id = 'libro' AND section = 'text'",
      );
      db().markTablesUpdated([db().processedParts]);
      await pumpEventQueue();
      expect(seen.last, ['El mapa']);
      expect(seen.first, ['Uno', 'Mapa']);
    });
  });

  group('cómo va el relleno', () {
    test('los documentos vivos con texto, cuántos están indexados y cuántas '
        'imágenes falta titular', () async {
      await document('listo', 'Listo', chapters: [(1, 'Uno')]);
      await document('pendiente', 'Pendiente');
      await document('borrado', 'Borrado');
      await document('fotos', 'Fotos', text: null);
      await image('fotos', 'f1');
      await image('fotos', 'f2', title: '', position: 1);
      await vault.writer.trash(['borrado']);

      final progress = await repository.watchProgress().first;
      expect(
        progress,
        const IndexProgress(
          documents: 2,
          indexedDocuments: 1,
          untitledImages: 1,
        ),
      );
      expect(progress.isComplete, isFalse);
    });
  });

  group('renombrar una imagen', () {
    test(
      'le cambia el título y su entrada; uno en blanco no se guarda',
      () async {
        await document('libro', 'Libro', text: null);
        await image('libro', 'f1', title: 'Mapa');

        expect(
          (await repository.renameImage('f1', '  Mapa  de\nRoma ')).isRight(),
          isTrue,
        );
        expect(
          (await db().select(db().processedImages).getSingle()).title,
          'Mapa de Roma',
        );
        expect(
          (await db().select(db().processedHeadings).getSingle()).title,
          'Mapa de Roma',
        );

        expect((await repository.renameImage('f1', '   ')).isLeft(), isTrue);
        expect((await repository.renameImage('otra', 'X')).isLeft(), isTrue);
        expect(
          (await db().select(db().processedImages).getSingle()).title,
          'Mapa de Roma',
        );
      },
    );

    test('es tocar el documento: sube su última modificación', () async {
      await document('libro', 'Libro', text: null);
      await image('libro', 'f1', title: 'Mapa');
      final before = (await vault.entry('libro')).updatedAt;
      vault.at(30);

      await repository.renameImage('f1', 'Otro');

      expect((await vault.entry('libro')).updatedAt, isNot(before));
    });
  });
}
