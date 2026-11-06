import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/design/widgets/adaptive_button_bar.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_dock.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import 'extract_harness.dart';

/// Los visores de Extraer texto completo, resumen y síntesis (F43, paso 7;
/// M8): vistas vivas sobre las marcas del documento, lo que falta marcado con
/// la máquina del original, «Resaltar las palabras clave» como la misma
/// preferencia y el modo escuchar con el amarillo en vivo.
void main() {
  final es = AppLocalizationsEs();
  final pink = StudyPalette.of(Brightness.light).keyword;
  const yellow = RenderedMarkdown.playingColor;
  const roma =
      'La república romana cayó. César cruzó el Rubicón.\n\n'
      'Aníbal cruzó los Alpes. Escipión volvió a Roma.';
  late ExtractHarness h;

  setUp(() async => h = await ExtractHarness.create());

  /// Lo que se ve en el visor, en texto.
  String shown(WidgetTester tester) => [
    for (final rich in tester.widgetList<RichText>(
      find.descendant(
        of: find.byKey(const Key('extract-viewer-list')),
        matching: find.byType(RichText),
      ),
    ))
      rich.text.toPlainText(),
  ].join('\n');

  /// Dónde se ve, en la pantalla, el renglón donde empieza [passage].
  Rect lineOf(WidgetTester tester, String passage) {
    final rich = find.textContaining(passage, findRichText: true);
    expect(rich, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(rich);
    final at = paragraph.text.toPlainText().indexOf(passage);
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: at, extentOffset: at + passage.length),
        )
        .first
        .toRect();
    return box.shift(paragraph.localToGlobal(Offset.zero));
  }

  Future<String> romaWithSummary() async {
    final id = await h.document('roma', title: 'Roma', text: roma);
    await h.mark(id, 'César cruzó el Rubicón.');
    await h.mark(id, 'Escipión volvió a Roma.');
    await h.mark(id, 'César', kind: StudyMarkKind.keyword);
    return id;
  }

  /// Edita la página de [id] que dice [from], como desde el documento: con
  /// [to] en su lugar.
  Future<void> editPage(String id, String from, String to) async {
    final repository = h.container.read(processedRepositoryProvider);
    final parts = (await repository.partsOf(id)).getRight().toNullable()!;
    final page = parts.firstWhere((p) => p.content.contains(from));
    final edited = await repository.editPart(
      page.id,
      page.content.replaceFirst(from, to),
    );
    expect(edited.isRight(), isTrue, reason: '$edited');
  }

  group('la lectura, una vista viva (decisión E)', () {
    testWidgets('el resumen: las oraciones marcadas en el documento, en '
        'orden, con el título arriba y las palabras clave en rosa; creado '
        'por la cola de verdad, queda lista enseguida', (tester) async {
      final id = await romaWithSummary();
      final creation = await h.creation(StudyCreationKind.summary, [id]);
      expect(creation.kind.isLiveView, isTrue);
      await h.open(tester, creation);

      expect(find.byKey(const Key('extract-viewer-summary')), findsOneWidget);
      expect(find.byKey(Key('extract-title-$id')), findsOneWidget);
      final text = shown(tester);
      expect(text, contains('César cruzó el Rubicón.'));
      expect(text, contains('Escipión volvió a Roma.'));
      expect(text, isNot(contains('república')));
      expect(text.indexOf('César'), lessThan(text.indexOf('Escipión')));
      expect(paintedWith(tester, pink), ['César']);
      expect(find.byKey(Key('extract-missing-$id')), findsNothing);
    });

    testWidgets('si se marca algo más en el documento —como desde el '
        'original—, aparece solo', (tester) async {
      final id = await romaWithSummary();
      final creation = await h.creation(StudyCreationKind.summary, [id]);
      await h.open(tester, creation);
      expect(shown(tester), isNot(contains('Aníbal')));

      await h.mark(id, 'Aníbal cruzó los Alpes.');
      await tester.pumpAndSettle();
      expect(shown(tester), contains('Aníbal cruzó los Alpes.'));
    });

    testWidgets('si se edita una página del documento, el texto completo '
        'abierto cambia solo', (tester) async {
      final id = await romaWithSummary();
      final full = await h.creation(StudyCreationKind.fullText, [id]);
      await h.open(tester, full);
      expect(shown(tester), contains('Escipión volvió a Roma.'));

      await editPage(id, 'Escipión', 'Escipión el Africano');
      await tester.pumpAndSettle();
      expect(shown(tester), contains('Escipión el Africano volvió a Roma.'));
    });

    testWidgets('las ediciones que caen en el mismo segundo que lo anterior '
        'también se ven: el cambio se sigue por la versión del documento, no '
        'por su hora —que se guarda en segundos—', (tester) async {
      h.frozenAt = DateTime(2026, 10, 29, 12);
      final id = await romaWithSummary();
      final full = await h.creation(StudyCreationKind.fullText, [id]);
      await h.open(tester, full);
      expect(shown(tester), contains('Escipión volvió a Roma.'));

      await editPage(id, 'Escipión', 'Escipión el Africano');
      await tester.pumpAndSettle();
      expect(shown(tester), contains('Escipión el Africano volvió a Roma.'));

      await editPage(id, 'Aníbal', 'Aníbal Barca');
      await tester.pumpAndSettle();
      expect(shown(tester), contains('Aníbal Barca cruzó los Alpes.'));
    });

    testWidgets('el texto completo: entero, con las palabras clave en rosa '
        'en cualquier oración', (tester) async {
      final id = await romaWithSummary();
      await h.mark(id, 'Alpes', kind: StudyMarkKind.keyword);
      final creation = await h.creation(StudyCreationKind.fullText, [id]);
      await h.open(tester, creation);

      final text = shown(tester);
      expect(text, contains('La república romana cayó.'));
      expect(text, contains('Escipión volvió a Roma.'));
      expect(paintedWith(tester, pink), ['César', 'Alpes']);
    });

    testWidgets('con varios documentos, cada uno con su título como '
        'encabezado, en el orden de la creación', (tester) async {
      final a = await romaWithSummary();
      final b = await h.document(
        'grecia',
        title: 'Grecia',
        text: 'Atenas inventó la democracia. Esparta prefería la guerra.',
      );
      await h.mark(b, 'Esparta prefería la guerra.');
      final creation = await h.creation(StudyCreationKind.summary, [b, a]);
      await h.open(tester, creation);

      final grecia = tester.getTopLeft(find.byKey(Key('extract-title-$b')));
      final romaTitle = tester.getTopLeft(find.byKey(Key('extract-title-$a')));
      expect(grecia.dy, lessThan(romaTitle.dy));
      final text = shown(tester);
      expect(text.indexOf('Esparta'), lessThan(text.indexOf('César')));
    });
  });

  group('lo que falta, con la máquina del original (M5, M8)', () {
    testWidgets('sin resumen lo dice; «Marcar con IA» muestra lo que '
        'consume y, al confirmar, el análisis de siempre marca el documento '
        'mismo y el visor se llena solo', (tester) async {
      h.modelReady = false; // Al crearla, la cola no puede analizar.
      final id = await h.document('roma', title: 'Roma', text: roma);
      final creation = await h.creation(StudyCreationKind.synthesis, [id]);
      h.modelReady = true;
      // Lo oculto en el original se vuelve a mostrar: lo que se pidió ver.
      await h.container
          .read(processedOriginalHiddenProvider(id).notifier)
          .setHidden(StudyMarkKind.synthesis, hidden: true);
      await h.open(tester, creation);

      expect(find.byKey(Key('extract-missing-$id')), findsOneWidget);
      expect(find.text(es.f43TextMissingSynthesis), findsOneWidget);
      expect(h.marker.parts, 0);

      await tester.tap(find.byKey(Key('extract-mark-$id')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('extract-mark-sheet')), findsOneWidget);
      expect(find.byKey(const Key('ai-capability-card')), findsOneWidget);

      await tester.tap(find.byKey(const Key('extract-mark-confirm')));
      await tester.pumpAndSettle();

      expect(h.marker.parts, greaterThan(0));
      final study = await h.study(id);
      // En las marcas del documento —la clave del procesado—: la única
      // fuente, la misma que lee el original.
      expect(study.of(StudyMarkKind.synthesis), isNotEmpty);
      expect((await h.own(id)).key, processedStudyKeyFor(id));
      expect(
        h.container.read(processedOriginalHiddenProvider(id)),
        isNot(contains(StudyMarkKind.synthesis)),
      );
      expect(find.byKey(Key('extract-missing-$id')), findsNothing);
      expect(shown(tester), contains('César cruzó el Rubicón.'));
    });

    testWidgets('con varios sin resumen, el aviso de arriba los marca a '
        'todos, de a uno', (tester) async {
      h.modelReady = false;
      final a = await h.document('roma', title: 'Roma', text: roma);
      final b = await h.document(
        'grecia',
        title: 'Grecia',
        text: 'Atenas inventó la democracia. Esparta prefería la guerra.',
      );
      final creation = await h.creation(StudyCreationKind.summary, [a, b]);
      h.modelReady = true;
      await h.open(tester, creation);

      expect(find.byKey(const Key('extract-missing-banner')), findsOneWidget);
      expect(find.text(es.f43TextMissingSeveralSummary(2)), findsOneWidget);
      await tester.tap(find.byKey(const Key('extract-mark-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('extract-mark-confirm')));
      await tester.pumpAndSettle();

      expect((await h.study(a)).of(StudyMarkKind.summary), isNotEmpty);
      expect((await h.study(b)).of(StudyMarkKind.summary), isNotEmpty);
      expect(find.byKey(const Key('extract-missing-banner')), findsNothing);
      final text = shown(tester);
      expect(text, contains('La república romana cayó.'));
      expect(text, contains('Atenas inventó la democracia.'));
    });

    testWidgets('un documento que se borró dice «Fuente borrada»', (
      tester,
    ) async {
      final id = await romaWithSummary();
      final creation = await h.creation(StudyCreationKind.summary, [
        id,
        'no-existe',
      ]);
      await h.open(tester, creation);

      expect(
        find.byKey(const Key('extract-deleted-no-existe')),
        findsOneWidget,
      );
      expect(find.text(es.f43StudioSourceDeleted), findsWidgets);
      expect(shown(tester), contains('César cruzó el Rubicón.'));
    });
  });

  group('«Palabras clave» en la fila de IA (F47, paso 1): la misma '
      'preferencia del original (M8)', () {
    Future<void> tapKeywords(WidgetTester tester) async {
      // La fila de IA se desplaza de costado: se la lleva a la vista.
      await tester.ensureVisible(
        find.byKey(const Key('extract-study-keyword')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('extract-study-keyword')));
      await tester.pumpAndSettle();
    }

    String state(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('extract-study-keyword')),
            matching: find.byKey(const Key('original-study-state-keyword')),
          ),
        )
        .data!;

    testWidgets('a la vista por defecto; tocarla la oculta en el documento, '
        'y mostrarla allá la muestra acá', (tester) async {
      final id = await romaWithSummary();
      final creation = await h.creation(StudyCreationKind.summary, [id]);
      await h.open(tester, creation);
      expect(state(tester), es.f43OrigStateDone('keyword'));

      await tapKeywords(tester);
      expect(h.container.read(processedKeywordsShownProvider(id)), isFalse);
      expect(
        h.container
            .read(sharedPreferencesProvider)
            .getStringList(OriginalLayers.processedKeyOf(id)),
        [StudyMarkKind.keyword.name],
      );
      expect(state(tester), es.f43OrigStateHidden('keyword'));
      expect(paintedWith(tester, pink), isEmpty);

      // Desde el original (M5): el mismo lugar.
      await h.container
          .read(processedOriginalHiddenProvider(id).notifier)
          .setHidden(StudyMarkKind.keyword, hidden: false);
      await tester.pumpAndSettle();
      expect(state(tester), es.f43OrigStateDone('keyword'));
      expect(paintedWith(tester, pink), ['César']);
    });

    testWidgets('con varios documentos se cambia en todos', (tester) async {
      final a = await romaWithSummary();
      final b = await h.document(
        'grecia',
        title: 'Grecia',
        text: 'Atenas inventó la democracia. Esparta prefería la guerra.',
      );
      await h.mark(b, 'Esparta prefería la guerra.');
      final creation = await h.creation(StudyCreationKind.summary, [a, b]);
      await h.open(tester, creation);

      await tapKeywords(tester);
      expect(h.container.read(processedKeywordsShownProvider(a)), isFalse);
      expect(h.container.read(processedKeywordsShownProvider(b)), isFalse);
    });
  });

  group('el modo escuchar (M8, decisión 86)', () {
    testWidgets('«Escuchar» abre el reproductor anclado de toda la app y lee '
        'lo que se ve; lo que suena va en amarillo con el rosa encima, y '
        'avanza con la voz', (tester) async {
      final id = await romaWithSummary();
      final creation = await h.creation(StudyCreationKind.summary, [id]);
      await h.open(tester, creation, withReadAloud: true);
      final player = find.byKey(const Key('read-aloud-player'));
      expect(player, findsNothing);

      await tester.tap(find.byKey(const Key('reading-listen')));
      await tester.pumpAndSettle();

      expect(player, findsOneWidget);
      expect(h.tts.spoken, ['César cruzó el Rubicón.']);
      // El amarillo en la oración que suena; la palabra clave, rosa encima.
      expect(paintedWith(tester, yellow).join(), ' cruzó el Rubicón.');
      expect(paintedWith(tester, pink), ['César']);
      // Uno solo: en el marco no va el botón flotante, y el reproductor es
      // el de toda la app.
      expect(h.container.read(readAloudDockProvider), isNotEmpty);
      expect(find.byKey(const Key('read-aloud-button')), findsNothing);

      h.tts.completeCurrent();
      await tester.pumpAndSettle();
      expect(h.tts.spoken.last, 'Escipión volvió a Roma.');
      expect(paintedWith(tester, yellow).join(), 'Escipión volvió a Roma.');

      await tester.tap(find.byKey(const Key('read-aloud-play')));
      await tester.pumpAndSettle();
      expect(h.container.read(readAloudControllerProvider).playing, isFalse);

      await h.container.read(readAloudControllerProvider.notifier).close();
      await tester.pumpAndSettle();
      expect(player, findsNothing);
      expect(paintedWith(tester, yellow), isEmpty);
    });

    testWidgets('con varios documentos dice el título de cada uno antes de '
        'leerlo, y lo resalta', (tester) async {
      final a = await romaWithSummary();
      final b = await h.document(
        'grecia',
        title: 'Grecia',
        text: 'Atenas inventó la democracia. Esparta prefería la guerra.',
      );
      await h.mark(b, 'Esparta prefería la guerra.');
      final creation = await h.creation(StudyCreationKind.summary, [b, a]);
      await h.open(tester, creation);

      await tester.tap(find.byKey(const Key('reading-listen')));
      await tester.pumpAndSettle();
      expect(h.tts.spoken, ['Grecia']);
      expect(
        paintedWith(
          tester,
          yellow,
          within: find.byKey(Key('extract-title-$b')),
        ),
        ['Grecia'],
      );
      h.tts.completeCurrent();
      await tester.pumpAndSettle();
      expect(h.tts.spoken.last, 'Esparta prefería la guerra.');
    });

    testWidgets('la lista acompaña sola a lo que suena, aunque esté lejos: '
        'salta, sin animación', (tester) async {
      final paragraphs = [
        for (var i = 0; i < 60; i++)
          'Párrafo $i dice algo largo sobre Roma y su historia, con texto.',
      ];
      final id = await h.document(
        'larga',
        title: 'Larga',
        text: paragraphs.join('\n\n'),
      );
      final creation = await h.creation(StudyCreationKind.fullText, [id]);
      await h.open(tester, creation, size: const Size(400, 800));

      await tester.tap(find.byKey(const Key('reading-listen')));
      await tester.pumpAndSettle();
      final controller = h.container.read(readAloudControllerProvider.notifier);
      await controller.seekToSegment(55);
      await tester.pumpAndSettle();

      final list = tester.getRect(find.byKey(const Key('extract-viewer-list')));
      final line = lineOf(tester, 'Párrafo 55 dice');
      expect(line.top, greaterThanOrEqualTo(list.top));
      expect(line.bottom, lessThan(list.top + list.height * 0.7));
      expect(paintedWith(tester, yellow).join(), startsWith('Párrafo 55 dice'));
    });

    group('«Escuchar» empieza por lo que se ve (F46, paso 5f)', () {
      /// Un texto completo de 60 párrafos —una oración cada uno—, abierto en
      /// un teléfono.
      Future<void> openLong(WidgetTester tester) async {
        final id = await h.document(
          'larga',
          title: 'Larga',
          text: [
            for (var i = 0; i < 60; i++)
              'Párrafo $i dice algo largo sobre Roma, con texto.',
          ].join('\n\n'),
        );
        final creation = await h.creation(StudyCreationKind.fullText, [id]);
        await h.open(tester, creation, size: const Size(400, 800));
      }

      final list = find.byKey(const Key('extract-viewer-list'));

      /// El número de la oración «[word] N» que está en la primera línea a la
      /// vista, arriba de la lista, aunque la línea esté cortada.
      int shownAtTop(WidgetTester tester, [String word = 'Párrafo']) {
        final top = tester.getRect(list).top;
        final texts = find.descendant(
          of: list,
          matching: find.byType(RichText),
        );
        for (final element in texts.evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          final origin = paragraph.localToGlobal(Offset.zero);
          if (origin.dy + paragraph.size.height <= top) continue;
          final dy = (top - origin.dy).clamp(0.0, paragraph.size.height);
          final at = paragraph.getPositionForOffset(Offset(0, dy)).offset;
          // La primera oración que termina después de esa línea —como
          // `ReadableDocument.startIndexOf`—: si la línea de arriba es la
          // vacía entre dos párrafos, la del siguiente.
          final sentences = RegExp(
            '$word (\\d+)[^.]*\\.',
          ).allMatches(paragraph.text.toPlainText()).where((m) => m.end > at);
          if (sentences.isEmpty) continue;
          return int.parse(sentences.first[1]!);
        }
        fail('no se ve ninguna oración');
      }

      /// Baja la lista [dy], como con el dedo.
      Future<void> scrollBy(WidgetTester tester, double dy) async {
        final scroll = tester.widget<ListView>(list).controller!;
        scroll.jumpTo(scroll.offset + dy);
        await tester.pumpAndSettle();
      }

      testWidgets('desplazado hasta la mitad, lee desde el párrafo de '
          'arriba, no desde el comienzo', (tester) async {
        await openLong(tester);
        await scrollBy(tester, 2400);
        final shown = shownAtTop(tester);
        expect(shown, greaterThan(10));

        await tester.tap(find.byKey(const Key('reading-listen')));
        await tester.pumpAndSettle();

        expect(h.tts.spoken.first, startsWith('Párrafo $shown dice'));
        expect(
          h.container.read(readAloudControllerProvider).segmentIndex,
          shown,
        );
      });

      testWidgets('en un párrafo largo cortado arriba, desde la oración de la '
          'línea de arriba, no desde el comienzo del párrafo', (tester) async {
        final id = await h.document(
          'un-parrafo',
          title: 'Un párrafo',
          text: [
            for (var i = 0; i < 80; i++)
              'Oración $i del mismo párrafo larguísimo sobre Roma.',
          ].join(' '),
        );
        final creation = await h.creation(StudyCreationKind.fullText, [id]);
        await h.open(tester, creation, size: const Size(400, 800));
        await scrollBy(tester, 2000);

        // La oración de la primera línea que se ve, entera o cortada.
        final shown = shownAtTop(tester, 'Oración');
        expect(shown, greaterThan(10));

        await tester.tap(find.byKey(const Key('reading-listen')));
        await tester.pumpAndSettle();

        expect(h.tts.spoken.first, startsWith('Oración $shown del'));
      });

      testWidgets('con varios documentos, pasado el título del segundo, desde '
          'su línea de arriba y no desde su título', (tester) async {
        final a = await h.document(
          'corto',
          title: 'Corto',
          text: 'Párrafo 0 dice poco.',
        );
        final b = await h.document(
          'largo',
          title: 'Largo',
          text: [
            for (var i = 0; i < 80; i++)
              'Oración $i del mismo párrafo larguísimo sobre Roma.',
          ].join(' '),
        );
        final creation = await h.creation(StudyCreationKind.fullText, [a, b]);
        await h.open(tester, creation, size: const Size(400, 800));
        // El título del segundo queda arriba, fuera de la vista pero todavía
        // armado: la vista empieza un poco más abajo, en su texto.
        final header = tester.getRect(
          find.byKey(ValueKey('extract-header-$b')),
        );
        await scrollBy(tester, header.bottom - tester.getRect(list).top + 120);
        expect(
          tester.any(
            find.byKey(ValueKey('extract-header-$b'), skipOffstage: false),
          ),
          isTrue,
        );
        final shown = shownAtTop(tester, 'Oración');

        await tester.tap(find.byKey(const Key('reading-listen')));
        await tester.pumpAndSettle();

        expect(h.tts.spoken.first, startsWith('Oración $shown del'));
      });

      testWidgets('en el resumen, que muestra solo lo marcado, desde la '
          'oración marcada de arriba', (tester) async {
        final sentences = [
          for (var i = 0; i < 80; i++)
            'Oración $i del mismo párrafo larguísimo sobre Roma.',
        ];
        final id = await h.document(
          'marcado',
          title: 'Marcado',
          text: sentences.join(' '),
        );
        // La mitad, salteada: entre lo que se ve hay texto que no se ve.
        for (var i = 0; i < 80; i += 2) {
          await h.mark(id, sentences[i]);
        }
        final creation = await h.creation(StudyCreationKind.summary, [id]);
        await h.open(tester, creation, size: const Size(400, 800));
        await scrollBy(tester, 1500);
        final shown = shownAtTop(tester, 'Oración');
        expect(shown, greaterThan(10));

        await tester.tap(find.byKey(const Key('reading-listen')));
        await tester.pumpAndSettle();

        expect(h.tts.spoken.first, startsWith('Oración $shown del'));
      });

      testWidgets('arriba de todo, desde el comienzo', (tester) async {
        await openLong(tester);

        await tester.tap(find.byKey(const Key('reading-listen')));
        await tester.pumpAndSettle();

        expect(h.tts.spoken.first, startsWith('Párrafo 0 dice'));
      });

      testWidgets('con el reproductor abierto y en pausa, ofrecerlo otra vez '
          'sigue donde iba; cerrado, «Escuchar» lee desde lo que se ve', (
        tester,
      ) async {
        await openLong(tester);
        await tester.tap(find.byKey(const Key('reading-listen')));
        await tester.pumpAndSettle();
        final controller = h.container.read(
          readAloudControllerProvider.notifier,
        );
        await controller.pause();
        await tester.pumpAndSettle();
        // La lista ya no sigue la lectura: la persona se fue a otro lado.
        await scrollBy(tester, 2400);
        final shown = shownAtTop(tester);
        expect(shown, greaterThan(10));

        await controller.open(h.container.read(currentReadableProvider)!);
        await tester.pumpAndSettle();
        expect(h.container.read(readAloudControllerProvider).segmentIndex, 0);

        await controller.close();
        await tester.pumpAndSettle();
        final after = shownAtTop(tester);
        await tester.tap(find.byKey(const Key('reading-listen')));
        await tester.pumpAndSettle();
        expect(
          h.container.read(readAloudControllerProvider).segmentIndex,
          after,
        );
        expect(h.tts.spoken.last, startsWith('Párrafo $after dice'));
      });
    });
  });

  testWidgets('el texto se desplaza con la física de la plataforma: un '
      'arrastre corto ya no baja de golpe (F45, mejora 13)', (tester) async {
    final id = await romaWithSummary();
    final creation = await h.creation(StudyCreationKind.fullText, [id]);
    await h.open(tester, creation);
    expect(
      tester
          .widget<ListView>(find.byKey(const Key('extract-viewer-list')))
          .physics,
      isNull,
    );
  });

  group('el archivo', () {
    testWidgets('«Descargar» guarda un Markdown con el título, el documento y '
        'las palabras clave en negrita', (tester) async {
      final id = await romaWithSummary();
      final creation = await h.creation(StudyCreationKind.summary, [id]);
      await h.open(tester, creation);

      await tester.tap(find.byKey(const Key('reading-frame-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reading-more-download')));
      await tester.pumpAndSettle();
      // El archivo se arma leyendo la base, fuera de los cuadros: se le da
      // tiempo de verdad.
      final saver = h.library.fileSaver;
      for (var i = 0; i < 100 && saver.savedBytes == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(saver.savedFileName, endsWith('.md'));
      final markdown = utf8.decode(saver.savedBytes!);
      expect(markdown, contains('## Roma'));
      expect(
        markdown,
        contains('**César** cruzó el Rubicón.\n\nEscipión volvió a Roma.'),
      );
    });
  });

  group('cómo se ve', () {
    // La tarjeta de lo que falta, con sus dos botones: en un renglón si
    // entran y, si no, uno debajo del otro, alineados y del mismo ancho, sin
    // el hueco que dejaba un `Wrap` (F46, paso 5c).
    for (final width in [360.0, 412.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('a $width dp con la letra a $scale, los botones de lo que '
            'falta van prolijos', (tester) async {
          h.modelReady = false;
          final id = await h.document('roma', title: 'Roma', text: roma);
          final creation = await h.creation(StudyCreationKind.summary, [id]);
          await h.open(
            tester,
            creation,
            size: Size(width, 1400),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);

          final card = tester.getRect(find.byKey(Key('extract-missing-$id')));
          final mark = tester.getRect(find.byKey(Key('extract-mark-$id')));
          final open = tester.getRect(find.byKey(Key('extract-open-$id')));
          // Sin el margen de abajo de la tarjeta (18), y adentro de su borde
          // y su relleno.
          final inner = Rect.fromLTRB(
            card.left,
            card.top,
            card.right,
            card.bottom - 18,
          ).deflate(16 + 1.5);
          expect(mark.left, closeTo(inner.left, 0.01));
          if (open.top > mark.top) {
            // Apilados: la misma izquierda, el mismo ancho —el de la
            // tarjeta—, y 8 entre los dos.
            expect(open.left, closeTo(mark.left, 0.01));
            expect(mark.width, closeTo(inner.width, 0.01));
            expect(open.width, closeTo(inner.width, 0.01));
            expect(open.top - mark.bottom, closeTo(8, 0.01));
          } else {
            // Juntos: 8 entre los dos y centrados en alto.
            expect(open.left - mark.right, closeTo(8, 0.01));
            expect(open.center.dy, closeTo(mark.center.dy, 0.01));
          }
          // Abajo, el relleno de la tarjeta y nada más.
          final bar = tester.getRect(
            find.descendant(
              of: find.byKey(Key('extract-missing-$id')),
              matching: find.byType(AdaptiveButtonBar),
            ),
          );
          expect(bar.bottom, closeTo(inner.bottom, 0.01));
          expect(open.bottom, lessThanOrEqualTo(bar.bottom + 0.01));
        });
      }
    }

    for (final theme in AppThemeChoice.values) {
      testWidgets('en 360 dp con la letra al doble, en ${theme.name}, con '
          'el reproductor abierto y lo que falta: sin desbordes', (
        tester,
      ) async {
        final a = await romaWithSummary();
        h.modelReady = false;
        final b = await h.document(
          'grecia',
          title: 'Grecia antigua y sus ciudades',
          text: 'Atenas inventó la democracia. Esparta prefería la guerra.',
        );
        final creation = await h.creation(StudyCreationKind.summary, [a, b]);
        await h.open(
          tester,
          creation,
          size: const Size(360, 780),
          theme: theme,
          textScale: 2,
          withReadAloud: true,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('reading-listen')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('read-aloud-player')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('reading-frame-appearance')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('reading-appearance-sheet')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
