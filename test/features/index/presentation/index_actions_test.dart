import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/index/domain/repositories/index_document_access.dart';
import 'package:sinapsis/features/index/presentation/index_actions.dart';
import 'package:sinapsis/features/index/presentation/providers/index_view.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_rows.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/fake_index_repository.dart';
import 'screens/index_screen_harness.dart';

/// Lo que se hace con una entrada o un documento del Índice al mantenerlo
/// apretado (F46, paso 4): la hoja común, «Abrir en el original» en su
/// página o en su título, «Preguntar al chat» con su texto, «Copiar el
/// título», «Renombrar» una imagen, y lo mismo desde el teclado, el clic
/// derecho y el lector de pantalla.
void main() {
  final es = AppLocalizationsEs();
  late FakeIndexRepository repo;
  late IndexScreenHarness harness;

  setUp(() {
    repo = FakeIndexRepository();
    harness = IndexScreenHarness(repo);
  });
  tearDown(() => repo.dispose());

  /// Tres documentos sin tema: un libro de texto, un PDF con marcadores y una
  /// página web con dos «Referencias»; uno con «Texto completo» y una galería.
  ///
  /// Sin copia del original en Procesado —[historia], [atlas] o [web] en
  /// `null`—, cada uno puede tener su fuente en la Biblioteca en [sources]
  /// (F46, paso 5c).
  void library({
    IndexOriginalKind? historia = IndexOriginalKind.other,
    IndexOriginalKind? atlas = IndexOriginalKind.pdf,
    IndexOriginalKind? web = IndexOriginalKind.webPage,
    Map<String, IndexLibrarySource> sources = const {},
  }) {
    repo.documents.addAll([
      indexDocument('historia', 'Historia de Roma', chapters: 3, images: 1),
      indexDocument('atlas', 'Atlas', chapters: 2),
      indexDocument(
        'web',
        'Roma en la web',
        kind: SourceKind.webPage,
        chapters: 3,
      ),
      indexDocument('suelto', 'Apuntes sueltos'),
    ]);
    repo.entries['historia'] = [
      ...indexChapters('historia', [
        (1, 'La Monarquía'),
        (2, 'Rómulo'),
        (1, 'La República'),
      ]),
      indexImage('historia', 9, position: 0, title: 'El Foro'),
    ];
    repo.entries['atlas'] = indexChapters(
      'atlas',
      [(1, 'Mapas'), (2, 'El Lacio')],
      firstKey: 20,
      pdf: true,
    );
    repo.entries['web'] = indexChapters('web', [
      (1, 'Referencias'),
      (1, 'Historia'),
      (1, 'Referencias'),
    ], firstKey: 30);
    repo.entries['suelto'] = [indexWholeText('suelto', 40)];
    harness.documents.facts.addAll({
      'historia': (
        title: 'Historia de Roma',
        original: historia,
        source: sources['historia'],
      ),
      'atlas': (title: 'Atlas', original: atlas, source: sources['atlas']),
      'web': (title: 'Roma en la web', original: web, source: sources['web']),
      'suelto': (
        title: 'Apuntes sueltos',
        original: null,
        source: sources['suelto'],
      ),
    });
    // Cada capítulo empieza en i * 100: «Rómulo» en 100, «La República» en
    // 200. Su texto es Markdown, como el de una página web: empieza con su
    // título y lleva un enlace con su dirección (F46, paso 5e).
    harness.documents.texts['historia'] =
        '${'M' * 99}\n'
        '${'## Rómulo\n[Rómulo](https://es.wikipedia.org/wiki/R%C3%B3mulo) '
            'fundó **Roma**.'.padRight(100)}'
        'La República.';
    harness.documents.texts['suelto'] = 'Unos apuntes sin títulos.';
  }

  Finder documentRow(String id) => find.byWidgetPredicate(
    (w) => w is IndexDocumentRow && w.document.id == id,
  );

  Future<void> unfold(WidgetTester tester, String id) async {
    await tester.tap(documentRow(id));
    await tester.pumpAndSettle();
  }

  Future<void> holdOn(WidgetTester tester, String title) async {
    await tester.longPress(indexEntry(title));
    await tester.pumpAndSettle();
  }

  ListTile tile(WidgetTester tester, String key) =>
      tester.widget<ListTile>(find.byKey(Key(key)));

  String detailOf(WidgetTester tester, String key) =>
      (tile(tester, key).subtitle! as Text).data!;

  Future<void> choose(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

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

  group('la hoja de un capítulo', () {
    testWidgets('mantenerlo apretado abre la hoja común con lo que es, su '
        'página y su documento, y lo que se puede hacer', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');
      await holdOn(tester, 'Rómulo');

      expect(find.byKey(const Key('reading-more-sheet')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('reading-more-title'))).data,
        'Rómulo',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('reading-more-kind'))).data,
        '${es.f46P4KindChapter(2)} · ${es.f46P3TextPage(2)} · '
        'Historia de Roma',
      );
      for (final key in [
        'index-action-open-original',
        'index-action-ask-chat',
        'index-action-copy',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.byKey(const Key('index-action-rename')), findsNothing);
      expect(harness.documents.asked, ['historia']);
    });

    testWidgets('«Copiar el título» lleva su numeración si se numera, y lo '
        'avisa', (tester) async {
      library();
      final copied = listenClipboard(tester);
      await harness.pump(tester);
      harness.container.read(indexViewProvider.notifier).toggleNumbering();
      await unfold(tester, 'historia');
      await holdOn(tester, 'Rómulo');
      expect(
        tester.widget<Text>(find.byKey(const Key('reading-more-title'))).data,
        '1.1 Rómulo',
      );

      await choose(tester, 'index-action-copy');
      expect(copied, ['1.1 Rómulo']);
      expect(find.text(es.f46P4Copied), findsOneWidget);
    });

    testWidgets('«Abrir en el original» de un PDF: en la página del '
        'marcador', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'atlas');
      await holdOn(tester, 'El Lacio');
      expect(
        detailOf(tester, 'index-action-open-original'),
        es.f46P4OriginalPdfPage(11),
      );

      await choose(tester, 'index-action-open-original');
      expect(
        find.text('original /processed/atlas/original?page=11'),
        findsOneWidget,
      );
    });

    testWidgets('«Abrir en el original» de una página web: en su título, el '
        'segundo de los iguales', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'web');
      await tester.longPress(indexEntry('Referencias').last);
      await tester.pumpAndSettle();
      expect(
        detailOf(tester, 'index-action-open-original'),
        es.f46P4OriginalHeading,
      );

      await choose(tester, 'index-action-open-original');
      expect(
        find.text('original /processed/web/original?heading=Referencias&nth=1'),
        findsOneWidget,
      );
    });

    testWidgets('«Abrir en el original» de lo demás —un Word, un EPUB—: '
        'desde el comienzo', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');
      await holdOn(tester, 'La República');
      expect(
        detailOf(tester, 'index-action-open-original'),
        es.f46P4OriginalStart,
      );
      await choose(tester, 'index-action-open-original');
      expect(
        find.text('original /processed/historia/original'),
        findsOneWidget,
      );
    });

    testWidgets('sin copia del original ni fuente, apagado y diciendo por '
        'qué', (tester) async {
      library(historia: null);
      await harness.pump(tester);
      await unfold(tester, 'historia');
      await holdOn(tester, 'Rómulo');

      expect(tile(tester, 'index-action-open-original').enabled, isFalse);
      expect(
        detailOf(tester, 'index-action-open-original'),
        es.f46P4NoOriginal,
      );
    });

    group('sin copia en Procesado, el original de la Biblioteca (paso 5c)', () {
      IndexLibrarySource source(
        String itemId,
        IndexOriginalKind? original, {
        bool inTrash = false,
      }) => (itemId: itemId, original: original, inTrash: inTrash);

      testWidgets('un PDF: en la página del marcador, en la Biblioteca', (
        tester,
      ) async {
        library(
          atlas: null,
          sources: {'atlas': source('fuente-atlas', IndexOriginalKind.pdf)},
        );
        await harness.pump(tester);
        await unfold(tester, 'atlas');
        await holdOn(tester, 'El Lacio');
        expect(tile(tester, 'index-action-open-original').enabled, isTrue);
        expect(
          detailOf(tester, 'index-action-open-original'),
          es.f46P5cSourcePdfPage(11),
        );

        await choose(tester, 'index-action-open-original');
        expect(
          find.text('biblioteca /library/fuente-atlas/original?page=11'),
          findsOneWidget,
        );
      });

      testWidgets('una página web: en su título, el segundo de los iguales', (
        tester,
      ) async {
        library(
          web: null,
          sources: {'web': source('fuente-web', IndexOriginalKind.webPage)},
        );
        await harness.pump(tester);
        await unfold(tester, 'web');
        await tester.longPress(indexEntry('Referencias').last);
        await tester.pumpAndSettle();
        expect(
          detailOf(tester, 'index-action-open-original'),
          es.f46P5cSourceHeading,
        );

        await choose(tester, 'index-action-open-original');
        expect(
          find.text(
            'biblioteca /library/fuente-web/original?heading=Referencias&nth=1',
          ),
          findsOneWidget,
        );
      });

      testWidgets('un Word o un EPUB: su original, desde el comienzo', (
        tester,
      ) async {
        library(
          historia: null,
          sources: {
            'historia': source('fuente-historia', IndexOriginalKind.other),
          },
        );
        await harness.pump(tester);
        await unfold(tester, 'historia');
        await holdOn(tester, 'Rómulo');
        expect(
          detailOf(tester, 'index-action-open-original'),
          es.f46P5cSourceStart,
        );

        await choose(tester, 'index-action-open-original');
        expect(
          find.text('biblioteca /library/fuente-historia/original'),
          findsOneWidget,
        );
      });

      testWidgets('una fuente sin un original que se lea —un audio—: su '
          'ficha', (tester) async {
        library(
          historia: null,
          sources: {'historia': source('fuente-audio', null)},
        );
        await harness.pump(tester);
        await unfold(tester, 'historia');
        await holdOn(tester, 'Rómulo');
        expect(
          detailOf(tester, 'index-action-open-original'),
          es.f46P5cSourceItem,
        );

        await choose(tester, 'index-action-open-original');
        expect(find.text('ficha /library/fuente-audio'), findsOneWidget);
      });

      testWidgets('con la fuente en la papelera, apagado y diciendo por qué', (
        tester,
      ) async {
        library(
          historia: null,
          sources: {
            'historia': source(
              'fuente-historia',
              IndexOriginalKind.other,
              inTrash: true,
            ),
          },
        );
        await harness.pump(tester);
        await unfold(tester, 'historia');
        await holdOn(tester, 'Rómulo');

        expect(tile(tester, 'index-action-open-original').enabled, isFalse);
        expect(
          detailOf(tester, 'index-action-open-original'),
          es.f46P5cSourceInTrash,
        );
      });

      testWidgets('con copia en Procesado, la copia: la fuente no se usa', (
        tester,
      ) async {
        library(
          sources: {'atlas': source('fuente-atlas', IndexOriginalKind.pdf)},
        );
        await harness.pump(tester);
        await unfold(tester, 'atlas');
        await holdOn(tester, 'El Lacio');
        expect(
          detailOf(tester, 'index-action-open-original'),
          es.f46P4OriginalPdfPage(11),
        );
        await choose(tester, 'index-action-open-original');
        expect(
          find.text('original /processed/atlas/original?page=11'),
          findsOneWidget,
        );
      });

      testWidgets('la hoja del documento: el original de la Biblioteca desde '
          'el comienzo', (tester) async {
        library(
          atlas: null,
          sources: {'atlas': source('fuente-atlas', IndexOriginalKind.pdf)},
        );
        await harness.pump(tester);
        await tester.longPress(documentRow('atlas'));
        await tester.pumpAndSettle();
        expect(
          detailOf(tester, 'index-action-open-original'),
          es.f46P5cSourceStart,
        );
        await choose(tester, 'index-action-open-original');
        expect(
          find.text('biblioteca /library/fuente-atlas/original'),
          findsOneWidget,
        );
      });
    });

    testWidgets('«Preguntar al chat»: una conversación nueva con el capítulo, '
        'su documento y su texto hasta el siguiente de su nivel —como se lee, '
        'sin su título ni la dirección del enlace—, a medio escribir', (
      tester,
    ) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');
      ChatHandoff? handoff;
      harness.container.listen(
        chatHandoffProvider,
        (_, next) => handoff ??= next,
      );
      await holdOn(tester, 'Rómulo');
      await choose(tester, 'index-action-ask-chat');

      expect(find.text('chat'), findsOneWidget);
      expect(handoff?.send, isFalse);
      expect(
        handoff?.question,
        es.f46P4AskDraftChapter(
          'Rómulo',
          'Historia de Roma',
          'Rómulo fundó Roma.',
        ),
      );
    });

    testWidgets('el de un PDF, que no es Markdown, va tal cual, sin el renglón '
        'de su título', (tester) async {
      library();
      harness.documents.texts['atlas'] =
          '${'M' * 99}\nEl Lacio\nUn **llano** [1] al sur.';
      harness.documents.plainTexts.add('atlas');
      await harness.pump(tester);
      await unfold(tester, 'atlas');
      ChatHandoff? handoff;
      harness.container.listen(
        chatHandoffProvider,
        (_, next) => handoff ??= next,
      );
      await holdOn(tester, 'El Lacio');
      await choose(tester, 'index-action-ask-chat');

      expect(
        handoff?.question,
        es.f46P4AskDraftChapter(
          'El Lacio',
          'Atlas',
          'Un **llano** [1] al sur.',
        ),
      );
    });

    testWidgets('sin el texto, no abre el chat: lo avisa', (tester) async {
      library();
      harness.documents.texts.remove('historia');
      await harness.pump(tester);
      await unfold(tester, 'historia');
      await holdOn(tester, 'Rómulo');
      await choose(tester, 'index-action-ask-chat');

      expect(find.text('chat'), findsNothing);
      expect(find.text(es.f46P4AskChatNoText), findsOneWidget);
    });

    testWidgets('un documento que ya no está no abre nada', (tester) async {
      library();
      harness.documents.facts.remove('historia');
      await harness.pump(tester);
      await unfold(tester, 'historia');
      await holdOn(tester, 'Rómulo');

      expect(find.byKey(const Key('reading-more-sheet')), findsNothing);
    });
  });

  group('«Texto completo» y las imágenes', () {
    testWidgets('«Texto completo»: el original y el chat con su comienzo, sin '
        'copiar un título que no tiene', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'suelto');
      ChatHandoff? handoff;
      harness.container.listen(
        chatHandoffProvider,
        (_, next) => handoff ??= next,
      );
      await holdOn(tester, es.f46P3WholeText);

      expect(find.byKey(const Key('index-action-copy')), findsNothing);
      expect(
        detailOf(tester, 'index-action-ask-chat'),
        es.f46P4AskChatDocumentHint,
      );
      await choose(tester, 'index-action-ask-chat');
      expect(
        handoff?.question,
        es.f46P4AskDraftWhole('Apuntes sueltos', 'Unos apuntes sin títulos.'),
      );
    });

    testWidgets('una imagen: «Renombrar» cambia su título en el Índice y lo '
        'avisa; ni el original ni el chat', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');
      await holdOn(tester, 'El Foro');

      expect(find.byKey(const Key('index-action-open-original')), findsNothing);
      expect(find.byKey(const Key('index-action-ask-chat')), findsNothing);
      await choose(tester, 'index-action-rename');
      expect(find.byType(IndexRenameImageDialog), findsOneWidget);

      // Vacío no se guarda: una imagen no se queda sin título.
      await tester.enterText(find.byKey(const Key('index-rename-field')), '  ');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('index-rename-save')))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('index-rename-field')),
        '  El Foro romano ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repo.renamed, {'img-9': 'El Foro romano'});
      expect(find.text(es.f46P4Renamed), findsOneWidget);
    });

    testWidgets('renombrar con el mismo título no escribe nada', (
      tester,
    ) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');
      await holdOn(tester, 'El Foro');
      await choose(tester, 'index-action-rename');
      await tester.tap(find.byKey(const Key('index-rename-save')));
      await tester.pumpAndSettle();
      expect(repo.renamed, isEmpty);
      expect(find.text(es.f46P4Renamed), findsNothing);
    });
  });

  group('la hoja de un documento', () {
    testWidgets('abrir su texto, el original, el chat sobre él y copiar su '
        'título', (tester) async {
      library();
      final copied = listenClipboard(tester);
      await harness.pump(tester);
      await tester.longPress(documentRow('atlas'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('reading-more-title'))).data,
        'Atlas',
      );
      expect(find.byKey(const Key('index-action-open-text')), findsOneWidget);
      expect(
        detailOf(tester, 'index-action-open-original'),
        es.f46P4OriginalStart,
      );
      await choose(tester, 'index-action-copy');
      expect(copied, ['Atlas']);

      await tester.longPress(documentRow('atlas'));
      await tester.pumpAndSettle();
      await choose(tester, 'index-action-open-text');
      expect(find.textContaining('lector /read/full_text'), findsOneWidget);
      expect(find.textContaining('at='), findsNothing);
    });

    testWidgets('«Preguntar al chat» sobre el documento, a medio escribir', (
      tester,
    ) async {
      library();
      await harness.pump(tester);
      ChatHandoff? handoff;
      harness.container.listen(
        chatHandoffProvider,
        (_, next) => handoff ??= next,
      );
      await tester.longPress(documentRow('web'));
      await tester.pumpAndSettle();
      await choose(tester, 'index-action-ask-chat');
      expect(handoff?.question, es.f47P1AskAiDraft('Roma en la web'));
      expect(handoff?.send, isFalse);
    });
  });

  group('para todos', () {
    testWidgets('el clic derecho y Mayús+F10 o la tecla de menú abren lo '
        'mismo', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');

      await tester.tap(indexEntry('Rómulo'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-more-sheet')), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const Key('reading-more-sheet'))),
      ).pop();
      await tester.pumpAndSettle();

      // Con el foco en la fila —el de su `InkWell`—, desde el teclado.
      Focus.of(tester.element(indexEntry('Rómulo'))).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-more-sheet')), findsOneWidget);
    });

    testWidgets('el lector de pantalla oye «Más opciones» en cada fila, y la '
        'acción abre la hoja', (tester) async {
      final semantics = tester.ensureSemantics();
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');

      final node = tester.getSemantics(indexEntry('Rómulo'));
      final data = node.getSemanticsData();
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      final more = data.customSemanticsActionIds!
          .map(CustomSemanticsAction.getAction)
          .where((a) => a?.label == es.f46P4MoreActions);
      expect(more, hasLength(1));
      expect(
        tester
            .getSemantics(
              find
                  .descendant(
                    of: documentRow('historia'),
                    matching: find.byType(Icon),
                  )
                  .first,
            )
            .getSemanticsData()
            .hasAction(SemanticsAction.longPress),
        isTrue,
      );

      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.longPress,
          viewId: tester.view.viewId,
          nodeId: node.id,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-more-sheet')), findsOneWidget);
      semantics.dispose();
    });

    for (final brightness in Brightness.values) {
      testWidgets('a 360 dp con la letra al doble, en ${brightness.name}, la '
          'hoja entra sin desbordes', (tester) async {
        library();
        repo.documents.removeWhere((d) => d.id != 'historia');
        await harness.pump(
          tester,
          size: const Size(360, 780),
          textScale: 2,
          theme: ThemeData(brightness: brightness),
        );
        await unfold(tester, 'historia');
        await tester.ensureVisible(indexEntry('Rómulo'));
        await tester.pumpAndSettle();
        await holdOn(tester, 'Rómulo');
        expect(find.byKey(const Key('reading-more-sheet')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
