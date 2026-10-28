import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/usecases/capture_item_usecase.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_triage.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_triage_providers.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_highlight_toolbar.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_selection.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/read_aloud_test_support.dart';

class _MockOrganizeRepository extends Mock implements OrganizeRepository {}

class _MockCaptureItemUseCase extends Mock implements CaptureItemUseCase {}

class _RecordingReadAloud extends FakeReadAloudController {
  ReadableDocument? opened;

  @override
  Future<void> open(
    ReadableDocument document, {
    int? fromSegment,
    ReadScope? scope,
  }) async {
    opened = document;
  }
}

typedef _Asked = ({HighlightColor? color, HighlightStyle style, String? note});

/// Lo seleccionado sobre un documento real, como lo da un visor: lo que se
/// pidió resaltar y cuántas veces se quitó la selección.
class _FakeSelection implements DocumentSelection {
  _FakeSelection(this.location);

  SelectionLocation location;
  HighlightOutcome outcome = const HighlightOutcome.created([]);
  final asked = <_Asked>[];
  int clears = 0;

  @override
  Future<String> text() async => 'Las fábricas';

  @override
  Future<SelectionLocation> locate() async => location;

  @override
  Future<HighlightOutcome> highlight({
    HighlightColor? color,
    HighlightStyle style = HighlightStyle.fill,
    String? note,
  }) async {
    asked.add((color: color, style: style, note: note));
    return outcome;
  }

  @override
  Future<void> clear() async => clears++;
}

