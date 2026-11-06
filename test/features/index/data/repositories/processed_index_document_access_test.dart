import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/index/data/repositories/processed_index_document_access.dart';
import 'package:sinapsis/features/index/domain/repositories/index_document_access.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_study_text.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_study_layout.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/domain/services/file_viewer_resolver.dart';

import '../../../../support/sample_knowledge_item.dart';

/// Lo que el Índice sabe de un documento procesado para «Abrir en el
/// original» (F46, pasos 4 y 5c): su copia del original y, sin ella, su fuente
/// en la Biblioteca con el original que su visor sabe abrir.
void main() {
  late _Processed processed;
  late _Library library;
  late _Viewers viewers;
  late ProcessedIndexDocumentAccess access;

  setUp(() {
    processed = _Processed();
    library = _Library();
    viewers = _Viewers();
    access = ProcessedIndexDocumentAccess(
      processed,
      library: library,
      viewers: viewers,
    );
  });

  const study = (
    itemId: 'fuente',
    renditionId: 'r',
    content: 'Texto.',
    markdown: true,
  );

  test('un documento que ya no está: nada', () async {
    expect(await access.factsOf('doc'), isNull);
  });

  test('con su copia del original: qué es; sin fuente, ninguna', () async {
    processed
      ..document = _document()
      ..original = RenditionKind.pdf;
    final facts = await access.factsOf('doc');
    expect(facts?.title, 'Fotosíntesis');
    expect(facts?.original, IndexOriginalKind.pdf);
    expect(facts?.source, isNull);
  });

  group('la fuente en la Biblioteca', () {
    for (final (viewer, kind) in <(ResolvedViewer, IndexOriginalKind?)>[
      (const PdfResolvedViewer('/a.pdf'), IndexOriginalKind.pdf),
      (const WebPageResolvedViewer('/a.html'), IndexOriginalKind.webPage),
      (
        const TextResolvedViewer('Texto.', study: study),
        IndexOriginalKind.other,
      ),
      (const TextResolvedViewer('Texto.'), null),
      (const MediaResolvedViewer(path: '/a.mp3', isVideo: false), null),
      (const NoResolvedViewer(), null),
    ]) {
      test('${viewer.runtimeType}: ${kind?.name ?? 'su ficha'}', () async {
        processed.document = _document(source: _link());
        library.item = _item();
        viewers.resolved = viewer;

        final facts = await access.factsOf('doc');
        expect(facts?.original, isNull);
        expect(facts?.source, (
          itemId: 'fuente',
          original: kind,
          inTrash: false,
        ));
        expect(viewers.asked, ['fuente']);
      });
    }

    test('en la papelera: se dice, sin mirar su visor', () async {
      processed.document = _document(source: _link(inTrash: true));
      library.item = _item();

      final facts = await access.factsOf('doc');
      expect(facts?.source, (itemId: 'fuente', original: null, inTrash: true));
      expect(viewers.asked, isEmpty);
    });

    test('un elemento que ya no está en la Biblioteca: sin fuente', () async {
      processed.document = _document(source: _link());

      final facts = await access.factsOf('doc');
      expect(facts?.source, isNull);
    });
  });

  group('su texto (F46, paso 5e)', () {
    test('con si es Markdown, como el de su fuente: el pasaje para el chat se '
        'lee como se lee el texto', () async {
      processed.text = const ProcessedStudyText(
        key: 'k',
        documentId: 'doc',
        content: '## Siglo XX',
        markdown: true,
        layout: ProcessedStudyLayout.source('r'),
      );
      expect(await access.textOf('doc'), (
        content: '## Siglo XX',
        markdown: true,
      ));

      processed.text = const ProcessedStudyText(
        key: 'k',
        documentId: 'doc',
        content: 'Un PDF.',
        markdown: false,
        layout: ProcessedStudyLayout.source('r'),
      );
      expect(await access.textOf('doc'), (content: 'Un PDF.', markdown: false));
    });

    test('sin texto, o si no se pudo leer, nada', () async {
      expect(await access.textOf('doc'), isNull);
      processed.failText = true;
      expect(await access.textOf('doc'), isNull);
    });
  });
}

ProcessedSourceLink _link({bool inTrash = false}) => ProcessedSourceLink(
  itemId: 'fuente',
  title: 'Fotosíntesis',
  inTrash: inTrash,
);

ProcessedDocument _document({ProcessedSourceLink? source}) => ProcessedDocument(
  summary: ProcessedDocumentSummary(
    id: 'doc',
    title: 'Fotosíntesis',
    sourceKind: SourceKind.webPage,
    createdAt: DateTime(2026, 11, 6),
    updatedAt: DateTime(2026, 11, 6),
    rev: 1,
    partCounts: const {},
    sourceItemId: source?.itemId,
  ),
  stats: const {},
  inTrash: false,
  source: source,
);

KnowledgeItem _item() {
  final item = sampleKnowledgeItem(title: 'Fotosíntesis');
  return item.copyWith(id: 'fuente');
}

class _Processed extends Fake implements ProcessedRepository {
  ProcessedDocument? document;
  RenditionKind? original;
  ProcessedStudyText? text;
  bool failText = false;

  @override
  Future<Either<Failure, ProcessedStudyText?>> studyTextOf(
    String documentId,
  ) async => failText
      ? left(const Failure.unexpected(message: 'no se pudo'))
      : right(text);

  @override
  Stream<ProcessedDocument?> watchDocument(String documentId) =>
      Stream.value(document);

  @override
  Stream<ProcessedOriginal?> watchOriginal(String documentId) => Stream.value(
    original == null
        ? null
        : ProcessedOriginal(
            documentId: documentId,
            renditionId: 'copia',
            relativePath: 'doc/original',
            kind: original!,
            sizeBytes: 1,
            copiedAt: DateTime(2026, 11, 6),
            sourceFilePath: 'fuente/original',
          ),
  );
}

class _Library extends Fake implements LibraryRepository {
  KnowledgeItem? item;

  @override
  Stream<KnowledgeItem?> watchById(String id) =>
      Stream.value(item?.id == id ? item : null);
}

class _Viewers extends Fake implements FileViewerResolver {
  ResolvedViewer resolved = const NoResolvedViewer();
  final asked = <String>[];

  @override
  Future<ResolvedViewer> resolve(KnowledgeItem item) async {
    asked.add(item.id);
    return resolved;
  }
}
