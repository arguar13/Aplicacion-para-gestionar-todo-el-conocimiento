import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/usecases/drop_original_copy.dart';

import '../../processed_harness.dart';

/// «Borrar la copia del original, quedarme con el texto» (F41, decisión K):
/// la copia va a la papelera del contenido, el texto se queda y la fuente no
/// se toca.
void main() {
  const text = 'El Senado de Roma. Cartago debe ser destruida. Fin.';
  const sourcePath = 'originales/libro/libro.pdf';
  late ProcessedHarness h;
  late DropOriginalCopy drop;
  final docId = processedDocumentIdFor('libro');

  setUp(() async {
    h = await ProcessedHarness.create();
    drop = DropOriginalCopy(repository: h.repository, process: h.process);
    await h.vault.writeOriginal(sourcePath, '%PDF-1.4 un pdf de prueba');
    final at = h.vault.now;
    await h.vault.library.save(
      KnowledgeItem(
        id: 'libro',
        title: 'El libro',
        source: Source(
          id: 'libro',
          kind: SourceKind.document,
          capturedAt: at,
          originalFilePath: sourcePath,
        ),
        processingState: ProcessingState.ready,
        createdAt: at,
        updatedAt: at,
        renditions: [
          Rendition.text(
            id: 'rend-libro',
            itemId: 'libro',
            kind: RenditionKind.plainText,
            content: text,
            isPrimary: true,
            createdAt: at,
          ),
        ],
      ),
    );
  });
  tearDown(() => h.close());

  Future<void> process({bool withText = false}) async {
    final result = await h.process('libro', {
      if (withText)
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
    }, original: const OriginalEdit(ProcessedChange.add));
    result.getOrElse((failure) => throw StateError('$failure'));
  }

  Future<ProcessedOriginal?> original() async =>
      (await h.repository.originalOf(docId)).getRight().toNullable();

  Future<List<String>> textPages() async => [
    for (final part in (await h.repository.partsOf(
      docId,
      sections: const {ProcessedSection.text},
    )).getRight().toNullable()!)
      part.content,
  ];

  File fileOf(String relativePath) =>
      File(p.join(h.vault.docs.path, p.joinAll(p.posix.split(relativePath))));

  test('con la copia como único texto, el texto entra como su sección Texto '
      'en el mismo guardado: el documento no queda mudo', () async {
    await process();
    final copyPath = (await original())!.relativePath;
    expect(await textPages(), isEmpty);

    final dropped = (await drop('libro')).getRight().toNullable()!;

    expect(dropped.keptText, isTrue);
    expect(await original(), isNull);
    expect((await textPages()).join(), text);
    // Se sigue estudiando: ahora sobre sus páginas.
    final own = (await h.repository.studyTextOf(
      docId,
    )).getRight().toNullable()!;
    expect(own.content, text);
    expect(own.layout.hasPages, isTrue);
    // La copia va a la papelera del contenido, de donde se recupera; el
    // archivo no se borra todavía.
    final trashed = await h.db.select(h.db.trashedContents).get();
    expect(trashed.single.itemId, docId);
    expect(trashed.single.kind, TrashedContentKind.file);
    expect(fileOf(copyPath).existsSync(), isTrue);
  });

  test(
    'la fuente no se toca: su archivo y su texto siguen en la Biblioteca',
    () async {
      await process();

      await drop('libro');

      final source = await (h.db.select(
        h.db.knowledgeSources,
      )..where((s) => s.itemId.equals('libro'))).getSingle();
      expect(source.originalBlobPath, sourcePath);
      expect(fileOf(sourcePath).existsSync(), isTrue);
      final renditions = await (h.db.select(
        h.db.renditions,
      )..where((r) => r.itemId.equals('libro'))).get();
      expect(renditions.single.content, text);
    },
  );

  test('«Deshacer» devuelve la copia y saca el texto que entró', () async {
    await process();
    final copy = (await original())!;
    final dropped = (await drop('libro')).getRight().toNullable()!;

    final undone = await h.process.undo(dropped.outcome.undo);

    expect(undone.isRight(), isTrue);
    expect((await original())?.relativePath, copy.relativePath);
    expect(await textPages(), isEmpty);
  });

  test('con su sección Texto, solo suelta la copia', () async {
    await process(withText: true);
    final before = await textPages();

    final dropped = (await drop('libro')).getRight().toNullable()!;

    expect(dropped.keptText, isFalse);
    expect(await original(), isNull);
    expect(await textPages(), before);
  });

  test('sin copia, no hay qué soltar: falla sin tocar nada', () async {
    await h.process('libro', {
      ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
    });

    final result = await drop('libro');

    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    expect(await h.db.select(h.db.trashedContents).get(), isEmpty);
  });
}