/// La barrita de resaltado sobre el PDF real y la página web (F38): la misma
/// de «Texto extraído», con cada botón llevado a lo que el visor seleccionó.
void main() {
  final es = AppLocalizationsEs();
  const content =
      'La revolución industrial cambió todo. Las fábricas usaban '
      'vapor.';
  const text = (
    itemId: 'item-1',
    renditionId: 'r1',
    content: content,
    markdown: false,
  );

  late _FakeSelection selection;
  late _MockOrganizeRepository repository;
  late _MockCaptureItemUseCase capture;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(RelationKind.relatedTo);
    registerFallbackValue(const CaptureRequest.text(rawInput: ''));
  });

  setUp(() {
    selection = _FakeSelection(
      const SelectionLocation.found([(start: 38, end: 50)]),
    );
    repository = _MockOrganizeRepository();
    capture = _MockCaptureItemUseCase();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool canCopy = true,
    HighlightColor? lastColor,
    bool cutting = false,
  }) async {
    container = ProviderContainer(
      overrides: [
        readAloudControllerProvider.overrideWith(_RecordingReadAloud.new),
        organizeRepositoryProvider.overrideWithValue(repository),
        captureItemUseCaseProvider.overrideWithValue(capture),
      ],
    );
    addTearDown(container.dispose);
    if (lastColor != null) {
      container.read(lastHighlightColorProvider.notifier).state = lastColor;
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ProviderScope(
              // Como dentro de «Cortar del original» (F41).
              overrides: [
                if (cutting)
                  processedCutSourceProvider.overrideWithValue('item-1'),
              ],
              child: Consumer(
                builder: (context, ref, _) {
                  ref.watch(processedTriageProvider('item-1'));
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: documentHighlightToolbar(
                          context,
                          ref,
                          anchors: const TextSelectionToolbarAnchors(
                            primaryAnchor: Offset(200, 300),
                            secondaryAnchor: Offset(200, 320),
                          ),
                          selection: selection,
                          text: text,
                          canCopy: canCopy,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('resaltar', () {
    testWidgets('un color resalta de fondo con ese color, lo recuerda para '
        'Subrayar y quita la selección', (tester) async {
      await pump(tester);

      await tap(tester, find.byKey(const Key('highlight-color-violet')));

      expect(selection.asked, [
        (color: HighlightColor.violet, style: HighlightStyle.fill, note: null),
      ]);
      expect(container.read(lastHighlightColorProvider), HighlightColor.violet);
      expect(selection.clears, 1);
    });

    testWidgets('Subrayar usa el último color elegido', (tester) async {
      await pump(tester, lastColor: HighlightColor.turquoise);

      await tap(tester, find.byKey(const Key('highlight-underline')));

      expect(selection.asked, [
        (
          color: HighlightColor.turquoise,
          style: HighlightStyle.underline,
          note: null,
        ),
      ]);
    });

    testWidgets('lo que no se pudo ubicar se avisa y la selección queda', (
      tester,
    ) async {
      selection.outcome = const HighlightOutcome.issue(HighlightIssue.scanned);
      await pump(tester);

      await tap(tester, find.byKey(const Key('highlight-color-orange')));

      expect(find.text(es.documentHighlightScanned), findsOneWidget);
      expect(selection.clears, 0);
    });
  });

  group('lo demás', () {
    testWidgets('Copiar copia lo seleccionado y quita la selección', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester);

      await tap(tester, find.byTooltip(es.highlightCopy));

      expect(copied, 'Las fábricas');
      expect(selection.clears, 1);
    });

    testWidgets('un PDF que no deja copiar no ofrece Copiar', (tester) async {
      await pump(tester, canCopy: false);

      expect(find.byType(HighlightToolbar), findsOneWidget);
      expect(find.byTooltip(es.highlightCopy), findsNothing);
    });

    testWidgets('Escuchar lee en voz alta lo seleccionado', (tester) async {
      await pump(tester);

      await tap(tester, find.byTooltip(es.highlightListen));

      final reader =
          container.read(readAloudControllerProvider.notifier)
              as _RecordingReadAloud;
      expect(
        reader.opened?.segments.map((s) => s.spoken).join(' '),
        'Las fábricas',
      );
      expect(selection.clears, 1);
    });

    testWidgets('Nota pide la nota y resalta con ella, con el último color', (
      tester,
    ) async {
      await pump(tester, lastColor: HighlightColor.orange);

      await tap(tester, find.byTooltip(es.highlightAddNote));
      await tester.enterText(find.byType(TextField), 'ojo');
      await tap(tester, find.text(es.detailSave));

      expect(selection.asked, [
        (color: HighlightColor.orange, style: HighlightStyle.fill, note: 'ojo'),
      ]);
    });

    testWidgets('Nota cancelada no resalta nada', (tester) async {
      await pump(tester);

      await tap(tester, find.byTooltip(es.highlightAddNote));
      await tap(tester, find.text(es.commonCancel));

      expect(selection.asked, isEmpty);
    });

    testWidgets('Nota sobre lo que no se ubica lo avisa, sin pedir la nota', (
      tester,
    ) async {
      selection.location = const SelectionLocation.failed(
        HighlightIssue.notLocated,
      );
      await pump(tester);

      await tap(tester, find.byTooltip(es.highlightAddNote));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(es.documentHighlightNotLocated), findsOneWidget);
    });

    testWidgets('Extraer como nota la vincula al elemento con el tramo del '
        'texto extraído, de la primera página a la última', (tester) async {
      selection.location = const SelectionLocation.found([
        (start: 14, end: 24),
        (start: 38, end: 50),
      ]);
      final newItem = KnowledgeItem(
        id: 'item-extracted',
        title: 'industrial',
        source: Source(
          id: 'src',
          kind: SourceKind.manualNote,
          capturedAt: DateTime(2026),
        ),
        processingState: ProcessingState.ready,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      when(
        () => capture.call(
          CaptureRequest.text(rawInput: content.substring(14, 50)),
        ),
      ).thenAnswer((_) async => right(newItem));
      when(
        () => repository.createRelation(
          fromItemId: any(named: 'fromItemId'),
          toItemId: any(named: 'toItemId'),
          kind: any(named: 'kind'),
          sourceCharStart: any(named: 'sourceCharStart'),
          sourceCharEnd: any(named: 'sourceCharEnd'),
        ),
      ).thenAnswer((_) async => right(unit));
      await pump(tester);

      await tap(tester, find.byTooltip(es.detailExtractSelection));

      verify(
        () => repository.createRelation(
          fromItemId: 'item-extracted',
          toItemId: 'item-1',
          kind: RelationKind.extractedFrom,
          sourceCharStart: 14,
          sourceCharEnd: 50,
        ),
      ).called(1);
      expect(selection.clears, 1);
    });

    testWidgets('Extraer o hacer tarjeta de lo que no se ubica lo avisa y no '
        'hace nada', (tester) async {
      selection.location = const SelectionLocation.failed(
        HighlightIssue.scanned,
      );
      await pump(tester);

      await tap(tester, find.byTooltip(es.detailExtractSelection));
      expect(find.text(es.documentHighlightScanned), findsOneWidget);

      await tap(tester, find.byTooltip(es.flashcardsFromSelection));
      expect(find.byType(AlertDialog), findsNothing);

      verifyNever(() => capture.call(any()));
      expect(selection.clears, 0);
    });

    testWidgets('Hacer tarjeta pide la pregunta, con lo seleccionado de '
        'respuesta', (tester) async {
      await pump(tester);

      await tap(tester, find.byTooltip(es.flashcardsFromSelection));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(content.substring(38, 50)), findsOneWidget);
      expect(selection.clears, 1);
    });
  });

  group('mientras se corta del original para Procesado (F41)', () {
    ProcessedTriage triage() =>
        container.read(processedTriageProvider('item-1'));

    testWidgets('fuera de «Cortar del original» no hay «A Procesado»', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byKey(const Key('highlight-to-processed')), findsNothing);
    });

    testWidgets('«A Procesado» manda el tramo del texto extraído a los '
        'fragmentos, de la primera página a la última, y quita la selección', (
      tester,
    ) async {
      selection.location = const SelectionLocation.found([
        (start: 14, end: 24),
        (start: 38, end: 50),
      ]);
      await pump(tester, cutting: true);

      await tap(tester, find.byKey(const Key('highlight-to-processed')));

      final clip = triage().clipsOf(ProcessedSection.fragments).single;
      expect(
        clip.draft,
        const ProcessedDraft.cut(
          ProcessedAnchor(renditionId: 'r1', start: 14, end: 50),
        ),
      );
      expect(clip.excerpt, content.substring(14, 50));
      expect(selection.clears, 1);
    });

    testWidgets('lo que no se ubica se avisa y no se corta', (tester) async {
      selection.location = const SelectionLocation.failed(
        HighlightIssue.scanned,
      );
      await pump(tester, cutting: true);

      await tap(tester, find.byKey(const Key('highlight-to-processed')));

      expect(find.text(es.documentHighlightScanned), findsOneWidget);
      expect(triage().edits, isEmpty);
      expect(selection.clears, 0);
    });

    testWidgets('«Extraer como nota» va a las notas del documento procesado: '
        'no crea ninguna nota en la Biblioteca', (tester) async {
      await pump(tester, cutting: true);

      await tap(tester, find.byTooltip(es.detailExtractSelection));

      expect(
        triage().clipsOf(ProcessedSection.notes).single.draft,
        const ProcessedDraft.cut(
          ProcessedAnchor(renditionId: 'r1', start: 38, end: 50),
        ),
      );
      verifyNever(() => capture.call(any()));
      expect(find.text(es.processedCutNoteAdded), findsOneWidget);
    });
  });
}
