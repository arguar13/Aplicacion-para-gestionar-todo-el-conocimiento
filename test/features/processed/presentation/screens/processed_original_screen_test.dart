import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_triage_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_original_screen.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../processed_ui_fixture.dart';

/// La copia del original en el documento procesado (F41, decisión H): se abre
/// en su visor con lo elegido marcado encima, sin mezclarse con lo de la
/// fuente, y si el texto de la fuente cambió, no se pinta nada y se dice.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  const text = 'La república romana cayó. César cruzó el Rubicón.';
  const add = OriginalEdit(ProcessedChange.add);

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Un documento de texto con su archivo, su resumen, una palabra clave y un
  /// fragmento, procesado con la copia del original.
  Future<String> processDocument({String name = 'notas.txt'}) async {
    await harness.saveTextSource(
      'roma',
      title: 'Roma',
      kind: SourceKind.document,
      originalName: name,
      originalBytes: text.codeUnits,
    );
    await harness.addSummarySentence('roma', text, 'César cruzó el Rubicón.');
    await harness.addSummarySentence(
      'roma',
      text,
      'república',
      kind: StudyMarkKind.keyword,
    );
    return harness.process('roma', {
      ProcessedSection.summary: SectionEdit.add(
        const SectionInput.fromSource(),
      ),
      ProcessedSection.keywords: SectionEdit.add(
        const SectionInput.fromSource(),
      ),
      ProcessedSection.fragments: harness.fragmentOf('roma', text, 'La'),
    }, original: add);
  }

  Future<void> open(WidgetTester tester, String id) async {
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.processedOriginal(id));
    expect(find.byType(ProcessedOriginalScreen), findsOneWidget);
  }

  testWidgets('desde el documento, «Ver el original» abre la copia en el '
      'lector, con su tarjeta: qué es, cuánto ocupa y cuándo se copió', (
    tester,
  ) async {
    final id = await processDocument();
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));

    final card = find.byKey(const Key('processed-original-card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining(es.processedOriginalKindDocument),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text(es.processedOriginalOpen));
    await tester.pumpAndSettle();

    expect(find.byType(ProcessedOriginalScreen), findsOneWidget);
    expect(find.byType(DocumentReaderView), findsOneWidget);
    expect(find.byKey(const Key('processed-original-notice')), findsNothing);
  });

  testWidgets('lo estudiado de la copia es lo elegido del procesado —el '
      'resumen y la palabra clave—, con la clave de la copia y no la de la '
      'fuente', (tester) async {
    final id = await processDocument();
    await open(tester, id);

    final key = processedOriginalStudyKeyFor(id);
    final reader = tester.widget<DocumentReaderView>(
      find.byType(DocumentReaderView),
    );
    expect(reader.study!.renditionId, key);
    expect(reader.study!.itemId, id);
    expect(reader.content, text);
    expect(reader.showStudyBar, isFalse);

    final study = await harness.container.read(
      documentStudyProvider(key).future,
    );
    final start = text.indexOf('César');
    expect(
      [
        for (final mark in study.of(StudyMarkKind.summary))
          (mark.start, mark.end),
      ],
      [(start, start + 23)],
    );
    expect(
      [
        for (final mark in study.of(StudyMarkKind.keyword))
          text.substring(mark.start, mark.end),
      ],
      ['república'],
    );
    // Se abre con todo a la vista.
    expect(
      harness.container.read(studyViewProvider(key)),
      kMarkedCopyStudyView,
    );
    // Los fragmentos, con el color de los cortes, sobre la copia.
    expect(harness.container.read(processedOriginalCutsProvider(key)), [
      ProcessedAnchor(renditionId: key, start: 0, end: 2),
    ]);
    // La fuente sigue con lo suyo: nada de lo elegido es suyo.
    final fromSource = await harness.container.read(
      documentStudyProvider('rend-roma').future,
    );
    expect(fromSource.of(StudyMarkKind.summary), hasLength(1));
    expect(
      fromSource.of(StudyMarkKind.summary).single.id,
      isNot(study.of(StudyMarkKind.summary).single.id),
    );
  });

  test('la copia solo se lee: escribir en ella falla y no toca nada', () async {
    final repository = harness.container.read(studyRepositoryProvider);
    final result = await repository.addUserMark(
      renditionId: processedOriginalStudyKeyFor('x'),
      content: text,
      kind: StudyMarkKind.summary,
      start: 0,
      end: 5,
    );
    expect(result.isLeft(), isTrue);
  });

  testWidgets('el resumen se pinta con el verde de estudiar, y su '
      'interruptor lo apaga', (tester) async {
    final id = await processDocument();
    await open(tester, id);
    final green = StudyPalette.of(Brightness.light).summary;

    // El lector pinta su página con un `SelectableText.rich`.
    bool painted() => tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .any((text) => _hasBackground(text.textSpan!, green));

    expect(painted(), isTrue);

    await tester.tap(
      find.widgetWithText(FilterChip, es.processedSectionSummary),
    );
    await tester.pumpAndSettle();
    expect(painted(), isFalse);
  });

  testWidgets('el fragmento se pinta con el color de los cortes', (
    tester,
  ) async {
    final id = await processDocument();
    await open(tester, id);
    final peach = ProcessedCutPalette.of(Brightness.light);

    expect(
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any((text) => _hasBackground(text.textSpan!, peach)),
      isTrue,
    );
  });

  testWidgets('si el texto de la fuente cambió, no se pinta nada y una línea '
      'dice por qué; un documento se ofrece abrir con otra app', (
    tester,
  ) async {
    final id = await processDocument();
    await harness.changeSourceTextHash('roma');
    await open(tester, id);

    expect(find.text(es.processedOriginalUnmarked), findsOneWidget);
    expect(find.byType(DocumentReaderView), findsNothing);
    expect(find.text(es.processedOriginalOpenWith), findsOneWidget);
    expect(
      find.widgetWithText(FilterChip, es.processedSectionSummary),
      findsNothing,
    );
  });

  testWidgets('una página archivada se abre en el visor de páginas', (
    tester,
  ) async {
    await harness.saveTextSource(
      'pagina',
      title: 'Una página',
      originalName: 'pagina.html',
    );
    final id = await harness.process('pagina', {
      ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
    }, original: add);
    await open(tester, id);

    expect(tester.takeException(), isNull);
    final viewer = tester.widget<WebPageViewerView>(
      find.byType(WebPageViewerView),
    );
    expect(viewer.text, isNotNull);
  });

  testWidgets('sin copia lo dice', (tester) async {
    await harness.saveTextSource('roma', title: 'Roma');
    final id = await harness.processTextAndNotes('roma');
    await open(tester, id);

    expect(find.text(es.processedOriginalMissing), findsOneWidget);
  });

  testWidgets('sin copia, el documento no muestra su tarjeta', (tester) async {
    await harness.saveTextSource('roma', title: 'Roma');
    final id = await harness.processTextAndNotes('roma');
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));

    expect(find.byKey(const Key('processed-original-card')), findsNothing);
  });
}

bool _hasBackground(InlineSpan span, Color color) {
  if (span is! TextSpan) return false;
  if (span.style?.backgroundColor == color) return true;
  return (span.children ?? const <InlineSpan>[]).any(
    (child) => _hasBackground(child, color),
  );
}
