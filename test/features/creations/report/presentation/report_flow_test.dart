import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/report/domain/report_json.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';
import 'package:sinapsis/features/creations/report/presentation/report_kind.dart';

import '../domain/report_generator_test.dart'
    show FakeReportWriter, reportReply;
import '../support/report_harness.dart';

/// Quien escribe, de mentira, que se queda escribiendo hasta [release]: así
/// se ve la fila «Generando…» antes de que el informe esté listo.
class _HeldWriter implements StructuredWriter {
  _HeldWriter(this.reply);

  final String reply;
  final release = Completer<void>();
  final calls = <StructuredCall>[];

  @override
  int get contextTokens => 200000;

  @override
  Future<T> writeStructured<T>(StructuredRequest<T> request) =>
      runStructuredRequest(request, (call) async {
        calls.add(call);
        await release.future;
        return reply;
      });
}

/// Los informes de punta a punta (F43, paso 10): la hoja con el formato y
/// las plantillas como tarjetas —la propia escrita con ✎ y recordada—, la
/// cola de crear de verdad con quien escribe de mentira, la fila que se
/// genera y el visor que se abre.
void main() {
  late ReportHarness h;

  setUp(() async {
    ReportHarness.writer = FakeReportWriter([reportReply()]);
    h = await ReportHarness.create(keywords: const ['Moisés']);
    await h.processed('p-1', 'Éxodo — Comentario');
  });

  Future<void> openSheet(WidgetTester tester) async {
    final tile = find.byKey(const ValueKey('creation-kind-report'));
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('review-entry')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder template(ReportTemplate t) =>
      find.byKey(ValueKey('report-template-${t.value}'));

  // La base se lee fuera del reloj de mentira de la prueba.
  Future<List<StudyCreation>> everything(WidgetTester tester) async =>
      (await tester.runAsync(
        () =>
            h.creations.watchByScope(const CreationScope.allProcessed()).first,
      ))!;

  Future<List<StudyCreation>> all(WidgetTester tester) async =>
      (await tester.runAsync(
        () => h.creations.pending(),
      ))!.getOrElse((f) => throw StateError('$f'));

  /// Deja trabajar a la cola —lo de la base y el armado del material corren
  /// fuera del reloj de mentira— hasta que no queda nada en la cola ni
  /// generándose.
  Future<List<StudyCreation>> untilDone(WidgetTester tester) async {
    for (var i = 0; i < 300; i++) {
      final created = await everything(tester);
      if (created.isNotEmpty && created.every((c) => !c.status.isPending)) {
        await tester.pumpAndSettle();
        return created;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    fail('La cola no terminó.');
  }

  Future<StudyCreation> stored(WidgetTester tester, String id) async =>
      (await tester.runAsync(
        () => h.creations.find(id),
      ))!.getOrElse((f) => throw StateError('$f'))!;

  test('los informes están registrados: su visor, su hoja y su generador', () {
    final spec = h.container
        .read(creationKindRegistryProvider)
        .of(StudyCreationKind.report);
    expect(spec.viewerBuilder, isNotNull);
    expect(spec.exporter, isNotNull);
    expect(spec.optionsBuilder, isNotNull);
    // La plantilla se dibuja a mano; el formato queda como segmentado.
    expect(spec.options.map((o) => o.key), [CreationOptionValues.format]);
    expect(spec.defaults[CreationOptionValues.template], 'learning_summary');
    expect(
      spec.outputTokensFor({
        CreationOptionValues.template: CreationOptionValues.glossary,
        CreationOptionValues.format: CreationOptionValues.document,
      }),
      ReportTemplate.glossary.outputTokens,
    );
    expect(buildReportKindSpec().kind, StudyCreationKind.report);
  });

  testWidgets('la hoja: el formato, las plantillas como tarjetas y la propia', (
    tester,
  ) async {
    await h.open(tester, '/review');
    await openSheet(tester);
    expect(find.byKey(const Key('report-template-picker')), findsOneWidget);
    for (final t in ReportTemplate.values) {
      expect(template(t), findsOneWidget);
    }
    expect(find.text('Crear la tuya ✎'), findsOneWidget);
    expect(
      find.text('Objetivos, conceptos clave y preguntas para repasar'),
      findsOneWidget,
    );
    // La de fábrica, elegida; sin la propia, sin su campo.
    expect(
      find.descendant(
        of: template(ReportTemplate.learningSummary),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('report-custom-template')), findsNothing);

    await tapInSheet(tester, template(ReportTemplate.custom));
    expect(find.byKey(const Key('report-custom-template')), findsOneWidget);
    expect(
      find.text('Sin descripción se arma un informe general.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('report-custom-template')),
      'Una línea de tiempo con cada plaga',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Sin descripción se arma un informe general.'),
      findsNothing,
    );
    await tapInSheet(
      tester,
      find.byKey(const ValueKey('creation-option-format-document')),
    );
    await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));

    final stored = (await untilDone(tester)).single;
    expect(stored.status, CreationStatus.ready);
    expect(stored.options[CreationOptionValues.template], 'custom');
    expect(
      stored.options[CreationOptionValues.customTemplate],
      'Una línea de tiempo con cada plaga',
    );
    expect(stored.options[CreationOptionValues.format], 'document');
    // Llegó al pedido.
    final writer = ReportHarness.writer! as FakeReportWriter;
    await tester.pumpAndSettle();
    expect(
      writer.calls.single.instruction,
      contains('«Una línea de tiempo con cada plaga»'),
    );
  });

  testWidgets('la propia queda recordada, y las ya usadas vuelven a un toque', (
    tester,
  ) async {
    await h.open(tester, '/review');
    await openSheet(tester);
    await tapInSheet(tester, template(ReportTemplate.custom));
    await tester.enterText(
      find.byKey(const Key('report-custom-template')),
      'Preguntas y respuestas',
    );
    await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
    await untilDone(tester);

    // La próxima vez, la hoja abre con la propia y su texto.
    await openSheet(tester);
    expect(
      find.descendant(
        of: template(ReportTemplate.custom),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(
      find.byKey(const Key('report-custom-template')),
    );
    expect(field.controller!.text, 'Preguntas y respuestas');

    // Se escribe otra; la de antes está en «Las que ya usaste».
    await tester.enterText(
      find.byKey(const Key('report-custom-template')),
      'Otra cosa',
    );
    await tester.pumpAndSettle();
    expect(find.text('Las que ya usaste'), findsOneWidget);
    await tapInSheet(
      tester,
      find.byKey(const ValueKey('report-custom-used-0')),
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('report-custom-template')))
          .controller!
          .text,
      'Preguntas y respuestas',
    );
  });

  testWidgets('crear → generándose → lista → abrir el visor', (tester) async {
    final writer = _HeldWriter(
      reportReply(sections: ['Objetivos', 'Conceptos clave']),
    );
    ReportHarness.writer = writer;
    await h.open(tester, '/review');
    await openSheet(tester);
    await tapInSheet(tester, template(ReportTemplate.studyGuide));
    await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
    // Hasta que la IA de mentira empieza a escribir.
    for (var i = 0; i < 300 && writer.calls.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    // Se está escribiendo: la fila muestra su paso y su avance.
    final pending = await all(tester);
    expect(pending, hasLength(1));
    final id = pending.single.id;
    expect(pending.single.status, CreationStatus.generating);
    expect(
      writer.calls.single.instruction,
      contains(ReportTemplate.studyGuide.guidance),
    );
    final row = find.byKey(ValueKey('creation-tile-$id'));
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
    expect(
      find.descendant(
        of: find.byKey(ValueKey('creation-status-$id')),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );

    writer.release.complete();
    await untilDone(tester);
    final ready = await stored(tester, id);
    expect(ready.status, CreationStatus.ready);
    expect(ready.title, 'Éxodo');
    expect(ReportJson.decode(ready.content).sections, hasLength(2));

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-view')), findsOneWidget);
    expect(find.text('GUÍA DE ESTUDIO · INTERACTIVO'), findsOneWidget);
    expect(find.text('Conceptos clave'), findsOneWidget);
    expect(find.text('Para probarte'), findsNWidgets(2));
  });

  testWidgets('la hoja en 360 dp, con la letra al doble y oscura', (
    tester,
  ) async {
    await h.open(
      tester,
      '/review',
      size: const Size(360, 760),
      theme: AppThemeChoice.dark,
      textScale: 2,
    );
    await openSheet(tester);
    expect(tester.takeException(), isNull);
    await tapInSheet(tester, template(ReportTemplate.custom));
    await tester.enterText(
      find.byKey(const Key('report-custom-template')),
      'Una plantilla con un texto bastante largo para ver cómo se acomoda',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // De a una: con la letra al doble no entran dos.
    final first = tester.getRect(template(ReportTemplate.learningSummary));
    final second = tester.getRect(template(ReportTemplate.studyGuide));
    expect(second.top, greaterThan(first.bottom));
  });
}
