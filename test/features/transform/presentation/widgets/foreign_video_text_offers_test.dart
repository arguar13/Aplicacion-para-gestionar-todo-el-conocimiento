import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_text_refresh.dart';
import 'package:sinapsis/features/transform/domain/repositories/video_text_repository.dart';
import 'package:sinapsis/features/transform/presentation/providers/foreign_video_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';
import '../../../processed/presentation/processed_ui_fixture.dart';

/// «Volver a extraer» lo ya guardado de un video cuyo texto no está en su
/// idioma (F45, paso 4): en la Bandeja y en Procesado, de a uno o todos de
/// una vez, sobre la base real en memoria.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 10, 30, 12);
  const title =
      'Las reliquias de San Francisco de Asís que han fascinado al mundo';
  const arabic =
      '[0:00] بقايا القديس فرنسيس الأسيزي التي أذهلت العالم\n'
      '[0:07] في هذا الفيديو نتحدث عن تاريخ هذه الآثار المقدسة';
  const spanish =
      '[0:00] Las reliquias de San Francisco de Asís han fascinado al mundo, '
      'y en este video vamos a ver por qué son tan importantes para los '
      'fieles y cómo se conservan desde hace más de ochocientos años.';
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Un video guardado con [text] y el idioma [language], listo, en la
  /// Bandeja.
  Future<void> saveVideo(
    String id, {
    String text = arabic,
    String? language = 'ar',
    SourceKind kind = SourceKind.youtube,
    DateTime? at,
  }) async {
    final when = at ?? now;
    final saved = await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: title,
            source: Source(
              id: id,
              kind: kind,
              capturedAt: when,
              url: 'https://www.youtube.com/watch?v=dQw4w9WgX$id',
              language: language,
            ),
            processingState: ProcessingState.ready,
            createdAt: when,
            updatedAt: when,
            renditions: [
              Rendition.text(
                id: 'rend-$id',
                itemId: id,
                kind: RenditionKind.plainText,
                content: text,
                isPrimary: true,
                createdAt: when,
              ),
            ],
          ),
        );
    saved.getOrElse((failure) => throw StateError('$failure'));
  }

  Future<String?> languageOf(String id) async =>
      (await harness.container.read(libraryRepositoryProvider).findById(id))
          .getRight()
          .toNullable()
          ?.source
          .language;

  /// El texto del documento [documentId], parte por parte.
  Future<List<String>> textOf(String documentId) async {
    final parts = await harness.container
        .read(processedRepositoryProvider)
        .partsOf(documentId, sections: {ProcessedSection.text});
    return [
      for (final part in parts.getOrElse((f) => throw StateError('$f')))
        part.content,
    ];
  }

  group('lo que se lee de la base', () {
    test(
      'la Bandeja: los videos con texto, en su orden, con solo el '
      'comienzo del texto; ni lo que no es un video ni la papelera',
      () async {
        await saveVideo('a', at: now);
        await saveVideo(
          'b',
          text: 'x' * 20000,
          at: now.add(const Duration(minutes: 1)),
        );
        await saveVideo('web', kind: SourceKind.webPage);
        await saveVideo('borrado');
        await trashItemRows(harness.database, 'borrado');

        final videos = await harness.container
            .read(videoTextRepositoryProvider)
            .watchPending()
            .first;

        expect([for (final v in videos) v.sourceId], ['a', 'b']);
        expect(videos.first.head, arabic);
        expect(videos.first.language, 'ar');
        expect(videos.first.title, title);
        // Un texto largo no viaja entero: solo su comienzo.
        expect(videos.last.head, hasLength(kStoredVideoTextHead));
      },
    );

    test(
      'Procesado: el comienzo del texto del documento y el de su fuente',
      () async {
        await saveVideo('v');
        final documentId = await harness.processTextAndNotes('v');

        final videos = await harness.container
            .read(videoTextRepositoryProvider)
            .watchProcessed()
            .first;

        expect(videos.single.documentId, documentId);
        expect(videos.single.sourceId, 'v');
        expect(videos.single.head, arabic);
        expect(videos.single.sourceHead, arabic);
      },
    );
  });

  group('en Procesado', () {
    testWidgets('el documento lo dice, y «Volver a extraer» manda la fuente a '
        'la cola sin el «ar» equivocado y pide traer el texto nuevo al '
        'documento', (tester) async {
      await saveVideo('v');
      final documentId = await harness.processTextAndNotes('v');
      await pumpApp(tester, harness);
      await pushAndSettle(
        tester,
        harness,
        RoutePaths.processedDocument(documentId),
      );

      expect(find.byKey(const Key('foreign-video-text')), findsOneWidget);
      expect(find.text(es.f45S4ForeignTextTitle), findsOneWidget);
      expect(
        find.text(es.f45S4ForeignTextBodyNoSpoken(es.f45S4LanguageName('ar'))),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('foreign-video-text-reextract')));
      await tester.pumpAndSettle();

      expect(harness.queue.enqueued, ['v']);
      expect(await languageOf('v'), isNull);
      expect(harness.container.read(processedTextRefreshProvider).pending, {
        'v',
      });
      expect(find.text(es.f45S4ReextractStartedProcessed(1)), findsOneWidget);
    });

    testWidgets('si la fuente ya tiene su texto en su idioma, se trae al '
        'documento sin volver a extraer', (tester) async {
      await saveVideo('v', language: 'es');
      final documentId = await harness.processTextAndNotes('v');
      // Se volvió a extraer desde la Biblioteca: la fuente ya está bien.
      await saveVideo('v', text: spanish, language: 'es');
      await pumpApp(tester, harness);
      await pushAndSettle(
        tester,
        harness,
        RoutePaths.processedDocument(documentId),
      );

      await tester.tap(find.byKey(const Key('foreign-video-text-reextract')));
      await tester.pumpAndSettle();

      expect(harness.queue.enqueued, isEmpty);
      expect(find.byKey(const Key('foreign-video-text')), findsNothing);
      expect(await textOf(documentId), [spanish]);
    });

    testWidgets('la lista ofrece volver a extraer todos de una vez', (
      tester,
    ) async {
      await saveVideo('a');
      await saveVideo('b');
      await harness.processTextAndNotes('a');
      await harness.processTextAndNotes('b');
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.processed);

      expect(find.text(es.f45S4ForeignTextsBanner(2)), findsOneWidget);
      await tester.tap(find.byKey(const Key('foreign-video-texts-reextract')));
      await tester.pumpAndSettle();

      expect(harness.queue.enqueued, unorderedEquals(['a', 'b']));
    });
  });

  group('en la Bandeja', () {
    testWidgets('la tarjeta lo ofrece; la franja, para los demás, todos de '
        'una vez', (tester) async {
      await saveVideo('a', at: now);
      await saveVideo('b', at: now.add(const Duration(minutes: 1)));
      await saveVideo(
        'bien',
        text: spanish,
        language: 'es',
        at: now.add(const Duration(minutes: 2)),
      );
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.inbox);

      // La tarjeta de arriba es la de «a»: la ofrece ella.
      expect(find.byKey(const Key('foreign-video-text')), findsOneWidget);
      // La franja cuenta los dos, y no el que está bien.
      expect(find.text(es.f45S4ForeignTextsBanner(2)), findsOneWidget);

      await tester.tap(find.byKey(const Key('foreign-video-texts-reextract')));
      await tester.pumpAndSettle();

      expect(harness.queue.enqueued, unorderedEquals(['a', 'b']));
      expect(find.text(es.f45S4ReextractStarted(2)), findsOneWidget);
      // En la Bandeja no hay documento que actualizar.
      expect(
        harness.container.read(processedTextRefreshProvider).pending,
        isEmpty,
      );
    });

    testWidgets('con uno solo, lo ofrece la tarjeta y no hay franja', (
      tester,
    ) async {
      await saveVideo('a', language: 'es');
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.inbox);

      expect(find.byKey(const Key('foreign-video-text')), findsOneWidget);
      expect(find.byKey(const Key('foreign-video-texts-banner')), findsNothing);
      await tester.tap(find.byKey(const Key('foreign-video-text-reextract')));
      await tester.pumpAndSettle();

      expect(harness.queue.enqueued, ['a']);
      // El idioma bien guardado se conserva.
      expect(await languageOf('a'), 'es');
    });
  });

  testWidgets('en un teléfono con la letra al doble, el aviso del documento y '
      'la franja de la lista no desbordan, en claro y en oscuro', (
    tester,
  ) async {
    await saveVideo('a', at: now);
    await saveVideo('b', at: now.add(const Duration(minutes: 1)));
    final documentId = await harness.processTextAndNotes('a');
    await harness.processTextAndNotes('b');
    for (final choice in [AppThemeChoice.light, AppThemeChoice.dark]) {
      await harness.container
          .read(themeChoiceNotifierProvider.notifier)
          .setChoice(choice);
      await pumpPhoneWithLargeText(tester, harness);
      await goAndSettle(tester, harness, RoutePaths.processed);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('foreign-video-texts-banner')),
        findsOneWidget,
      );

      await pushAndSettle(
        tester,
        harness,
        RoutePaths.processedDocument(documentId),
      );
      expect(tester.takeException(), isNull);
      // Con la letra al doble, la tarjeta de la fuente ocupa la pantalla: el
      // aviso está debajo, y la lista lo arma al llegar.
      await tester.scrollUntilVisible(
        find.byKey(const Key('foreign-video-text')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('foreign-video-text')), findsOneWidget);
    }
  });
}
