import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/presentation/fragment_citation.dart';
import 'package:sinapsis/features/citations/presentation/providers/citation_preferences.dart';
import 'package:sinapsis/features/notes/domain/entities/cited_source.dart';
import 'package:sinapsis/features/notes/presentation/providers/note_sources_providers.dart';
import 'package:sinapsis/features/notes/presentation/widgets/cited_sources_section.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/reference/presentation/providers/reference_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/library_harness.dart';

/// La cita de un fragmento (F15): la de su fuente, con la página o el minuto
/// donde está, en el estilo y el idioma por defecto. Sale de una nota atómica
/// que se extrajo de la fuente y de un resaltado. Contra SQLite real.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  final now = DateTime(2026, 9, 21, 9);

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  const book = ReferenceData(
    type: ReferenceType.book,
    publisher: 'Sudamericana',
    publicationPrecision: PublicationPrecision.year,
    contributors: [
      Contributor(
        name: PersonName(family: 'García Márquez', given: 'Gabriel'),
      ),
    ],
  );

  /// Una fuente con su referencia, su texto principal y unos fragmentos con
  /// página: el 0–100 es la página 1 y el 100–250, la 2.
  Future<void> library() async {
    final writer = KnowledgeEntryWriter(harness.database, clock: () => now);
    await writer.upsert(
      KnowledgeItem(
        id: 'libro',
        title: 'Cien años de soledad',
        source: Source(
          id: 'src-libro',
          kind: SourceKind.document,
          capturedAt: now,
          publishedAt: DateTime(1967),
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await writer.setReference('libro', book);
    await harness.database
        .into(harness.database.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'texto',
            itemId: 'libro',
            kind: RenditionKind.plainText,
            content: Value('x' * 250),
            isPrimary: true,
            createdAt: now,
          ),
        );
    for (final (seq, start, end, page) in [(0, 0, 100, 1), (1, 100, 250, 2)]) {
      await harness.database
          .into(harness.database.chunks)
          .insert(
            ChunksCompanion.insert(
              id: 'chunk-$seq',
              itemId: 'libro',
              seq: seq,
              content: 'x' * (end - start),
              charStart: start,
              charEnd: end,
              pageNumber: Value(page),
            ),
          );
    }
    await writer.upsert(
      KnowledgeItem(
        id: 'nota',
        title: 'Una nota',
        source: Source(
          id: 'src-nota',
          kind: SourceKind.manualNote,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Lo que se copió al portapapeles mientras dura la prueba.
  List<String> listenClipboard(WidgetTester tester) {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
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
    return copied;
  }

  group('la cita de un fragmento', () {
    /// Pide la cita a través de un `Consumer`, que es de donde sale un `ref`.
    Future<String?> cite(
      WidgetTester tester, {
      String sourceId = 'libro',
      CitationLocator? locator,
    }) async {
      late WidgetRef captured;
      await tester.pumpWidget(
        harness.wrap(
          Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final citation = await citeFragment(
        captured,
        sourceId: sourceId,
        locator: locator,
      );
      return citation?.toPlainText();
    }

    testWidgets('en APA, la cita en el texto con la página', (tester) async {
      await library();

      expect(
        await cite(tester, locator: const CitationLocator.page('12')),
        '(García Márquez, 1967, p. 12)',
      );
      expect(
        await cite(tester, locator: const CitationLocator.page('12-14')),
        '(García Márquez, 1967, pp. 12–14)',
      );
      expect(
        await cite(tester, locator: const CitationLocator.time('2:07')),
        '(García Márquez, 1967, 2:07)',
      );
    });

    testWidgets('sin página ni minuto cita la obra entera', (tester) async {
      await library();

      expect(await cite(tester), '(García Márquez, 1967)');
    });

    testWidgets('en Chicago notas, la nota al pie con la página al final', (
      tester,
    ) async {
      await library();
      await harness.container
          .read(citationPreferencesProvider.notifier)
          .setStyle('chicago17nb');

      expect(
        await cite(tester, locator: const CitationLocator.page('12')),
        'Gabriel García Márquez, Cien años de soledad (Sudamericana, 1967), '
        '12.',
      );
    });

    testWidgets('en IEEE, el número entre corchetes y la página', (
      tester,
    ) async {
      await library();
      await harness.container
          .read(citationPreferencesProvider.notifier)
          .setStyle('ieee');

      expect(
        await cite(tester, locator: const CitationLocator.page('12')),
        '[1, p. 12]',
      );
    });

    testWidgets('en el idioma que se haya elegido', (tester) async {
      await library();
      await harness.container
          .read(citationPreferencesProvider.notifier)
          .setLanguage(CitationLanguage.en);

      expect(
        await cite(tester, locator: const CitationLocator.page('12-14')),
        '(García Márquez, 1967, pp. 12–14)',
      );
    });

    testWidgets('lo que falta de la fuente sale marcado, no callado', (
      tester,
    ) async {
      await library();
      await harness.container
          .read(referenceRepositoryProvider)
          .saveReference('libro', const ReferenceData());

      final text = await cite(
        tester,
        locator: const CitationLocator.page('12'),
      );

      expect(text, contains('[falta: autor]'));
    });

    testWidgets('una fuente que no existe, o una nota, no se cita', (
      tester,
    ) async {
      await library();

      expect(await cite(tester, sourceId: 'fantasma'), isNull);
      expect(await cite(tester, sourceId: 'nota'), isNull);
    });
  });

  group('desde una nota atómica', () {
    Future<void> pumpNote(
      WidgetTester tester,
      List<CitedFragment> fragments,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness.wrap(
          ProviderScope(
            overrides: [
              citedSourcesProvider.overrideWith(
                (ref, noteId) => Stream.value([
                  CitedSource(
                    sourceId: 'libro',
                    title: 'Cien años de soledad',
                    sourceKind: SourceKind.document,
                    isDirect: false,
                    fragments: fragments,
                  ),
                ]),
              ),
            ],
            child: const Scaffold(
              body: SingleChildScrollView(
                child: CitedSourcesSection(noteId: 'nota'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Los fragmentos están en la fila de la fuente, plegada.
      await tester.tap(find.text('Cien años de soledad').first);
      await tester.pumpAndSettle();
    }

    CitedFragment fragment({int? page, int? ms}) => CitedFragment(
      noteId: 'n1',
      noteTitle: 'Una idea',
      start: 10,
      end: 40,
      startMs: ms,
      pageNumber: page,
    );

    testWidgets('copia la cita con la página del fragmento', (tester) async {
      await library();
      final copied = listenClipboard(tester);
      await pumpNote(tester, [fragment(page: 12)]);

      await tester.tap(find.byTooltip(es.citedFragmentCiteTooltip));
      await tester.pumpAndSettle();

      expect(copied, ['(García Márquez, 1967, p. 12)']);
      expect(find.text(es.citationCopied), findsOneWidget);
    });

    testWidgets('con el minuto, si es un video o un audio', (tester) async {
      await library();
      final copied = listenClipboard(tester);
      await pumpNote(tester, [fragment(ms: 3727000)]);

      await tester.tap(find.byTooltip(es.citedFragmentCiteTooltip));
      await tester.pumpAndSettle();

      expect(copied, ['(García Márquez, 1967, 1:02:07)']);
    });

    testWidgets('si tiene página y minuto, la página', (tester) async {
      await library();
      final copied = listenClipboard(tester);
      await pumpNote(tester, [fragment(page: 3, ms: 5000)]);

      await tester.tap(find.byTooltip(es.citedFragmentCiteTooltip));
      await tester.pumpAndSettle();

      expect(copied, ['(García Márquez, 1967, p. 3)']);
    });

    testWidgets('sin saber dónde está, cita la obra', (tester) async {
      await library();
      final copied = listenClipboard(tester);
      await pumpNote(tester, [fragment()]);

      await tester.tap(find.byTooltip(es.citedFragmentCiteTooltip));
      await tester.pumpAndSettle();

      expect(copied, ['(García Márquez, 1967)']);
    });

    testWidgets('cada fragmento cita el suyo', (tester) async {
      await library();
      final copied = listenClipboard(tester);
      await pumpNote(tester, [fragment(page: 5), fragment(page: 9)]);

      await tester.tap(find.byTooltip(es.citedFragmentCiteTooltip).last);
      await tester.pumpAndSettle();

      expect(copied, ['(García Márquez, 1967, p. 9)']);
    });
  });

  group('desde un resaltado', () {
    Future<void> highlight(
      String id, {
      required String renditionId,
      required int start,
      required int end,
    }) => harness.database
        .into(harness.database.highlights)
        .insert(
          HighlightsCompanion.insert(
            id: id,
            renditionId: renditionId,
            startOffset: start,
            endOffset: end,
            excerpt: 'un pasaje',
            createdAt: now,
          ),
        );

    Future<void> pumpHighlights(
      WidgetTester tester, {
      String itemId = 'libro',
      String renditionId = 'texto',
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness.wrap(
          Scaffold(
            body: SingleChildScrollView(
              child: HighlightableText(
                itemId: itemId,
                renditionId: renditionId,
                content: 'x' * 250,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lleva la página del fragmento donde empieza', (tester) async {
      await library();
      await highlight('uno', renditionId: 'texto', start: 20, end: 60);
      await highlight('dos', renditionId: 'texto', start: 140, end: 200);
      final copied = listenClipboard(tester);
      await pumpHighlights(tester);

      await tester.tap(find.byKey(const Key('cite-highlight-uno')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cite-highlight-dos')));
      await tester.pumpAndSettle();

      expect(copied, [
        '(García Márquez, 1967, p. 1)',
        '(García Márquez, 1967, p. 2)',
      ]);
    });

    testWidgets('el botón de citar tiene su nombre', (tester) async {
      await library();
      await highlight('uno', renditionId: 'texto', start: 20, end: 60);
      await pumpHighlights(tester);

      expect(find.byTooltip(es.detailHighlightCiteTooltip), findsOneWidget);
    });

    testWidgets('una forma que no es el texto principal cita la obra', (
      tester,
    ) async {
      await library();
      await harness.database
          .into(harness.database.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'resumen',
              itemId: 'libro',
              kind: RenditionKind.plainText,
              content: Value('x' * 250),
              isPrimary: false,
              createdAt: now,
            ),
          );
      await highlight('uno', renditionId: 'resumen', start: 140, end: 200);
      final copied = listenClipboard(tester);
      await pumpHighlights(tester, renditionId: 'resumen');

      await tester.tap(find.byKey(const Key('cite-highlight-uno')));
      await tester.pumpAndSettle();

      expect(copied, ['(García Márquez, 1967)']);
    });

    testWidgets('en una nota no se ofrece citar', (tester) async {
      await library();
      await harness.database
          .into(harness.database.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'texto-nota',
              itemId: 'nota',
              kind: RenditionKind.plainText,
              content: Value('x' * 250),
              isPrimary: true,
              createdAt: now,
            ),
          );
      await highlight('uno', renditionId: 'texto-nota', start: 20, end: 60);
      await pumpHighlights(tester, itemId: 'nota', renditionId: 'texto-nota');

      expect(find.byKey(const Key('cite-highlight-uno')), findsNothing);
      // El resaltado sigue ahí, con su botón de quitarlo.
      expect(find.byTooltip(es.detailRemoveHighlight), findsOneWidget);
    });
  });
}
