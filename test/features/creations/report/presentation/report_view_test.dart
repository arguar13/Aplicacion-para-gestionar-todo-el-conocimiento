import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_order.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';

import '../support/report_harness.dart';
import '../support/sample_reports.dart';

/// El visor de un informe (F43, paso 10): las secciones que se pliegan con
/// «⌃», el índice que salta, las preguntas del interactivo con su puntaje,
/// las palabras clave en rosa, la descarga y cómo se ve en un teléfono
/// angosto, con la letra grande y en los nueve temas.
void main() {
  late ReportHarness h;

  setUp(() async {
    h = await ReportHarness.create(keywords: const ['Moisés', 'Sinaí']);
    await h.processed('p-1', 'Éxodo — Comentario');
  });

  Future<void> open(
    WidgetTester tester,
    Report report, {
    Map<String, Object?> options = const {},
    Size size = const Size(420, 1600),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    final creation = await h.ready(report, options: options);
    await h.open(
      tester,
      '/creations/${creation.id}',
      size: size,
      theme: theme,
      textScale: textScale,
    );
  }

  Finder body(int section) =>
      find.byKey(ValueKey('report-section-body-$section'));
  Finder toggle(int section) =>
      find.byKey(ValueKey('report-section-toggle-$section'));

  /// La opción de la pregunta [q] de la sección [s] cuyo texto es [text].
  Finder option(int s, int q, String text) {
    final question = sampleReport().sections[s].questions[q];
    final index = question.options.indexWhere((o) => o.text == text);
    return find.descendant(
      of: find.byKey(ValueKey('report-question-$s-$q')),
      matching: find.byKey(ValueKey('report-option-$index')),
    );
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('arriba la plantilla y el formato, el título y las secciones', (
    tester,
  ) async {
    await open(tester, sampleReport());
    expect(find.text('RESUMEN DE APRENDIZAJE · INTERACTIVO'), findsOneWidget);
    expect(find.byKey(const Key('report-title')), findsOneWidget);
    expect(
      find.text('De la esclavitud en Egipto a la Alianza del Sinaí.'),
      findsOneWidget,
    );
    expect(find.text('3 secciones · 3 preguntas'), findsOneWidget);
    for (final title in ['Introducción', 'Moisés y el Faraón', 'Conclusión']) {
      expect(find.text(title), findsWidgets);
    }
    // Las viñetas, la lista numerada y la cita.
    expect(find.text('•'), findsNWidgets(3));
    expect(find.text('◦'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(
      find.text('Dejá ir a mi pueblo.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('cada sección se pliega con «⌃» y se vuelve a abrir', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester, sampleReport());
    expect(body(0), findsOneWidget);
    expect(
      find.descendant(
        of: toggle(0),
        matching: find.byIcon(Icons.keyboard_arrow_up_rounded),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Plegar «Introducción»')),
      matchesSemantics(
        label: 'Plegar «Introducción»',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(toggle(0));
    await tester.pumpAndSettle();
    expect(body(0), findsNothing);
    expect(body(1), findsOneWidget, reason: 'las otras no se pliegan');
    expect(
      find.descendant(
        of: toggle(0),
        matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Desplegar «Introducción»'), findsOneWidget);

    await tester.tap(toggle(0));
    await tester.pumpAndSettle();
    expect(body(0), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('el índice salta a una sección y pliega o despliega todo', (
    tester,
  ) async {
    await open(tester, sampleReport(), size: const Size(420, 700));
    await tester.tap(find.byKey(const Key('report-action-index')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-index')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-index-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-fold-all')));
    await tester.pumpAndSettle();
    expect(body(0), findsNothing);
    expect(body(2), findsNothing);

    // Tocar «Conclusión» la despliega y la deja a la vista.
    await tester.tap(find.byKey(const ValueKey('report-index-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-index')), findsNothing);
    expect(body(2), findsOneWidget);
    expect(body(0), findsNothing);
    expect(tester.getTopLeft(toggle(2)).dy, inInclusiveRange(0, 700));

    await tester.tap(find.byKey(const Key('report-action-index')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-unfold-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cerrar').last);
    await tester.pumpAndSettle();
    expect(body(0), findsOneWidget);
    expect(body(1), findsOneWidget);

    // Desde el final, saltar a la primera la trae arriba.
    await tester.drag(
      find.byKey(const Key('report-view')),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(toggle(0)).dy, lessThan(0));
    await tester.tap(find.byKey(const Key('report-action-index')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-index-0')));
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(toggle(0)).dy;
    expect(top, greaterThan(0));
    expect(top, lessThan(200), reason: 'arriba, debajo de la barra');
  });

  testWidgets('el interactivo: «¡Exacto!», «No es esa» y el puntaje', (
    tester,
  ) async {
    await open(tester, sampleReport());
    expect(find.text('Para probarte'), findsNWidgets(2));
    expect(find.text('0 de 3 respondidas'), findsOneWidget);

    // Bien en la primera.
    await tapVisible(tester, option(0, 0, 'Moisés'));
    expect(find.text('¡Exacto!'), findsOneWidget);
    expect(
      find.text('Moisés recibe el llamado en la zarza ardiente.'),
      findsOneWidget,
    );
    // La primera respuesta es la que cuenta.
    await tapVisible(tester, option(0, 0, 'Aarón'));
    expect(find.text('¡Exacto!'), findsOneWidget);
    expect(find.text('No es esa'), findsNothing);

    // Mal en la segunda: dice cuál era, con su letra.
    await tapVisible(tester, option(0, 1, 'A Roma'));
    final q2 = sampleReport().sections[0].questions[1];
    final letter = reportOptionLetter(
      reportOptionOrder(q2).indexOf(q2.correct),
    );
    expect(find.text('No es esa'), findsOneWidget);
    expect(find.text('La correcta es la $letter: Al Sinaí'), findsOneWidget);
    expect(find.text('1 de 2 bien en esta sección'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    // El porqué de la elegida, si lo tiene.
    await tapVisible(tester, option(1, 0, 'Oro y plata'));
    expect(find.text('No es lo que pide.'), findsOneWidget);
    expect(find.text('Tu puntaje: 1 de 3'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('report-try-again')));
    expect(find.text('¡Exacto!'), findsNothing);
    expect(find.text('No es esa'), findsNothing);
    expect(find.text('0 de 3 respondidas'), findsOneWidget);
  });

  testWidgets('las opciones, para el lector de pantalla', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester, sampleReport());
    final q = sampleReport().sections[0].questions[0];
    final order = reportOptionOrder(q);
    final moises = reportOptionLetter(order.indexOf(q.correct));
    expect(find.bySemanticsLabel('Opción $moises: Moisés'), findsOneWidget);
    await tapVisible(tester, option(0, 0, 'Moisés'));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Opción $moises: Moisés')),
      matchesSemantics(label: 'Opción $moises: Moisés', value: 'Correcta'),
    );
    semantics.dispose();
  });

  testWidgets('como documento, sin preguntas ni puntaje', (tester) async {
    await open(
      tester,
      sampleReport(),
      options: {CreationOptionValues.format: CreationOptionValues.document},
    );
    expect(find.text('RESUMEN DE APRENDIZAJE · DOCUMENTO'), findsOneWidget);
    expect(find.text('3 secciones'), findsOneWidget);
    expect(find.text('Para probarte'), findsNothing);
    expect(find.byKey(const Key('report-score')), findsNothing);
  });

  testWidgets('las palabras clave en rosa, y se apagan', (tester) async {
    await open(tester, sampleReport(), size: const Size(420, 2400));
    final pink = StudyPalette.of(Brightness.light).keyword;
    List<String> painted() => [
      for (final widget in tester.widgetList<RichText>(find.byType(RichText)))
        ...() {
          final found = <String>[];
          widget.text.visitChildren((span) {
            if (span is TextSpan &&
                span.style?.backgroundColor == pink &&
                span.text != null) {
              found.add(span.text!);
            }
            return true;
          });
          return found;
        }(),
    ];
    expect(painted(), containsAll(['Moisés', 'Sinaí']));
    expect(painted(), isNot(contains('Faraón')));

    await tester.tap(find.byKey(const Key('report-keywords')));
    await tester.pumpAndSettle();
    expect(painted(), isEmpty);
  });

  testWidgets('el glosario: cada término con su definición', (tester) async {
    await open(
      tester,
      sampleGlossary(),
      options: {CreationOptionValues.template: CreationOptionValues.glossary},
    );
    expect(find.text('GLOSARIO · INTERACTIVO'), findsOneWidget);
    expect(find.text('Maná'), findsOneWidget);
    expect(
      find.text('El pan del desierto.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('sin secciones, lo dice', (tester) async {
    await open(tester, const Report(title: 'Vacío'));
    expect(find.byKey(const Key('report-empty')), findsOneWidget);
  });

  testWidgets('descargar: elige Markdown y guarda el archivo', (tester) async {
    await open(tester, sampleReport());
    await tester.tap(find.byKey(const Key('report-action-download')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-export-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('report-export-markdown')));
    await tester.pumpAndSettle();
    final saver = h.library.fileSaver;
    expect(saver.savedFileName, 'Éxodo_ liberación y alianza.md');
    final markdown = utf8.decode(saver.savedBytes!);
    expect(markdown, contains('# Éxodo: liberación y alianza'));
    expect(markdown, contains('Fuentes: Éxodo — Comentario'));
    expect(markdown, contains('**Moisés**'));
    expect(markdown, contains('## Respuestas'));
  });

  testWidgets('descargar sin elegir no guarda nada', (tester) async {
    await open(tester, sampleReport());
    await tester.tap(find.byKey(const Key('report-action-download')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(h.library.fileSaver.savedFileName, isNull);
  });

  group('en un teléfono angosto', () {
    testWidgets('360 dp, la letra al doble y oscuro: nada desborda', (
      tester,
    ) async {
      await open(
        tester,
        sampleReport(),
        size: const Size(360, 720),
        theme: AppThemeChoice.dark,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      // Recorrerlo entero, respondiendo una.
      await tapVisible(tester, option(0, 0, 'Aarón'));
      await tester.drag(
        find.byKey(const Key('report-view')),
        const Offset(0, -6000),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('report-action-index')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final theme in AppThemeChoice.values) {
      testWidgets('en el tema ${theme.name}', (tester) async {
        await open(
          tester,
          sampleReport(),
          size: const Size(360, 1800),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        await tapVisible(tester, option(0, 0, 'Moisés'));
        expect(find.text('¡Exacto!'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
