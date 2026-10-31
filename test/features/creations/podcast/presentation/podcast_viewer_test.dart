import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/podcast_kind.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/processed_rows.dart';
import '../../presentation/repasar_harness.dart';

/// F47, paso 6: el podcast guardado en «Lo creado» —su fila, «Hecho con IA»,
/// el botón de escuchar con su estado y el guion como transcripción, con
/// cada cita tocable que lleva al pasaje—, en la app de verdad con su router.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;

  const sourceText =
      'Capítulo 14. Y el mar se abrió ante ellos, y los hijos de Israel '
      'entraron por en medio del mar, en seco.';
  const quote = 'el mar se abrió ante ellos';

  const podcast = Podcast(
    title: 'El mar abierto',
    format: PodcastFormat.conversation,
    length: PodcastLength.short,
    requestedWords: 450,
    targetWords: 450,
    segments: [
      PodcastSegment(
        speaker: PodcastSpeaker.a,
        text: '¿Qué pasó cuando llegaron al mar?',
        kind: PodcastSegmentKind.link,
        pauseAfter: kPodcastTurnPause,
      ),
      PodcastSegment(
        speaker: PodcastSpeaker.b,
        text: 'El mar se abrió y el pueblo cruzó en seco.',
        kind: PodcastSegmentKind.data,
        pauseAfter: kPodcastBreath,
        citations: [
          PodcastCitation(
            quote: quote,
            documentId: 'p-1',
            documentTitle: 'Éxodo — Comentario',
          ),
        ],
      ),
      PodcastSegment(
        speaker: PodcastSpeaker.b,
        text: 'Lo cuenta el capítulo catorce.',
        kind: PodcastSegmentKind.data,
        citations: [
          PodcastCitation(
            quote: 'una frase que la fuente ya no tiene',
            documentId: 'p-1',
            documentTitle: 'Éxodo — Comentario',
          ),
        ],
      ),
    ],
  );

  setUp(() async {
    harness = await RepasarHarness.create(specs: [podcastKindSpec()]);
  });

  /// La fuente src-1 con [sourceText], para que la cita tenga a dónde ir.
  Future<void> saveSource() async {
    final now = DateTime(2026, 10, 30);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'src-1',
            title: 'Éxodo',
            source: Source(
              id: 'src-1',
              kind: SourceKind.webPage,
              capturedAt: now,
              url: 'https://e.org/exodo',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend-src-1',
                itemId: 'src-1',
                kind: RenditionKind.markdown,
                content: sourceText,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
  }

  /// Un podcast listo sobre p-1, escrito por «Gemini»; con [sourceItemId],
  /// la fuente que guardó [saveSource].
  Future<StudyCreation> ready({
    Podcast content = podcast,
    String? raw,
    String? sourceItemId,
  }) async {
    await insertProcessedRows(
      harness.library.database,
      id: 'p-1',
      title: 'Éxodo — Comentario',
      sourceItemId: sourceItemId,
      parts: const {
        ProcessedSection.text: [sourceText],
      },
    );
    final queued = await harness.creation(
      StudyCreationKind.podcast,
      scope: const CreationScope.document('p-1'),
      sources: const ['p-1'],
      status: CreationStatus.generating,
    );
    await harness.creations.complete(
      queued.id,
      title: content.title,
      content: raw ?? PodcastJson.encodeString(content),
    );
    return queued;
  }

  Future<void> open(
    WidgetTester tester,
    StudyCreation creation, {
    Size size = const Size(420, 900),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) => harness.openRepasar(
    tester,
    size: size,
    theme: theme,
    textScale: textScale,
    location: '/creations/${creation.id}',
  );

  testWidgets('arriba, de qué es, «Hecho con IA» con su modelo y el botón de '
      'escuchar apagado, que dice por qué', (tester) async {
    final creation = await ready();
    await open(tester, creation);

    expect(find.text('El mar abierto'), findsWidgets);
    expect(
      find.text('${es.f47P6FormatConversation} · ~1 min · 2 voces'),
      findsOneWidget,
    );
    expect(find.text(es.f47P6MadeWithAiModel('Gemini')), findsOneWidget);
    final listen = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(es.f47P6Listen),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(listen.onPressed, isNull);
    expect(find.text(es.f47P6AudioPending), findsOneWidget);
    expect(find.text(es.f47P6Transcript), findsOneWidget);
  });

  testWidgets('la transcripción: cada tramo, y quién habla cuando cambia', (
    tester,
  ) async {
    final creation = await ready();
    await open(tester, creation);

    for (final segment in podcast.segments) {
      expect(find.text(segment.text), findsOneWidget);
    }
    // La Voz 2 dice dos tramos seguidos: su nombre va una sola vez.
    expect(find.text(es.f47P6SpeakerA), findsOneWidget);
    expect(find.text(es.f47P6SpeakerB), findsOneWidget);
    expect(find.byKey(const ValueKey('podcast-citation-1-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('podcast-citation-0-0')), findsNothing);
  });

  testWidgets('tocar una cita abre la lectura de la fuente parada en el '
      'pasaje', (tester) async {
    await saveSource();
    final creation = await ready(sourceItemId: 'src-1');
    await open(tester, creation);

    await tester.tap(find.byKey(const ValueKey('podcast-citation-1-0')));
    await tester.pumpAndSettle();

    final start = sourceText.indexOf('el mar se abrió ante ellos');
    final reading = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
    expect(reading.itemId, 'src-1');
    expect(reading.jump, (start: start, end: start + quote.length));
  });

  testWidgets('una cita que ya no está en la fuente abre el documento y lo '
      'dice', (tester) async {
    await saveSource();
    final creation = await ready(sourceItemId: 'src-1');
    await open(tester, creation);

    final citation = find.byKey(const ValueKey('podcast-citation-2-0'));
    await tester.ensureVisible(citation);
    await tester.pumpAndSettle();
    await tester.tap(citation);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ProcessedDocumentScreen>(find.byType(ProcessedDocumentScreen))
          .documentId,
      'p-1',
    );
    expect(find.text(es.f43MindPassageMissing), findsOneWidget);
  });

  testWidgets('lo que quitó la comprobación se cuenta, y abierto se ve '
      'tachado con su porqué; si el material no daba, también se dice', (
    tester,
  ) async {
    const checked = Podcast(
      title: 'Corto',
      format: PodcastFormat.brief,
      length: PodcastLength.long,
      requestedWords: 2250,
      targetWords: 300,
      segments: [
        PodcastSegment(
          speaker: PodcastSpeaker.a,
          text: 'El mar se abrió.',
          kind: PodcastSegmentKind.data,
          citations: [PodcastCitation(quote: quote, documentId: 'p-1')],
        ),
      ],
      discarded: [
        PodcastDiscard(
          reason: PodcastDiscardReason.numberNotInMaterial,
          text: 'Cruzaron 600.000 personas.',
        ),
        PodcastDiscard(
          reason: PodcastDiscardReason.noCitation,
          text: 'Fue el mayor milagro.',
        ),
      ],
    );
    final creation = await ready(content: checked);
    await open(tester, creation);

    expect(find.text(es.f47P6Shortened(2, 15)), findsOneWidget);
    expect(find.text(es.f47P6Discarded(2)), findsOneWidget);
    expect(find.text('Cruzaron 600.000 personas.'), findsNothing);
    // Una sola voz: la transcripción no nombra a nadie.
    expect(find.text(es.f47P6SpeakerA), findsNothing);

    await tester.tap(find.text(es.f47P6Discarded(2)));
    await tester.pumpAndSettle();
    final struck = tester.widget<Text>(find.text('Cruzaron 600.000 personas.'));
    expect(struck.style?.decoration, TextDecoration.lineThrough);
    expect(find.text(es.f47P6DiscardNumber), findsOneWidget);
    expect(find.text(es.f47P6DiscardNoCitation), findsOneWidget);
  });

  testWidgets('lo guardado que no se entiende lo dice, sin romperse', (
    tester,
  ) async {
    final creation = await ready(raw: '{"segments": []}');
    await open(tester, creation);

    expect(find.text(es.f47P6Unreadable), findsOneWidget);
  });

  testWidgets('en «Lo creado», su fila con su nombre; tocarla lo abre', (
    tester,
  ) async {
    final creation = await ready();
    harness.container.read(repasarScopeProvider.notifier).state =
        const CreationScope.document('p-1');
    await harness.openRepasar(tester, size: const Size(420, 2400));
    final row = find.byKey(ValueKey('creation-tile-${creation.id}'));
    await tester.scrollUntilVisible(
      row,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('review-entry')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    // La fila dice de qué tipo es y el título que le puso la IA.
    expect(
      find.descendant(of: row, matching: find.textContaining('El mar abierto')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining(es.f47P6KindPodcast),
      ),
      findsWidgets,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('podcast-viewer')), findsOneWidget);
  });

  for (final theme in [AppThemeChoice.light, AppThemeChoice.dark]) {
    testWidgets('a 360 dp con la letra al doble, en ${theme.name}, sin '
        'desbordes y con el lector de pantalla', (tester) async {
      final handle = tester.ensureSemantics();
      final creation = await ready();
      await open(
        tester,
        creation,
        size: const Size(360, 780),
        theme: theme,
        textScale: 2,
      );
      final citation = find.byKey(const ValueKey('podcast-citation-1-0'));
      // La lista se arma de a lo que se ve: se baja hasta la cita.
      await tester.scrollUntilVisible(
        citation,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('podcast-viewer')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getRect(citation).right, lessThanOrEqualTo(360));
      // Cada tramo dice quién habla; cada cita, de dónde es y qué hace.
      expect(
        find.bySemanticsLabel(
          '${es.f47P6SpeakerB}: El mar se abrió y el pueblo cruzó en seco.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(citation),
        isSemantics(
          label: es.f47P6CitationSemantics('Éxodo — Comentario', quote),
          hint: es.f47P6CitationHint,
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  }
}
