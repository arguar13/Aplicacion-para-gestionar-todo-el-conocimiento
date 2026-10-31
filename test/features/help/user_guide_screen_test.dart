import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/domain/services/chat_passages.dart'
    show foldForSearch;
import 'package:sinapsis/features/help/presentation/help_document.dart';
import 'package:sinapsis/features/help/presentation/providers/help_providers.dart';
import 'package:sinapsis/features/help/presentation/screens/user_guide_screen.dart';
import 'package:sinapsis/features/help/presentation/widgets/help_load_error.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import 'help_test_app.dart';

/// La guía de uso dentro de la app (F47, paso 7), con la guía de verdad, a
/// 360 dp con la letra al doble, en claro y en oscuro.
void main() {
  final es = AppLocalizationsEs();
  final guide = HelpDocument.parse(File(kUserGuideAsset).readAsStringSync());

  Future<void> pumpGuide(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) => pumpHelpScreen(
    tester,
    const UserGuideScreen(),
    brightness: brightness,
    overrides: [userGuideProvider.overrideWith((ref) async => guide)],
  );

  final contents = find.byKey(const Key('guide-contents'));

  /// Desplaza el índice hasta que [finder] se vea: con la letra al doble, la
  /// presentación de la guía ocupa más que la pantalla.
  Future<void> showInContents(
    WidgetTester tester,
    Finder finder, {
    double delta = 500,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      // Con la letra al doble, el índice entero son decenas de pantallas.
      maxScrolls: 120,
      // El primero es el de la lista; el campo de buscar tiene el suyo.
      scrollable: find
          .descendant(of: contents, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
  }

  /// El cuerpo del capítulo abierto, sin la barra de arriba.
  Finder inChapter(Finder finder) => find.descendant(
    of: find.byWidgetPredicate(
      (w) =>
          w is SingleChildScrollView &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('guide-chapter-body'),
    ),
    matching: finder,
  );

  /// Si [finder] se ve, entero, en la pantalla de 800 de alto.
  bool onScreen(WidgetTester tester, Finder finder) {
    final rect = tester.getRect(finder);
    return rect.top >= 0 && rect.bottom <= 800;
  }

  for (final brightness in Brightness.values) {
    group('en ${brightness.name}', () {
      testWidgets(
        'el índice sale de los títulos de la guía, de punta a punta',
        (tester) async {
          await pumpGuide(tester, brightness: brightness);

          expect(find.text(es.f47P7Guide), findsOneWidget);
          await showInContents(tester, find.text(es.f47P7GuideContents));
          await showInContents(tester, find.text(guide.chapters.first.title));
          expect(find.text(guide.chapters.first.title), findsOneWidget);
          await showInContents(tester, find.text(guide.chapters.last.title));
          expect(find.text(guide.chapters.last.title), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('un capítulo se lee entero y lleva al siguiente', (
        tester,
      ) async {
        await pumpGuide(tester, brightness: brightness);

        await showInContents(tester, find.byKey(const Key('guide-chapter-0')));
        await tester.tap(find.byKey(const Key('guide-chapter-0')));
        await tester.pumpAndSettle();

        final first = guide.chapters[0];
        expect(find.widgetWithText(AppBar, first.title), findsOneWidget);
        expect(inChapter(find.text(first.title)), findsOneWidget);

        await tester.scrollUntilVisible(
          find.byKey(const Key('guide-next-chapter')),
          600,
          scrollable: inChapter(find.byType(Scrollable)).first,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('guide-previous-chapter')), findsNothing);
        await tester.tap(find.byKey(const Key('guide-next-chapter')));
        await tester.pumpAndSettle();

        final second = guide.chapters[1];
        expect(find.widgetWithText(AppBar, second.title), findsOneWidget);
        expect(onScreen(tester, inChapter(find.text(second.title))), isTrue);
        expect(tester.takeException(), isNull);
      });

      testWidgets('buscar lista cada lugar, y salta de uno a otro resaltado', (
        tester,
      ) async {
        await pumpGuide(tester, brightness: brightness);
        final matches = guide.search('bóveda');

        await tester.enterText(
          find.byKey(const Key('guide-search-field')),
          'BOVEDA',
        );
        await tester.pumpAndSettle();
        expect(
          find.text(es.f47P7GuideResultCount(matches.length)),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('guide-match-0')));
        await tester.pumpAndSettle();
        expect(
          find.text(es.f47P7GuideMatchPosition(1, matches.length)),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(AppBar, guide.chapters[matches[0].chapter].title),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('guide-find-next')));
        await tester.pumpAndSettle();
        expect(
          find.text(es.f47P7GuideMatchPosition(2, matches.length)),
          findsOneWidget,
        );

        // El resultado en el que se está, en amarillo; los demás, con el
        // fondo de los resaltados.
        final yellow = paintedSpans(tester)
            .where(
              (s) => s.style?.backgroundColor == RenderedMarkdown.playingColor,
            )
            .map((s) => s.text ?? '')
            .join();
        expect(foldForSearch(yellow), 'boveda');
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('de una sección, abre su capítulo con la sección a la vista', (
    tester,
  ) async {
    await pumpGuide(tester);
    // La última sección del capítulo con más: la más lejos del principio.
    final chapter = guide.chapters.reduce(
      (a, b) => b.sections.length > a.sections.length ? b : a,
    );
    final section = chapter.sections.last;
    final tile = find.byKey(
      Key('guide-section-${chapter.index}-${section.blockIndex}'),
    );
    await showInContents(tester, tile);

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, chapter.title), findsOneWidget);
    expect(onScreen(tester, inChapter(find.text(section.title))), isTrue);
  });

  testWidgets('«atrás» desde un capítulo vuelve al índice, no a Ajustes', (
    tester,
  ) async {
    await pumpGuide(tester);
    await showInContents(tester, find.byKey(const Key('guide-chapter-2')));
    await tester.tap(find.byKey(const Key('guide-chapter-2')));
    await tester.pumpAndSettle();
    expect(contents, findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(contents, findsOneWidget);

    // Y la flecha de arriba hace lo mismo.
    await showInContents(tester, find.byKey(const Key('guide-chapter-2')));
    await tester.tap(find.byKey(const Key('guide-chapter-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(es.f47P7GuideBackToContents));
    await tester.pumpAndSettle();
    expect(contents, findsOneWidget);
  });

  testWidgets(
    'desde un capítulo se busca en toda la guía, cruzando capítulos',
    (tester) async {
      await pumpGuide(tester);
      final matches = guide.search('bóveda');
      // Un capítulo sin «bóveda» a partir de él no existe: el primero de la
      // búsqueda es el primero de este capítulo en adelante.
      final start = matches.last.chapter;
      await showInContents(tester, find.byKey(Key('guide-chapter-$start')));
      await tester.tap(find.byKey(Key('guide-chapter-$start')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('guide-open-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('guide-find-field')),
        'bóveda',
      );
      await tester.pumpAndSettle();
      final firstHere = matches.indexWhere((m) => m.chapter >= start);
      expect(
        find.text(es.f47P7GuideMatchPosition(firstHere + 1, matches.length)),
        findsOneWidget,
      );

      // Del último, «siguiente» da la vuelta al primero, en otro capítulo.
      await tester.tap(find.byKey(const Key('guide-find-previous')));
      await tester.pumpAndSettle();
      for (var i = firstHere - 1; i < matches.length - 1; i++) {
        await tester.tap(find.byKey(const Key('guide-find-next')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('guide-find-next')));
      await tester.pumpAndSettle();
      expect(
        find.text(es.f47P7GuideMatchPosition(1, matches.length)),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          AppBar,
          guide.chapters[matches.first.chapter].title,
        ),
        findsOneWidget,
      );

      // Cerrar la búsqueda saca lo resaltado.
      await tester.tap(find.byKey(const Key('guide-find-close')));
      await tester.pumpAndSettle();
      expect(
        paintedSpans(tester).where(
          (s) => s.style?.backgroundColor == RenderedMarkdown.playingColor,
        ),
        isEmpty,
      );
    },
  );

  testWidgets('lo que no está lo dice', (tester) async {
    await pumpGuide(tester);
    await tester.enterText(
      find.byKey(const Key('guide-search-field')),
      'xyzzy',
    );
    await tester.pumpAndSettle();
    expect(find.text(es.f47P7GuideNoResults('xyzzy')), findsOneWidget);
    expect(find.byKey(const Key('guide-match-0')), findsNothing);
  });

  testWidgets('los párrafos se leen de corrido, sin los cortes del archivo', (
    tester,
  ) async {
    await pumpGuide(tester);
    // La presentación de la guía está partida en renglones en el archivo.
    final preface = guide.raw.substring(
      guide.preface.first.content.start,
      guide.preface.first.content.end,
    );
    expect(preface, contains('\n'));
    final shown = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((t) => t.text.toPlainText())
        .firstWhere((t) => t.startsWith(preface.substring(0, 20)));
    expect(shown, isNot(contains('\n')));
  });

  testWidgets('para el lector de pantalla: el índice es un encabezado, y la '
      'cuenta de resultados se anuncia', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpGuide(tester);
    await showInContents(tester, find.text(es.f47P7GuideContents));

    expect(
      tester.getSemantics(find.text(es.f47P7GuideContents)),
      isSemantics(label: es.f47P7GuideContents, isHeader: true),
    );

    await showInContents(
      tester,
      find.byKey(const Key('guide-search-field')),
      delta: -500,
    );
    await tester.enterText(
      find.byKey(const Key('guide-search-field')),
      'bóveda',
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('guide-result-count'))),
      isSemantics(isLiveRegion: true),
    );

    await tester.tap(find.byKey(const Key('guide-match-0')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('guide-find-position'))),
      isSemantics(isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('si no se puede leer, lo dice y deja reintentar', (tester) async {
    var attempts = 0;
    await pumpHelpScreen(
      tester,
      const UserGuideScreen(),
      overrides: [
        userGuideProvider.overrideWith((ref) async {
          attempts++;
          throw const FileSystemException('sin guía');
        }),
      ],
    );
    expect(find.byType(HelpLoadError), findsOneWidget);
    expect(find.text(es.f47P7HelpLoadError), findsOneWidget);

    await tester.tap(find.byKey(const Key('help-retry')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });
}
