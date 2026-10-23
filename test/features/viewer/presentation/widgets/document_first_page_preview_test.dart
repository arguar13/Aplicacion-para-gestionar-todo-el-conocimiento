import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_first_page_preview.dart';

import '../../../../support/memory_study_repository.dart';

/// La primera página fija de un documento de texto (F39): lo estudiado y lo
/// resaltado a mano que cae en ella se sigue viendo; lo de las otras páginas,
/// no.
void main() {
  const pageOne = 'Primera hoja con una idea importante.';
  const pageTwo = 'Segunda hoja que nadie ve acá.';
  const content = '$pageOne\n\n---\n\n$pageTwo';
  final twoStart = content.indexOf(pageTwo);

  Highlight at(int start, int end, {String id = 'h1'}) => Highlight(
    id: id,
    renditionId: 'r1',
    startOffset: start,
    endOffset: end,
    excerpt: content.substring(start, end),
    createdAt: DateTime.utc(2026),
    color: HighlightColor.violet,
  );

  late ProviderContainer container;

  Future<void> pumpPreview(
    WidgetTester tester, {
    List<Highlight> highlights = const [],
    DocumentStudy study = DocumentStudy.notStarted,
    bool withStudy = true,
    VoidCallback? onTap,
  }) async {
    container = ProviderContainer(
      overrides: [
        studyRepositoryProvider.overrideWithValue(MemoryStudyRepository(study)),
        renditionHighlightsProvider.overrideWith(
          (ref, id) => Stream.value(highlights),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: DocumentFirstPagePreview(
                content: content,
                onTap: onTap,
                study: withStudy
                    ? (
                        itemId: 'item-1',
                        renditionId: 'r1',
                        content: content,
                        markdown: true,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Los tramos del texto de la página, con su fondo.
  List<(String, Color?)> pieces(WidgetTester tester) {
    final found = <(String, Color?)>[];
    tester
        .widget<Text>(
          find.descendant(
            of: find.byType(DocumentFirstPagePreview),
            matching: find.byType(Text),
          ),
        )
        .textSpan!
        .visitChildren((span) {
          if (span is TextSpan && span.text != null) {
            found.add((span.text!, span.style?.backgroundColor));
          }
          return true;
        });
    return found;
  }

  testWidgets('muestra la primera página y nada de las otras', (tester) async {
    await pumpPreview(tester);

    expect(
      find.textContaining('Primera hoja', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Segunda hoja', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('lo subrayado a mano en la primera página se ve con su color; '
      'lo de otra página, no', (tester) async {
    await pumpPreview(
      tester,
      highlights: [
        at(0, 7),
        at(twoStart, twoStart + 7, id: 'h2'),
      ],
    );
    final context = tester.element(find.byType(DocumentFirstPagePreview));

    expect(pieces(tester), [
      ('Primera', HighlightPalette.resolve(context, HighlightColor.violet)),
      (' hoja con una idea importante.', null),
    ]);
  });

  testWidgets('lo estudiado —el resumen y las palabras clave— que cae en la '
      'primera página se ve con sus colores', (tester) async {
    const summary = StudyMark(
      id: 's1',
      kind: StudyMarkKind.summary,
      origin: ContentOrigin.ai,
      start: 0,
      end: pageOne.length,
    );
    final keyword = StudyMark(
      id: 'k1',
      kind: StudyMarkKind.keyword,
      origin: ContentOrigin.ai,
      start: pageOne.indexOf('idea'),
      end: pageOne.indexOf('idea') + 4,
    );
    await pumpPreview(
      tester,
      study: DocumentStudy(
        marks: [summary, keyword],
        analyzedUntil: content.length,
        complete: true,
      ),
    );
    container.read(studyViewProvider('r1').notifier).state = const StudyView(
      summary: true,
      keywords: true,
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(DocumentFirstPagePreview));
    final study = StudyPalette.of(Theme.of(context).brightness);

    expect(pieces(tester), [
      ('Primera hoja con una ', study.summary),
      ('idea', study.keyword),
      (' importante.', study.summary),
    ]);
  });

  testWidgets('sin el texto de un elemento —un adjunto— no se pinta nada', (
    tester,
  ) async {
    await pumpPreview(tester, withStudy: false, highlights: [at(0, 7)]);

    expect(find.byType(RichText), findsWidgets);
    expect(pieces(tester).where((p) => p.$2 != null), isEmpty);
  });

  testWidgets('tocarla avisa; no se selecciona ni se desplaza', (tester) async {
    var taps = 0;
    await pumpPreview(tester, onTap: () => taps++);

    await tester.tap(find.byKey(const Key('document-first-page-preview')));

    expect(taps, 1);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(Scrollable), findsNothing);
  });
}
