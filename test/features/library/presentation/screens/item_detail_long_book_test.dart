import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_pagination.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/read_aloud_test_support.dart';
import '../../../../support/time_growth.dart';

/// El detalle de un libro de millones de caracteres: desplegar «Extraer texto»
/// dibujaba el libro entero en un solo bloque —decenas de segundos con la
/// interfaz congelada, y Android avisaba que la app no respondía—. Un texto
/// largo se lee por páginas, como en «Leer como libro».
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 10, 27, 10);

  String sentences(String where) =>
      'La revolución industrial cambió el mundo de forma profunda y duradera '
      'para todos los pueblos $where, según cuentan los historiadores que la '
      'estudiaron. ';

  /// Un libro de unos [chars] caracteres, en párrafos.
  String book(int chars) {
    final buffer = StringBuffer();
    var paragraph = 0;
    while (buffer.length < chars) {
      if (paragraph % 40 == 0) {
        buffer.write('## Capítulo ${paragraph ~/ 40}\n\n');
      }
      buffer
        ..write(sentences('del párrafo $paragraph') * 4)
        ..write('\n\n');
      paragraph++;
    }
    return buffer.toString();
  }

  Future<LibraryHarness> pumpItem(
    WidgetTester tester,
    String content, {
    SourceKind kind = SourceKind.document,
  }) async {
    final harness = await LibraryHarness.create();
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'item-1',
            title: 'Un libro',
            source: Source(id: 'src-1', kind: kind, capturedAt: now),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'r1',
                itemId: 'item-1',
                kind: RenditionKind.markdown,
                content: content,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness.wrap(const ItemDetailScreen(itemId: 'item-1')),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  /// Despliega «Extraer texto» y espera a que el libro se parta en otro hilo;
  /// devuelve los microsegundos que la interfaz estuvo ocupada: los cuadros,
  /// no la espera.
  Future<int> unfold(WidgetTester tester) async {
    final row = find.text(es.studyExtractText);
    await tester.ensureVisible(row);
    final watch = Stopwatch()..start();
    await tester.tap(row);
    await tester.pump();
    var busy = watch.elapsedMicroseconds;
    for (var i = 0; i < 400; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(DocumentReaderView).evaluate().isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      watch
        ..reset()
        ..start();
      await tester.pump(const Duration(milliseconds: 50));
      busy += watch.elapsedMicroseconds;
    }
    return busy;
  }

  testWidgets('un libro largo se despliega por páginas: el lector de «Leer '
      'como libro», sin un bloque con el libro entero', (tester) async {
    final content = book(kPagedTextChars + 20000);
    await pumpItem(tester, content);
    expect(find.byKey(const Key('detail-paged-text')), findsNothing);

    await unfold(tester);

    expect(find.byKey(const Key('detail-paged-text')), findsOneWidget);
    expect(find.byType(HighlightableText), findsNothing);
    expect(find.textContaining('Capítulo 0'), findsOneWidget);
    final pages = readerPageRanges(content).length;
    expect(find.text(es.documentReaderPageOf(1, pages)), findsOneWidget);
    // Los botones de estudiar son los de la tarjeta, no se repiten abajo.
    expect(find.byKey(const Key('study-toggle-summary')), findsOneWidget);
  });

  testWidgets('el texto largo ofrece el libro entero para escuchar, partido '
      'en otro hilo: el mismo documento que «Escuchar» de la tarjeta, y por '
      'encima de lo del detalle', (tester) async {
    final content = book(kPagedTextChars + 200000);
    final harness = await pumpItem(tester, content);

    await unfold(tester);
    // Se parte aparte: hasta tenerlo, el lector no lo ofrece.
    ReadableDocument? offered;
    for (var i = 0; i < 400; i++) {
      offered = harness.container.read(currentReadableProvider);
      if (offered?.id == studyReadableId('r1')) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }

    expect(offered?.id, studyReadableId('r1'));
    final markdown = extractedTextIsMarkdown(
      Source(id: 'src-1', kind: SourceKind.document, capturedAt: now),
    );
    expect(
      offered!.segments,
      buildReadableSegments(content, sourceKey: 'r1', markdown: markdown),
    );
    // Lo del detalle no trae el texto: lo ofrece el lector.
    expect(
      harness.container
          .read(readableRegistryProvider)
          .where((document) => document.id == 'item:item-1'),
      everyElement(
        isA<ReadableDocument>().having((d) => d.segments, 'pedazos', isEmpty),
      ),
    );
  });

  testWidgets('en el marco del detalle también se escucha dentro: lo que suena '
      'va en amarillo en su página, y el marco la da vuelta solo', (
    tester,
  ) async {
    final content = book(kPagedTextChars + 20000);
    final harness = await pumpItem(tester, content);
    await unfold(tester);
    ReadableDocument? offered;
    for (var i = 0; i < 400; i++) {
      offered = harness.container.read(currentReadableProvider);
      if (offered?.id == studyReadableId('r1')) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    final pages = readerPageRanges(content);
    // El primer renglón de la tercera página.
    final third = offered!.segments.indexWhere(
      (segment) => segment.start >= pages[2].start,
    );

    await harness.container
        .read(readAloudControllerProvider.notifier)
        .open(offered, fromSegment: third);
    await tester.pumpAndSettle();

    expect(find.text(es.documentReaderPageOf(3, pages.length)), findsOneWidget);
    expect(
      readAloudHighlights(
        tester,
        within: find.byKey(const Key('detail-paged-text')),
      ),
      [
        content.substring(
          offered.segments[third].start,
          offered.segments[third].end,
        ),
      ],
    );
    await harness.container.read(readAloudControllerProvider.notifier).close();
  });

  testWidgets('la transcripción larga de un audio sigue al audio: no se pasa '
      'a páginas', (tester) async {
    await pumpItem(
      tester,
      book(kPagedTextChars + 5000),
      kind: SourceKind.audio,
    );

    await tester.ensureVisible(find.text(es.studyExtractTranscript));
    await tester.tap(find.text(es.studyExtractTranscript));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-paged-text')), findsNothing);
    expect(find.byType(DocumentReaderView), findsNothing);
  });

  testWidgets('un texto que no es tan largo sigue desplegándose de corrido', (
    tester,
  ) async {
    await pumpItem(tester, book(5000));

    await tester.ensureVisible(find.text(es.studyExtractText));
    await tester.tap(find.text(es.studyExtractText));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-paged-text')), findsNothing);
    expect(find.byType(HighlightableText), findsOneWidget);
  });

  testWidgets('desplegar el texto no cuesta más porque el libro sea más '
      'largo: cuatro veces más texto, el mismo tiempo (no cuatro veces)', (
    tester,
  ) async {
    Future<int> open(int chars) async {
      await pumpItem(tester, book(chars));
      final busy = await unfold(tester);
      await tester.pumpWidget(const SizedBox());
      return busy;
    }

    final growth = await timeGrowth(() => open(100000), () => open(400000));

    expect(growth, lessThan(2.2));
  });
}
