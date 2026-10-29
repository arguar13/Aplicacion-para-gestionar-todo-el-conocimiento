import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/presentation/providers/extract_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_dock.dart';
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
      expect(shown(tester), isNot(contains('el Africano')));

      final parts =
          (await h.container.read(processedRepositoryProvider).partsOf(id))
              .getRight()
              .toNullable()!;
      final page = parts.firstWhere((p) => p.content.contains('Escipión'));
      await h.container
          .read(processedRepositoryProvider)
          .editPart(
            page.id,
            page.content.replaceFirst('Escipión', 'Escipión el Africano'),
          );
      await tester.pumpAndSettle();
      expect(shown(tester), contains('Escipión el Africano'));
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

  group('«Resaltar las palabras clave» (M8): la misma preferencia del '
      'original', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('extract-reading')));
      await tester.pumpAndSettle();
    }

    bool switchOn(WidgetTester tester) => tester
        .widget<SwitchListTile>(
          find.byKey(const Key('extract-keywords-toggle')),
        )
        .value;

    testWidgets('prendida por defecto; apagarla acá la apaga en el '
        'documento, y prenderla allá la prende acá', (tester) async {
      final id = await romaWithSummary();
      final creation = await h.creation(StudyCreationKind.summary, [id]);
      await h.open(tester, creation);
      await openSheet(tester);
      expect(switchOn(tester), isTrue);
      expect(find.text(es.f43TextKeywordsToggleOne), findsOneWidget);

      await tester.tap(find.byKey(const Key('extract-keywords-toggle')));
      await tester.pumpAndSettle();
      expect(h.container.read(processedKeywordsShownProvider(id)), isFalse);
      expect(
        h.container
            .read(sharedPreferencesProvider)
            .getStringList(ProcessedOriginalLayers.keyOf(id)),
        [StudyMarkKind.keyword.name],
      );
      expect(switchOn(tester), isFalse);
      expect(paintedWith(tester, pink), isEmpty);

      // Desde el original (M5): el mismo lugar.
      await h.container
          .read(processedOriginalHiddenProvider(id).notifier)
          .setHidden(StudyMarkKind.keyword, hidden: false);
      await tester.pumpAndSettle();
      expect(switchOn(tester), isTrue);
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
      await openSheet(tester);
      expect(find.text(es.f43TextKeywordsToggleMany(2)), findsOneWidget);

      await tester.tap(find.byKey(const Key('extract-keywords-toggle')));
      await tester.pumpAndSettle();
      expect(h.container.read(processedKeywordsShownProvider(a)), isFalse);
      expect(h.container.read(processedKeywordsShownProvider(b)), isFalse);
    });
  });

  group('el modo escuchar (M8, decisión 86)', () {
    testWidgets('«Escuchar» abre el reproductor grande y lee lo que se ve; '
        'lo que suena va en amarillo con el rosa encima, y avanza con la '
        'voz', (tester) async {
      final id = await romaWithSummary();
      final creation = await h.creation(StudyCreationKind.summary, [id]);
      await h.open(tester, creation);
      expect(find.byKey(const Key('extract-player')), findsNothing);

      await tester.tap(find.byKey(const Key('extract-listen')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('extract-player')), findsOneWidget);
      expect(h.tts.spoken, ['César cruzó el Rubicón.']);
      // El amarillo en la oración que suena; la palabra clave, rosa encima.
      expect(paintedWith(tester, yellow).join(), ' cruzó el Rubicón.');
      expect(paintedWith(tester, pink), ['César']);
      expect(find.text('${es.readAloudReading} · 1 de 2'), findsOneWidget);
      // El lector flotante no repite el reproductor.
      expect(
        h.container.read(readAloudDockProvider),
        contains(extractReadableId(creation.id)),
      );

      h.tts.completeCurrent();
      await tester.pumpAndSettle();
      expect(h.tts.spoken.last, 'Escipión volvió a Roma.');
      expect(paintedWith(tester, yellow).join(), 'Escipión volvió a Roma.');

      await tester.tap(find.byKey(const Key('extract-player-previous')));
      await tester.pumpAndSettle();
      expect(h.tts.spoken.last, 'César cruzó el Rubicón.');
      expect(h.container.read(readAloudControllerProvider).segmentIndex, 0);

      await tester.tap(find.byKey(const Key('extract-player-play')));
      await tester.pumpAndSettle();
      expect(h.container.read(readAloudControllerProvider).playing, isFalse);

      await tester.tap(find.byKey(const Key('extract-player-next')));
      await tester.pumpAndSettle();
      expect(h.container.read(readAloudControllerProvider).segmentIndex, 1);
      expect(paintedWith(tester, yellow).join(), 'Escipión volvió a Roma.');

      await tester.tap(find.byKey(const Key('extract-player-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('extract-player')), findsNothing);
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

      await tester.tap(find.byKey(const Key('extract-listen')));
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

      await tester.tap(find.byKey(const Key('extract-listen')));
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
  });

  group('el archivo', () {
    testWidgets('«Descargar» guarda un Markdown con el título, el documento y '
        'las palabras clave en negrita', (tester) async {
      final id = await romaWithSummary();
      final creation = await h.creation(StudyCreationKind.summary, [id]);
      await h.open(tester, creation);

      await tester.tap(find.byKey(ValueKey('creation-menu-${creation.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('creation-action-download')));
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
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('extract-listen')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('extract-player')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('extract-reading')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('extract-reading-sheet')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
