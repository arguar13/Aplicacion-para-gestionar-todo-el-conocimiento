import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/quiet_video_player.dart';
import '../../../../support/read_aloud_test_support.dart';

/// El detalle de un elemento con el lector flotante (F25): qué ofrece para
/// leer —la nota del usuario, el texto, una nota de bloques bloque por
/// bloque—, qué pinta de amarillo mientras lee y cuándo deja de ofrecerlo.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 10, 2, 10);
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create(
      extraOverrides: [
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
      ],
    );
  });

  ReadableDocument? offered() =>
      harness.container.read(currentReadableProvider);

  FakeReadAloudController reader() =>
      harness.container.read(readAloudControllerProvider.notifier)
          as FakeReadAloudController;

  /// Guarda un elemento de [kind] con [renditions] y devuelve su
  /// identificador.
  Future<String> save({
    required SourceKind kind,
    required List<Rendition> Function(String id) renditions,
    String? notes,
  }) async {
    const id = 'f25-detalle';
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Para escuchar',
            notes: notes,
            source: Source(id: id, kind: kind, capturedAt: now),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: renditions(id),
          ),
        );
    return id;
  }

  Rendition text(String itemId, String content) => Rendition.text(
    id: '$itemId-texto',
    itemId: itemId,
    kind: RenditionKind.plainText,
    content: content,
    isPrimary: true,
    createdAt: now,
  );

  Future<void> pumpDetail(WidgetTester tester, String id) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness.wrap(ItemDetailScreen(itemId: id)));
    await tester.pumpAndSettle();
  }

  group('con su propio audio no se ofrece: sería un segundo audio de lo '
      'mismo', () {
    /// Un elemento de [kind] con su archivo, que se resuelve como audio:
    /// como un audio o un video del teléfono, o el audio ya bajado de un
    /// YouTube.
    Future<String> saveWithAudio(SourceKind kind) async {
      VideoPlayerPlatform.instance = QuietVideoPlayer();
      harness = await LibraryHarness.create(
        extraOverrides: [
          readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
          resolvedFileViewerProvider.overrideWith(
            (ref, item) async => const MediaResolvedViewer(
              path: '/boveda/archivos/clase.opus',
              isVideo: false,
            ),
          ),
        ],
      );
      const id = 'f25-con-audio';
      await harness.container
          .read(libraryRepositoryProvider)
          .save(
            KnowledgeItem(
              id: id,
              title: 'Una clase grabada',
              source: Source(
                id: id,
                kind: kind,
                capturedAt: now,
                originalFilePath: 'clase.opus',
              ),
              processingState: ProcessingState.ready,
              createdAt: now,
              updatedAt: now,
              renditions: [text(id, '[0:00] hola a todos')],
            ),
          );
      return id;
    }

    testWidgets('un audio con su archivo: el texto ya se escucha con la voz '
        'original', (tester) async {
      final id = await saveWithAudio(SourceKind.audio);
      await pumpDetail(tester, id);

      expect(offered(), isNull);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('un video con su archivo, tampoco', (tester) async {
      final id = await saveWithAudio(SourceKind.video);
      await pumpDetail(tester, id);

      expect(offered(), isNull);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('un YouTube sin el audio bajado sí: no hay otra forma de '
        'escucharlo', (tester) async {
      final id = await save(
        kind: SourceKind.youtube,
        renditions: (id) => [text(id, '[0:00] hola a todos')],
      );
      await pumpDetail(tester, id);

      expect(offered()?.id, 'item:$id');
    });
  });

  testWidgets('ofrece la nota del usuario y después el texto, línea por '
      'línea, con su lugar en cada uno', (tester) async {
    final id = await save(
      kind: SourceKind.webPage,
      notes: 'Mi nota.',
      renditions: (id) => [text(id, 'Primera línea.\n\nSegunda línea.')],
    );

    await pumpDetail(tester, id);

    final document = offered()!;
    expect(document.id, 'item:$id');
    expect(document.title, 'Para escuchar');
    expect(document.segments, [
      ReadableSegment(
        sourceKey: 'note:$id',
        start: 0,
        end: 8,
        spoken: 'Mi nota.',
      ),
      ReadableSegment(
        sourceKey: '$id-texto',
        start: 0,
        end: 14,
        spoken: 'Primera línea.',
      ),
      ReadableSegment(
        sourceKey: '$id-texto',
        start: 16,
        end: 30,
        spoken: 'Segunda línea.',
      ),
    ]);
  });

  testWidgets('la línea que se lee se ve en amarillo: en la nota del usuario '
      'y en el texto, solo esa', (tester) async {
    final id = await save(
      kind: SourceKind.webPage,
      notes: 'Mi nota.',
      renditions: (id) => [text(id, 'Primera línea.\n\nSegunda línea.')],
    );
    await pumpDetail(tester, id);
    expect(readAloudHighlights(tester), isEmpty);

    reader().readAt(offered()!, 0);
    await tester.pump();
    expect(readAloudHighlights(tester), ['Mi nota.']);

    reader().readAt(offered()!, 2);
    await tester.pump();
    expect(readAloudHighlights(tester), ['Segunda línea.']);
  });

  testWidgets('una transcripción se lee sin las marcas de tiempo, y se '
      'resalta el renglón entero', (tester) async {
    final id = await save(
      kind: SourceKind.audio,
      renditions: (id) => [text(id, '[0:00] hola a todos\n[0:05] y chau')],
    );
    await pumpDetail(tester, id);

    final document = offered()!;
    expect(document.segments.map((s) => s.spoken), ['hola a todos', 'y chau']);

    reader().readAt(document, 1);
    await tester.pump();
    expect(readAloudHighlights(tester), ['[0:05] y chau']);
  });

  testWidgets('una nota de bloques se lee bloque por bloque, sin el formato, '
      'y se resalta en su bloque', (tester) async {
    final id = await save(
      kind: SourceKind.manualNote,
      renditions: (id) => [
        Rendition.text(
          id: '$id-bloques',
          itemId: id,
          kind: RenditionKind.blocks,
          content: encodeContentBlocks(const [
            ContentBlock.heading(text: 'Un título'),
            ContentBlock.paragraph(text: 'Un **párrafo** firme.'),
          ]),
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
    await pumpDetail(tester, id);

    final document = offered()!;
    expect(document.segments, [
      ReadableSegment(
        sourceKey: 'blocks:$id-bloques:0',
        start: 0,
        end: 9,
        spoken: 'Un título',
      ),
      ReadableSegment(
        sourceKey: 'blocks:$id-bloques:1',
        start: 0,
        end: 21,
        spoken: 'Un párrafo firme.',
      ),
    ]);

    reader().readAt(document, 1);
    await tester.pump();
    expect(readAloudHighlights(tester), ['Un párrafo firme.']);
  });

  testWidgets('el texto plegado de un documento se ofrece recién al '
      'desplegarlo, y deja de ofrecerse al plegarlo', (tester) async {
    final id = await save(
      kind: SourceKind.document,
      notes: 'Mi nota.',
      renditions: (id) => [text(id, 'Lo que dice el documento.')],
    );
    await pumpDetail(tester, id);
    expect(offered()!.segments.map((s) => s.spoken), ['Mi nota.']);

    await tester.tap(find.text(es.detailExtractedTextTitle));
    await tester.pumpAndSettle();
    expect(offered()!.id, 'item:$id');
    expect(offered()!.segments.map((s) => s.spoken), [
      'Mi nota.',
      'Lo que dice el documento.',
    ]);

    await tester.tap(find.text(es.detailExtractedTextTitle));
    await tester.pumpAndSettle();
    expect(offered()!.segments.map((s) => s.spoken), ['Mi nota.']);
  });

  testWidgets('tapado por otra pantalla deja de ofrecerse, y vuelve al '
      'volver; al salir, nada', (tester) async {
    final id = await save(
      kind: SourceKind.webPage,
      renditions: (id) => [text(id, 'Algo para leer.')],
    );
    await pumpDetail(tester, id);
    expect(offered()?.id, 'item:$id');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold())),
    );
    await tester.pumpAndSettle();
    expect(offered(), isNull);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(offered()?.id, 'item:$id');

    await tester.pumpWidget(harness.wrap(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(offered(), isNull);
    // Lo que el detalle deja programado al cerrarse termina antes de que
    // termine la prueba.
    await tester.pump(const Duration(seconds: 1));
  });
}
