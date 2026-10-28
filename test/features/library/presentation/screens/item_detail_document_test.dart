import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/widgets/playback_synced_text.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/memory_study_repository.dart';

/// El detalle de un documento (F21, decisión A): lo principal es el
/// original; el texto extraído queda plegado, porque existe para la
/// búsqueda, el chat, las tarjetas y el quiz, no para leerlo ahí.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 9, 29, 10);

  Future<LibraryHarness> pumpItem(
    WidgetTester tester, {
    required SourceKind kind,
    String content = 'La primera frase del libro.',
    List<Override> extraOverrides = const [],
  }) async {
    final harness = await LibraryHarness.create(extraOverrides: extraOverrides);
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

  testWidgets('el texto extraído de un documento empieza plegado, en el '
      '«Extraer texto» de la tarjeta de estudiar (F36), y se abre si se lo '
      'pide', (tester) async {
    await pumpItem(tester, kind: SourceKind.document);

    expect(find.text(es.detailExtractedTextTitle), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('study-document-card')),
        matching: find.text(es.studyExtractText),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('La primera frase'), findsNothing);

    await tester.tap(find.text(es.studyExtractText));
    await tester.pumpAndSettle();

    expect(find.textContaining('La primera frase'), findsOneWidget);
  });

  testWidgets('en una página web el texto también va plegado en la tarjeta, '
      'y se lee al desplegarlo (F39)', (tester) async {
    await pumpItem(tester, kind: SourceKind.webPage);

    expect(find.text(es.studyCardTitleWebPage), findsOneWidget);
    // Sin fotos, no hay fila de fotos.
    expect(find.byKey(const Key('study-extract-photos')), findsNothing);
    expect(find.text(es.detailExtractedTextTitle), findsNothing);
    expect(find.textContaining('La primera frase'), findsNothing);

    await tester.ensureVisible(find.text(es.studyExtractText));
    await tester.tap(find.text(es.studyExtractText));
    await tester.pumpAndSettle();

    expect(find.textContaining('La primera frase'), findsOneWidget);
  });

  for (final (kind, title) in [
    (SourceKind.socialPost, es.studyCardTitlePost),
    (SourceKind.image, es.studyCardTitleImage),
    (SourceKind.audio, es.studyCardTitleAudio),
    (SourceKind.video, es.studyCardTitleVideo),
    (SourceKind.youtube, es.studyCardTitleVideo),
  ]) {
    testWidgets('$kind tiene su tarjeta, «$title», con el texto plegado '
        'adentro (F39)', (tester) async {
      await pumpItem(tester, kind: kind);

      expect(find.text(title), findsOneWidget);
      expect(find.byKey(const Key('study-extract-text')), findsOneWidget);
      expect(find.textContaining('La primera frase'), findsNothing);
    });
  }

  testWidgets('en un audio, lo estudiado se pinta en la transcripción '
      'desplegada, y eligiendo palabras clave un toque elige una (F39)', (
    tester,
  ) async {
    const content =
        'La revolución industrial cambió todo. Las fábricas usaban vapor.';
    const sentence = 'La revolución industrial cambió todo.';
    final repository = MemoryStudyRepository(
      const DocumentStudy(
        marks: [
          StudyMark(
            id: 's1',
            kind: StudyMarkKind.summary,
            origin: ContentOrigin.ai,
            start: 0,
            end: sentence.length,
          ),
        ],
        analyzedUntil: content.length,
        complete: true,
      ),
    );
    final harness = await pumpItem(
      tester,
      kind: SourceKind.audio,
      content: content,
      extraOverrides: [studyRepositoryProvider.overrideWithValue(repository)],
    );
    final light = StudyPalette.of(Brightness.light);

    await tester.ensureVisible(find.text(es.studyExtractTranscript));
    await tester.tap(find.text(es.studyExtractTranscript));
    await tester.pumpAndSettle();
    harness.container.read(studyViewProvider('r1').notifier).state =
        const StudyView(summary: true, pick: StudyMarkKind.keyword);
    await tester.pumpAndSettle();

    final transcript = find.descendant(
      of: find.byType(PlaybackSyncedText),
      matching: find.byType(SelectableText),
    );
    List<(String, Color?)> pieces() => [
      for (final span
          in tester
              .widget<SelectableText>(transcript)
              .textSpan!
              .children!
              .cast<TextSpan>())
        (span.text!, span.style?.backgroundColor),
    ];
    expect(pieces().first, (sentence, light.summary));

    final state = tester.state<EditableTextState>(
      find.descendant(of: transcript, matching: find.byType(EditableText)),
    );
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection.collapsed(
          offset: content.indexOf('industrial') + 2,
        ),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pumpAndSettle();

    expect(repository.added, ['industrial']);
  });

  testWidgets('las fotos de una página van en la tarjeta, en «Fotos», '
      'plegadas, y no en «Contenido» (F39)', (tester) async {
    final harness = await pumpItem(tester, kind: SourceKind.webPage);
    final attachments = harness.container.read(attachmentRepositoryProvider);
    for (final (i, name) in ['coliseo.jpg', 'foro.jpg'].indexed) {
      await attachments.addAttachment(
        itemId: 'item-1',
        kind: RenditionKind.image,
        relativePath: 'originales/src-1/contenido/$name',
        position: i,
      );
    }
    await attachments.addAttachment(
      itemId: 'item-1',
      kind: RenditionKind.pdf,
      relativePath: 'originales/src-1/contenido/informe.pdf',
      position: 2,
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('study-extract-photos'));
    expect(
      find.descendant(of: row, matching: find.text(es.studyPhotoCount(2))),
      findsOneWidget,
    );
    expect(find.byKey(const Key('item-photos-grid')), findsNothing);
    expect(find.text('${es.contentGroupImages} · 2'), findsNothing);
    expect(find.text('${es.contentGroupDocuments} · 1'), findsOneWidget);

    await tester.ensureVisible(row);
    await tester.tap(
      find.descendant(of: row, matching: find.text(es.studyExtractPhotos)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-photos-grid')), findsOneWidget);
  });

  testWidgets('sin la tarjeta —una nota—, las fotos siguen en «Contenido»', (
    tester,
  ) async {
    final harness = await pumpItem(tester, kind: SourceKind.manualNote);
    await harness.container
        .read(attachmentRepositoryProvider)
        .addAttachment(
          itemId: 'item-1',
          kind: RenditionKind.image,
          relativePath: 'originales/src-1/contenido/coliseo.jpg',
          position: 0,
        );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('study-extract-photos')), findsNothing);
    expect(find.text('${es.contentGroupImages} · 1'), findsOneWidget);
  });
}
