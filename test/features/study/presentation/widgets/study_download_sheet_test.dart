import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_format.dart';
import 'package:sinapsis/features/export/domain/services/marked_document_writer.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/export/presentation/providers/marked_download_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_download_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../support/fake_file_saver.dart';
import '../../../../support/fake_marked_document_writer.dart';
import '../../../../support/fake_study_analysis.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/memory_study_repository.dart';
import '../../../../support/read_aloud_test_support.dart';
import '../../../../support/sample_files.dart';
import '../../../../support/sample_knowledge_item.dart';

/// Un escritor que no termina hasta que la prueba lo suelte: para ver la
/// barra mientras arma el archivo.
class _GatedWriter implements MarkedDocumentWriter {
  final gate = Completer<void>();

  @override
  Future<Uint8List> write(
    Uint8List original, {
    required String content,
    required List<DocumentMark> marks,
  }) async {
    await gate.future;
    return FakeMarkedDocumentWriter.outputFor(marks.length);
  }
}

void main() {
  const content =
      'La revolución industrial cambió todo. Nada más.\n\n'
      'Las fábricas usaban vapor.';
  const text = (
    itemId: 'i1',
    renditionId: 'r1',
    content: content,
    markdown: true,
  );
  const summarySentence = 'La revolución industrial cambió todo.';

  StudyMark mark(String id, StudyMarkKind kind, String part) {
    final start = content.indexOf(part);
    return StudyMark(
      id: id,
      kind: kind,
      origin: ContentOrigin.ai,
      start: start,
      end: start + part.length,
    );
  }

  final analyzed = DocumentStudy(
    marks: [
      mark('s1', StudyMarkKind.summary, summarySentence),
      mark('k1', StudyMarkKind.keyword, 'revolución'),
      mark('y1', StudyMarkKind.synthesis, 'Las fábricas usaban vapor.'),
    ]..sort((a, b) => a.start.compareTo(b.start)),
    analyzedUntil: content.length,
    complete: true,
  );

  final mine = Highlight(
    id: 'h1',
    renditionId: 'r1',
    startOffset: content.indexOf('Nada más.'),
    endOffset: content.indexOf('Nada más.') + 'Nada más.'.length,
    excerpt: 'Nada más.',
    createdAt: DateTime(2026, 10, 22),
  );

  late InMemoryFileStore files;
  late FakeFileSaver saver;
  late FakeMarkedDocumentWriter writer;
  late KnowledgeItem item;
  late ProviderContainer container;
  late MemoryStudyRepository repository;

  setUp(() async {
    files = InMemoryFileStore();
    saver = FakeFileSaver();
    writer = FakeMarkedDocumentWriter();
    final path = await files.save(
      bytes: buildPdf(),
      suggestedName: 'historia.pdf',
      id: 'item-1',
    );
    final base = sampleKnowledgeItem(title: 'Historia');
    item = base.copyWith(
      source: base.source.copyWith(
        kind: SourceKind.document,
        originalFilePath: path,
      ),
    );
  });

  /// Monta [child] con todo de mentira.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    DocumentStudy study = DocumentStudy.notStarted,
    List<Highlight> highlights = const [],
    Map<MarkedDocumentFormat, MarkedDocumentWriter>? writers,
    StudyView? view,
  }) async {
    repository = MemoryStudyRepository(study);
    container = ProviderContainer(
      overrides: [
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
        studyRepositoryProvider.overrideWithValue(repository),
        studyAnalysisProvider.overrideWith((ref, id) => FakeStudyAnalysis()),
        renditionHighlightsProvider.overrideWith(
          (ref, id) => Stream.value(highlights),
        ),
        fileStoreProvider.overrideWithValue(files),
        fileSaverProvider.overrideWithValue(saver),
        if (view != null) studyViewProvider.overrideWith((ref, id) => view),
        markedDocumentWritersProvider.overrideWithValue(
          writers ?? {MarkedDocumentFormat.pdf: writer},
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget sheet() => StudyDownloadSheet(
    item: item,
    text: text,
    format: MarkedDocumentFormat.pdf,
  );

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<CheckboxListTile>(find.byKey(Key(key))).onChanged != null;

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const Key('study-download-save')))
          .onPressed !=
      null;

  group('la hoja', () {
    testWidgets('al abrirse completa las palabras clave de las oraciones que '
        'quedaron sin ninguna, para que lo que se lleva las tenga en todas', (
      tester,
    ) async {
      await pump(tester, sheet(), study: analyzed);

      // «Nada más.» y «Las fábricas usaban vapor.» no tenían ninguna.
      expect(repository.filled, isNotEmpty);
      expect(
        repository.filled.any((w) => 'Nada más.'.contains(w)),
        isTrue,
        reason: '${repository.filled}',
      );
    });

    testWidgets('dice el formato y ofrece las cuatro cosas, todas prendibles '
        'si hay de todo', (tester) async {
      await pump(tester, sheet(), study: analyzed, highlights: [mine]);

      expect(find.textContaining('(PDF)'), findsOneWidget);
      for (final key in [
        'study-download-summary',
        'study-download-synthesis',
        'study-download-keywords',
        'study-download-mine',
      ]) {
        expect(enabled(tester, key), isTrue, reason: key);
      }
      // Nada elegido: no hay qué guardar.
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('sin resumen, sin palabras clave ni subrayados, las opciones '
        'están apagadas y dicen por qué', (tester) async {
      await pump(tester, sheet());

      for (final key in [
        'study-download-summary',
        'study-download-synthesis',
        'study-download-keywords',
        'study-download-mine',
      ]) {
        expect(enabled(tester, key), isFalse, reason: key);
      }
      expect(find.textContaining('Todavía no hay resumen'), findsOneWidget);
      expect(find.textContaining('Todavía no subrayaste'), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('solo se apaga lo que no tiene datos', (tester) async {
      await pump(
        tester,
        sheet(),
        study: DocumentStudy(
          marks: [mark('s1', StudyMarkKind.summary, summarySentence)],
          analyzedUntil: content.length,
          complete: true,
        ),
        highlights: [mine],
      );

      expect(enabled(tester, 'study-download-summary'), isTrue);
      expect(enabled(tester, 'study-download-synthesis'), isFalse);
      expect(enabled(tester, 'study-download-keywords'), isFalse);
      expect(enabled(tester, 'study-download-mine'), isTrue);
    });

    testWidgets('arranca con lo que ya se ve resaltado en el original', (
      tester,
    ) async {
      await pump(
        tester,
        sheet(),
        study: analyzed,
        view: const StudyView(synthesis: true, keywords: true),
      );

      bool checked(String key) =>
          tester.widget<CheckboxListTile>(find.byKey(Key(key))).value!;
      expect(checked('study-download-synthesis'), isTrue);
      expect(checked('study-download-keywords'), isTrue);
      expect(checked('study-download-summary'), isFalse);
      expect(checked('study-download-mine'), isFalse);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('lo que se ve resaltado pero no tiene datos no se prende', (
      tester,
    ) async {
      await pump(tester, sheet(), view: const StudyView(summary: true));

      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('study-download-summary')),
            )
            .value,
        isFalse,
      );
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('guardar entrega al escritor lo elegido y lo guarda con el '
        'nombre del original', (tester) async {
      await pump(tester, sheet(), study: analyzed, highlights: [mine]);

      await tap(tester, 'study-download-summary');
      await tap(tester, 'study-download-mine');
      expect(saveEnabled(tester), isTrue);
      await tap(tester, 'study-download-save');

      expect(saver.savedFileName, 'Historia — resumen y mis resaltados.pdf');
      expect(writer.lastMarks, hasLength(2));
      expect(saver.savedBytes, FakeMarkedDocumentWriter.outputFor(2));
      expect(find.byKey(const Key('study-download-result')), findsOneWidget);
      expect(
        find.text('Guardado: Historia — resumen y mis resaltados.pdf'),
        findsOneWidget,
      );
    });

    testWidgets('cerrar el selector sin guardar dice que se canceló', (
      tester,
    ) async {
      saver = FakeFileSaver(path: null);
      await pump(tester, sheet(), study: analyzed);

      await tap(tester, 'study-download-summary');
      await tap(tester, 'study-download-save');

      expect(find.text('Cancelaste el guardado.'), findsOneWidget);
    });

    testWidgets('si el escritor falla, lo dice con un mensaje claro', (
      tester,
    ) async {
      writer.error = const FormatException('zip roto');
      await pump(tester, sheet(), study: analyzed);

      await tap(tester, 'study-download-summary');
      await tap(tester, 'study-download-save');

      expect(
        find.textContaining('No se pudo marcar este archivo'),
        findsOneWidget,
      );
      expect(saver.savedBytes, isNull);
    });

    testWidgets('si el selector se cae, lo dice', (tester) async {
      saver.error = StateError('sin diálogo');
      await pump(tester, sheet(), study: analyzed);

      await tap(tester, 'study-download-summary');
      await tap(tester, 'study-download-save');

      expect(
        find.textContaining('No se pudo guardar el archivo'),
        findsOneWidget,
      );
    });

    testWidgets('mientras arma el archivo muestra la barra y no deja volver '
        'a guardar ni cambiar lo elegido', (tester) async {
      final gated = _GatedWriter();
      await pump(
        tester,
        sheet(),
        study: analyzed,
        writers: {MarkedDocumentFormat.pdf: gated},
      );

      await tap(tester, 'study-download-summary');
      await tester.tap(find.byKey(const Key('study-download-save')));
      await tester.pump();

      expect(find.byKey(const Key('study-download-progress')), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      expect(enabled(tester, 'study-download-summary'), isFalse);

      gated.gate.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('study-download-progress')), findsNothing);
      expect(saver.savedFileName, 'Historia — resumen.pdf');
    });
  });
}
