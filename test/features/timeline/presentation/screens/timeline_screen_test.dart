import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_canvas.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_events_painter.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_frame.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_minimap.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';
import '../../timeline_fixtures.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;
  late String fechaId;

  final now = DateTime(2026, 9, 11, 10);

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
    fechaId =
        (await (db.select(db.propertyDefinitions)..where(
                  (d) =>
                      d.isSystem.equals(true) &
                      d.name.equals(kFechaDelHechoCategoryName),
                ))
                .getSingle())
            .id;
  });

  /// Guarda un documento procesado de una fuente de tipo [kind] —lo que la
  /// línea de tiempo lee desde F41 (paso 6)— y le pone [date] como «Fecha del
  /// hecho», por el camino de la app.
  Future<void> seedEvent(
    String id,
    HistoricalDate date, {
    String? title,
    SourceKind kind = SourceKind.webPage,
  }) async {
    await insertProcessedDocument(
      db,
      id: id,
      title: title ?? 'Hecho $id',
      createdAt: now,
      sourceKind: kind,
    );
    final organize = harness.container.read(organizeRepositoryProvider);
    final value = (await organize.getOrCreateHistoricalPropertyValue(
      definitionId: fechaId,
      date: date,
    )).getRight().toNullable()!;
    await organize.assignProperty(
      itemId: id,
      definitionId: fechaId,
      value: value.value,
    );
  }

  /// Le pone a un elemento que ya existe OTRA «Fecha del hecho»: un documento
  /// con varias fechas.
  Future<void> addDate(String id, HistoricalDate date) async {
    final organize = harness.container.read(organizeRepositoryProvider);
    final value = (await organize.getOrCreateHistoricalPropertyValue(
      definitionId: fechaId,
      date: date,
    )).getRight().toNullable()!;
    await organize.assignProperty(
      itemId: id,
      definitionId: fechaId,
      value: value.value,
    );
  }

  /// Un tema con esos elementos adentro; devuelve su id.
  Future<String> space(String name, List<String> itemIds) async {
    final created =
        (await harness.container
                .read(organizeRepositoryProvider)
                .createSpace(name))
            .getRight()
            .toNullable()!;
    await harness.container
        .read(libraryRepositoryProvider)
        .setSpaces(itemIds: itemIds, spaceIds: {created.id});
    return created.id;
  }

  GoRouter router() => GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const TimelineScreen()),
      GoRoute(
        path: RoutePaths.itemDetailPattern,
        builder: (_, state) =>
            Scaffold(body: Text('detalle de ${state.pathParameters['id']}')),
      ),
    ],
  );

  Widget app(Widget Function(Widget child) wrap) => wrap(
    MaterialApp.router(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router(),
    ),
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(900, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        (child) => UncontrolledProviderScope(
          container: harness.container,
          child: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final canvasKey = find.byKey(const ValueKey('timeline-events'));

  /// El cuadro que la pantalla está dibujando: dónde puso cada evento. Los
  /// eventos no son widgets —se dibujan en un solo lienzo—, así que se miran en
  /// el modelo del que salen el dibujo, el toque y la semántica.
  TimelineFrame frameOf(WidgetTester tester) =>
      (tester.widget<CustomPaint>(canvasKey).painter! as TimelineEventsPainter)
          .frame;

  bool shows(WidgetTester tester, String title) =>
      canvasKey.evaluate().isNotEmpty &&
      frameOf(tester).boxes.any((box) => box.event.title == title);

  TimelineBox boxOf(WidgetTester tester, String title) =>
      frameOf(tester).boxes.singleWhere((box) => box.event.title == title);

  double left(WidgetTester tester, String title) =>
      boxOf(tester, title).rect.left;

  /// Toca el centro de la caja del evento [title], como lo haría un dedo.
  Future<void> tapEvent(WidgetTester tester, String title) => tester.tapAt(
    tester.getTopLeft(canvasKey) + boxOf(tester, title).rect.center,
  );

  group('sin hechos', () {
    testWidgets('explica cómo fechar un elemento', (tester) async {
      await pumpScreen(tester);

      expect(find.text(es.timelineEmptyTitle), findsOneWidget);
      expect(find.text(es.timelineEmptyHint), findsOneWidget);
      expect(find.byType(TimelineCanvas), findsNothing);
    });

    testWidgets('un elemento sin fecha tampoco aparece', (tester) async {
      await harness.container
          .read(libraryRepositoryProvider)
          .save(
            KnowledgeItem(
              id: 'sin-fecha',
              title: 'Sin fecha',
              source: Source(
                id: 's',
                kind: SourceKind.webPage,
                capturedAt: now,
                url: 'https://e.org',
              ),
              processingState: ProcessingState.ready,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await pumpScreen(tester);

      expect(find.text(es.timelineEmptyTitle), findsOneWidget);
    });
  });

  group('con hechos', () {
    setUp(() async {
      await seedEvent('cesar', dateOf(44, bce: true), title: 'César');
      await seedEvent('roma', dateOf(476), title: 'Caída de Roma');
      await seedEvent('constantinopla', dateOf(1453), title: 'Constantinopla');
    });

    testWidgets('muestra cada hecho con su título y cuántos hay', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(shows(tester, 'César'), isTrue);
      expect(shows(tester, 'Caída de Roma'), isTrue);
      expect(shows(tester, 'Constantinopla'), isTrue);
      expect(find.text(es.timelineEventCount(3)), findsOneWidget);
    });

    testWidgets('a.C. y d.C. se ubican sin salto: la distancia entre hechos es '
        'proporcional a los años que los separan', (tester) async {
      await pumpScreen(tester);

      final cesar = left(tester, 'César');
      final roma = left(tester, 'Caída de Roma');
      final constantinopla = left(tester, 'Constantinopla');

      expect(cesar, lessThan(roma));
      expect(roma, lessThan(constantinopla));
      // 44 a.C. → 476 son 519 años; 476 → 1453 son 977.
      expect(
        (roma - cesar) / (constantinopla - roma),
        closeTo(519 / 977, 0.02),
      );
    });

    testWidgets('tocar un hecho abre su detalle', (tester) async {
      await pumpScreen(tester);

      await tapEvent(tester, 'Caída de Roma');
      await tester.pumpAndSettle();

      expect(find.text('detalle de roma'), findsOneWidget);
    });

    testWidgets('tocar donde no hay un hecho no abre nada', (tester) async {
      await pumpScreen(tester);

      // Un punto del lienzo lejos de todo evento: hay tres, en los primeros
      // carriles.
      await tester.tapAt(tester.getTopLeft(canvasKey) + const Offset(300, 400));
      await tester.pumpAndSettle();

      expect(find.textContaining('detalle de'), findsNothing);
      expect(find.byType(TimelineCanvas), findsOneWidget);
    });

    testWidgets('cada hecho es un nodo de semántica con su título y su fecha, '
        'que se puede activar', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);

      final roma = find.semantics.byLabel('Caída de Roma, 476');
      expect(roma.evaluate(), hasLength(1));
      expect(roma.evaluate().single.flagsCollection.isButton, isTrue);
      expect(find.semantics.byLabel('César, 44 a.C.').evaluate(), hasLength(1));

      tester.semantics.tap(roma);
      await tester.pumpAndSettle();

      expect(find.text('detalle de roma'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('con el mouse encima, la ayuda dice el título y la fecha '
        'completa', (tester) async {
      await pumpScreen(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final at =
          tester.getTopLeft(canvasKey) +
          boxOf(tester, 'Caída de Roma').rect.center;

      await tester.sendEventToBinding(mouse.hover(at));
      // Todavía no: la ayuda espera un momento, como la de cualquier botón.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('timeline-tip')), findsNothing);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('timeline-tip')), findsOneWidget);
      expect(find.textContaining('Caída de Roma\n476'), findsOneWidget);

      // Al salir, se va.
      await tester.sendEventToBinding(mouse.hover(const Offset(1, 1)));
      await tester.pump();
      expect(find.byKey(const ValueKey('timeline-tip')), findsNothing);
    });

    testWidgets('con el dedo, mantener apretado un hecho muestra su ayuda', (
      tester,
    ) async {
      await pumpScreen(tester);
      final at =
          tester.getTopLeft(canvasKey) +
          boxOf(tester, 'Caída de Roma').rect.center;

      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pump();

      expect(find.byKey(const ValueKey('timeline-tip')), findsOneWidget);
      expect(find.textContaining('Caída de Roma\n476'), findsOneWidget);

      // Y se va sola, a los seis segundos: tiempo de leer una cita.
      await tester.pump(const Duration(seconds: 7));
      expect(find.byKey(const ValueKey('timeline-tip')), findsNothing);
    });

    testWidgets('mover la vista esconde la ayuda', (tester) async {
      await pumpScreen(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final at =
          tester.getTopLeft(canvasKey) +
          boxOf(tester, 'Caída de Roma').rect.center;
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('timeline-tip')), findsOneWidget);

      await tester.tap(find.byTooltip(es.timelineZoomIn));
      await tester.pump();

      expect(find.byKey(const ValueKey('timeline-tip')), findsNothing);
    });
  });

  group('imprecisión', () {
    setUp(() async {
      await seedEvent('exacta', dateOf(1000), title: 'Exacta');
      await seedEvent('circa', dateOf(1100, circa: true), title: 'Circa');
      await seedEvent(
        'decada',
        dateOf(1200, precision: DatePrecision.decade),
        title: 'Década',
      );
      await seedEvent(
        'siglo-circa',
        dateOf(1300, precision: DatePrecision.century, circa: true),
        title: 'Siglo circa',
      );
    });

    TimelineBarStyle styleOf(WidgetTester tester, String title) =>
        boxOf(tester, title).event.barStyle;

    testWidgets('cada grado de imprecisión se dibuja con su propio estilo', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(styleOf(tester, 'Exacta'), TimelineBarStyle.exact);
      expect(styleOf(tester, 'Circa'), TimelineBarStyle.approximate);
      expect(styleOf(tester, 'Década'), TimelineBarStyle.period);
      expect(
        styleOf(tester, 'Siglo circa'),
        TimelineBarStyle.approximatePeriod,
      );
    });

    testWidgets('lo aproximado tiene el borde difuso; lo exacto, no', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(boxOf(tester, 'Exacta').fuzzPx, 0);
      expect(boxOf(tester, 'Circa').fuzzPx, greaterThan(0));
      expect(boxOf(tester, 'Década').fuzzPx, 0);
      expect(boxOf(tester, 'Siglo circa').fuzzPx, greaterThan(0));
      // Y un período ocupa más eje que un año.
      expect(
        boxOf(tester, 'Década').corePx,
        greaterThan(boxOf(tester, 'Exacta').corePx),
      );
    });

    testWidgets('la leyenda explica los tres estilos', (tester) async {
      await pumpScreen(tester);

      expect(find.text(es.timelineLegendExact), findsOneWidget);
      expect(find.text(es.timelineLegendCirca), findsOneWidget);
      expect(find.text(es.timelineLegendPeriod), findsOneWidget);
    });
  });

  group('mover y acercar', () {
    // Dos hechos juntos en el centro, que siguen a la vista después de acercar
    // o de mover, y dos en los extremos que fijan el encuadre de partida.
    setUp(() async {
      await seedEvent('x', dateOf(1000), title: 'Extremo uno');
      await seedEvent('a', dateOf(1240), title: 'Uno');
      await seedEvent('b', dateOf(1260), title: 'Dos');
      await seedEvent('y', dateOf(1500), title: 'Extremo dos');
    });

    double gap(WidgetTester tester) =>
        left(tester, 'Dos') - left(tester, 'Uno');

    testWidgets('arrastrar corre el eje', (tester) async {
      await pumpScreen(tester);
      final before = left(tester, 'Uno');

      await tester.drag(find.byType(TimelineCanvas), const Offset(-150, 0));
      await tester.pumpAndSettle();

      expect(left(tester, 'Uno'), lessThan(before - 100));
    });

    testWidgets('el botón de acercar separa los hechos', (tester) async {
      await pumpScreen(tester);
      final before = gap(tester);

      await tester.tap(find.byTooltip(es.timelineZoomIn));
      await tester.pumpAndSettle();

      expect(gap(tester), greaterThan(before * 1.3));
    });

    testWidgets('el de alejar los junta', (tester) async {
      await pumpScreen(tester);
      final before = gap(tester);

      await tester.tap(find.byTooltip(es.timelineZoomOut));
      await tester.pumpAndSettle();

      expect(gap(tester), lessThan(before * 0.8));
    });

    testWidgets('mostrar todo vuelve al encuadre de partida', (tester) async {
      await pumpScreen(tester);
      final before = left(tester, 'Uno');

      await tester.tap(find.byTooltip(es.timelineZoomIn));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(TimelineCanvas), const Offset(-100, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(es.timelineFit));
      await tester.pumpAndSettle();

      expect(left(tester, 'Uno'), closeTo(before, 0.01));
    });

    testWidgets('la rueda acerca alrededor del cursor', (tester) async {
      await pumpScreen(tester);
      final before = gap(tester);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(TimelineCanvas))),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -200)));
      await tester.pumpAndSettle();

      expect(gap(tester), greaterThan(before * 1.3));
    });

    testWidgets('con el teclado: flechas para mover, + y - para acercar', (
      tester,
    ) async {
      await pumpScreen(tester);
      // El foco del teclado se pide al tocar el lienzo.
      await tester.tapAt(
        tester.getCenter(find.byType(TimelineCanvas)) + const Offset(0, 150),
      );
      await tester.pump();
      final before = left(tester, 'Uno');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(left(tester, 'Uno'), lessThan(before));

      final gapBefore = gap(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.pumpAndSettle();
      expect(gap(tester), lessThan(gapBefore));
    });

    testWidgets('no se acerca más de lo que los límites permiten', (
      tester,
    ) async {
      await pumpScreen(tester);

      for (var i = 0; i < 40; i++) {
        await tester.tap(find.byTooltip(es.timelineZoomIn));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // Nunca se rompe: la pantalla sigue mostrando el eje.
      expect(tester.takeException(), isNull);
      expect(find.byType(TimelineCanvas), findsOneWidget);
    });
  });

  group('filtros', () {
    setUp(() async {
      await seedEvent('web', dateOf(476), title: 'Imperio romano en la web');
      await seedEvent(
        'nota',
        dateOf(1453),
        title: 'Imperio bizantino',
        kind: SourceKind.manualNote,
      );
      await seedEvent('otro', dateOf(1789), title: 'Revolución francesa');
    });

    Future<void> search(WidgetTester tester, String text) async {
      await tester.enterText(
        find.widgetWithText(TextField, es.timelineSearchHint).first,
        text,
      );
      // Espera al retardo de la búsqueda y a que la consulta responda.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('buscar deja solo los hechos que coinciden', (tester) async {
      await pumpScreen(tester);

      await search(tester, 'imperio');

      expect(shows(tester, 'Imperio romano en la web'), isTrue);
      expect(shows(tester, 'Imperio bizantino'), isTrue);
      expect(shows(tester, 'Revolución francesa'), isFalse);
      expect(find.text(es.timelineEventCount(2)), findsOneWidget);
    });

    testWidgets('la búsqueda espera a que se termine de escribir', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.widgetWithText(TextField, es.timelineSearchHint).first,
        'imperio',
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Todavía no buscó: sigue viéndose todo.
      expect(shows(tester, 'Revolución francesa'), isTrue);
    });

    testWidgets('sin coincidencias avisa y ofrece quitar los filtros', (
      tester,
    ) async {
      await pumpScreen(tester);

      await search(tester, 'inexistente');

      expect(find.text(es.timelineNoResults), findsOneWidget);
      await tester.tap(find.text(es.timelineFilterClear));
      await tester.pumpAndSettle();

      expect(shows(tester, 'Revolución francesa'), isTrue);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, es.timelineSearchHint).first,
            )
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('el botón de borrar la búsqueda la limpia', (tester) async {
      await pumpScreen(tester);
      await search(tester, 'imperio');

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(shows(tester, 'Revolución francesa'), isTrue);
    });

    testWidgets('el panel filtra por tipo de elemento', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byTooltip(es.timelineFiltersTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, es.sourceKindNote));
      await tester.pumpAndSettle();

      // Cierra el panel.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(shows(tester, 'Imperio bizantino'), isTrue);
      expect(shows(tester, 'Imperio romano en la web'), isFalse);
      // El botón del panel avisa que hay un filtro puesto.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('el panel filtra por tema', (tester) async {
      final organize = harness.container.read(organizeRepositoryProvider);
      final temaId =
          (await (db.select(db.propertyDefinitions)..where(
                    (d) =>
                        d.isSystem.equals(true) &
                        d.name.equals(kTemaCategoryName),
                  ))
                  .getSingle())
              .id;
      await organize.assignProperty(
        itemId: 'otro',
        definitionId: temaId,
        value: 'Historia moderna',
      );
      await pumpScreen(tester);

      await tester.tap(find.byTooltip(es.timelineFiltersTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Historia moderna'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(shows(tester, 'Revolución francesa'), isTrue);
      expect(shows(tester, 'Imperio bizantino'), isFalse);
    });

    testWidgets('quitar los filtros desde el panel vuelve a mostrar todo', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byTooltip(es.timelineFiltersTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, es.sourceKindNote));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.timelineFilterClear));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text(es.timelineEventCount(3)), findsOneWidget);
    });
  });

  group('actualización', () {
    testWidgets('un hecho que se fecha con la pantalla abierta aparece', (
      tester,
    ) async {
      await seedEvent('a', dateOf(1000), title: 'Primero');
      await pumpScreen(tester);
      expect(shows(tester, 'Segundo'), isFalse);

      // Con un solo hecho la vista abarca diez años alrededor: 1002 entra.
      await seedEvent('b', dateOf(1002), title: 'Segundo');
      await tester.pumpAndSettle();

      expect(shows(tester, 'Segundo'), isTrue);
      expect(find.text(es.timelineEventCount(2)), findsOneWidget);
    });

    testWidgets('un hecho nuevo no mueve la vista: se cuenta, y se llega a él '
        'moviendo o con "mostrar todo"', (tester) async {
      await seedEvent('a', dateOf(1000), title: 'Primero');
      await pumpScreen(tester);
      final before = left(tester, 'Primero');

      await seedEvent('b', dateOf(1500), title: 'Lejano');
      await tester.pumpAndSettle();

      expect(find.text(es.timelineEventCount(2)), findsOneWidget);
      expect(shows(tester, 'Lejano'), isFalse);
      expect(left(tester, 'Primero'), before);

      await tester.tap(find.byTooltip(es.timelineFit));
      await tester.pumpAndSettle();

      expect(shows(tester, 'Lejano'), isTrue);
    });
  });

  group('el recorte: Todo · Tema · Documento (F40)', () {
    setUp(() async {
      await seedEvent('cesar', dateOf(44, bce: true), title: 'César');
      await seedEvent('roma', dateOf(476), title: 'Caída de Roma');
      await seedEvent('constantinopla', dateOf(1453), title: 'Constantinopla');
      await seedEvent('francia', dateOf(1789), title: 'Revolución francesa');
    });

    final all = find.byKey(const ValueKey('timeline-scope-all'));
    final topic = find.byKey(const ValueKey('timeline-scope-topic'));
    final document = find.byKey(const ValueKey('timeline-scope-document'));

    bool allSelected(WidgetTester tester) =>
        tester.widget<ChoiceChip>(all).selected;

    Future<void> chooseFrom(
      WidgetTester tester,
      Finder chip,
      String title,
    ) async {
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, title));
      await tester.pumpAndSettle();
    }

    testWidgets('por defecto se ve todo, y «Todo» es el chip marcado', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(allSelected(tester), isTrue);
      expect(find.text(es.timelineEventCount(4)), findsOneWidget);
      // Los otros dos se ofrecen sin elegir: su nombre y la flecha.
      expect(
        find.descendant(of: topic, matching: find.text(es.timelineScopeTopic)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: document,
          matching: find.text(es.timelineScopeDocument),
        ),
        findsOneWidget,
      );
      expect(tester.widget<InputChip>(topic).onDeleted, isNull);
    });

    group('Tema', () {
      setUp(() async {
        await space('Antigüedad', ['cesar', 'roma']);
        await space('Modernidad', ['francia']);
      });

      testWidgets('la hoja lista los temas con un buscador', (tester) async {
        await pumpScreen(tester);

        await tester.tap(topic);
        await tester.pumpAndSettle();

        expect(find.text(es.timelineTopicSheetTitle), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Antigüedad'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Modernidad'), findsOneWidget);
        expect(
          find.widgetWithText(TextField, es.timelineTopicSearchHint),
          findsOneWidget,
        );
      });

      testWidgets('el buscador no distingue mayúsculas ni acentos', (
        tester,
      ) async {
        await pumpScreen(tester);
        await tester.tap(topic);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, es.timelineTopicSearchHint),
          'antiguedad',
        );
        await tester.pumpAndSettle();

        expect(find.widgetWithText(ListTile, 'Antigüedad'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Modernidad'), findsNothing);
      });

      testWidgets('lo buscado que no existe lo dice', (tester) async {
        await pumpScreen(tester);
        await tester.tap(topic);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, es.timelineTopicSearchHint),
          'zzz',
        );
        await tester.pumpAndSettle();

        expect(find.text(es.timelinePickerNoMatch), findsOneWidget);
      });

      testWidgets('elegir un tema deja solo sus hechos, y el chip dice cuál', (
        tester,
      ) async {
        await pumpScreen(tester);

        await chooseFrom(tester, topic, 'Antigüedad');

        expect(shows(tester, 'César'), isTrue);
        expect(shows(tester, 'Caída de Roma'), isTrue);
        expect(shows(tester, 'Constantinopla'), isFalse);
        expect(find.text(es.timelineEventCount(2)), findsOneWidget);
        expect(
          find.descendant(of: topic, matching: find.text('Antigüedad')),
          findsOneWidget,
        );
        expect(allSelected(tester), isFalse);
      });

      testWidgets('la «×» del chip quita el tema y vuelve a «Todo»', (
        tester,
      ) async {
        await pumpScreen(tester);
        await chooseFrom(tester, topic, 'Antigüedad');

        await tester.tap(find.byTooltip(es.timelineBranchFilterTooltip));
        await tester.pumpAndSettle();

        expect(find.text(es.timelineEventCount(4)), findsOneWidget);
        expect(allSelected(tester), isTrue);
        expect(
          find.descendant(
            of: topic,
            matching: find.text(es.timelineScopeTopic),
          ),
          findsOneWidget,
        );
      });

      testWidgets('tocar «Todo» también lo quita', (tester) async {
        await pumpScreen(tester);
        await chooseFrom(tester, topic, 'Antigüedad');

        await tester.tap(all);
        await tester.pumpAndSettle();

        expect(find.text(es.timelineEventCount(4)), findsOneWidget);
        expect(allSelected(tester), isTrue);
      });

      testWidgets('elegir un tema conserva lo buscado', (tester) async {
        await pumpScreen(tester);
        await tester.enterText(
          find.widgetWithText(TextField, es.timelineSearchHint).first,
          'césar',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await chooseFrom(tester, topic, 'Antigüedad');

        expect(find.text(es.timelineEventCount(1)), findsOneWidget);
        expect(shows(tester, 'César'), isTrue);
      });
    });

    group('Documento', () {
      setUp(() async {
        // Un documento con dos fechas.
        await addDate('roma', dateOf(410));
      });

      testWidgets('la hoja lista los documentos con fechas, cada uno con '
          'cuántas tiene y de cuándo a cuándo', (tester) async {
        await harness.container
            .read(libraryRepositoryProvider)
            .save(
              KnowledgeItem(
                id: 'sin-fecha',
                title: 'Sin fecha',
                source: Source(
                  id: 's',
                  kind: SourceKind.webPage,
                  capturedAt: now,
                  url: 'https://e.org',
                ),
                processingState: ProcessingState.ready,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await pumpScreen(tester);

        await tester.tap(document);
        await tester.pumpAndSettle();

        expect(find.text(es.timelineDocumentSheetTitle), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Caída de Roma'), findsOneWidget);
        expect(
          find.text(es.timelineDocumentSubtitle(2, '410 – 476')),
          findsOneWidget,
        );
        expect(
          find.text(es.timelineDocumentSubtitle(1, '1453')),
          findsOneWidget,
        );
        // Sin ninguna fecha no tiene qué hacer en la línea de tiempo.
        expect(find.widgetWithText(ListTile, 'Sin fecha'), findsNothing);
      });

      testWidgets('elegir un documento deja solo sus hechos', (tester) async {
        await pumpScreen(tester);

        await chooseFrom(tester, document, 'Caída de Roma');

        // Las dos fechas del documento, y nada más.
        expect(find.text(es.timelineEventCount(2)), findsOneWidget);
        expect(shows(tester, 'César'), isFalse);
        expect(frameOf(tester).boxes.map((b) => b.event.itemId).toSet(), {
          'roma',
        });
        expect(
          find.descendant(of: document, matching: find.text('Caída de Roma')),
          findsOneWidget,
        );
      });

      testWidgets('encuadra su época: la vista se cierra sobre sus fechas', (
        tester,
      ) async {
        await pumpScreen(tester);
        final wide = frameOf(tester).boxes.length;

        await chooseFrom(tester, document, 'Caída de Roma');

        // Con todo a la vista el eje cubría desde 44 a.C. hasta 1789; ahora
        // abarca poco más que 410–476, así que los dos hechos están muy
        // separados entre sí y bien adentro de la pantalla.
        final boxes = frameOf(tester).boxes;
        expect(wide, 5);
        expect(boxes, hasLength(2));
        final canvasWidth = tester.getSize(canvasKey).width;
        for (final box in boxes) {
          expect(box.rect.left, greaterThan(0));
          expect(box.rect.left, lessThan(canvasWidth - 20));
        }
        expect(
          boxes.last.rect.left - boxes.first.rect.left,
          greaterThan(canvasWidth / 2),
        );
      });

      testWidgets('cambiar de documento reemplaza al anterior', (tester) async {
        await pumpScreen(tester);
        await chooseFrom(tester, document, 'Caída de Roma');

        await chooseFrom(tester, document, 'César');

        expect(find.text(es.timelineEventCount(1)), findsOneWidget);
        expect(shows(tester, 'César'), isTrue);
      });

      testWidgets('elegir un documento después de un tema reemplaza al tema', (
        tester,
      ) async {
        await space('Antigüedad', ['cesar']);
        await pumpScreen(tester);
        await chooseFrom(tester, topic, 'Antigüedad');

        await chooseFrom(tester, document, 'Caída de Roma');

        expect(
          find.descendant(
            of: topic,
            matching: find.text(es.timelineScopeTopic),
          ),
          findsOneWidget,
        );
        expect(shows(tester, 'César'), isFalse);
        expect(shows(tester, 'Caída de Roma'), isTrue);
      });
    });
  });

  group('sin documentos con fechas (F40)', () {
    testWidgets(
      'la hoja de «Documento» lo dice, y una sin fechas no se ofrece',
      (tester) async {
        await harness.container
            .read(libraryRepositoryProvider)
            .save(
              KnowledgeItem(
                id: 'sin-fecha',
                title: 'Sin fecha',
                source: Source(
                  id: 's',
                  kind: SourceKind.webPage,
                  capturedAt: now,
                  url: 'https://e.org',
                ),
                processingState: ProcessingState.ready,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await pumpScreen(tester);

        await tester.tap(find.byKey(const ValueKey('timeline-scope-document')));
        await tester.pumpAndSettle();

        expect(find.text(es.timelineDocumentsEmpty), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Sin fecha'), findsNothing);
      },
    );

    testWidgets('la hoja de «Tema» sin temas lo dice', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const ValueKey('timeline-scope-topic')));
      await tester.pumpAndSettle();

      expect(find.text(es.timelineTopicsEmpty), findsOneWidget);
    });
  });

  group('el filtro tiene un solo dueño (F40)', () {
    setUp(() async {
      await seedEvent('cesar', dateOf(44, bce: true), title: 'César');
      await seedEvent('roma', dateOf(476), title: 'Caída de Roma');
      await seedEvent('constantinopla', dateOf(1453), title: 'Constantinopla');
    });

    TimelineFilterNotifier owner() =>
        harness.container.read(timelineFilterProvider.notifier);

    testWidgets('un filtro fijado antes de que la pantalla exista se ve al '
        'abrirla', (tester) async {
      owner().focusOn(
        const TimelineScope.document(itemId: 'roma', label: 'Caída de Roma'),
      );

      await pumpScreen(tester);

      expect(find.text(es.timelineEventCount(1)), findsOneWidget);
      expect(shows(tester, 'Caída de Roma'), isTrue);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('timeline-scope-document')),
          matching: find.text('Caída de Roma'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('fijarlo con la pantalla ya armada la actualiza: no depende '
        'de que se construya de nuevo', (tester) async {
      await pumpScreen(tester);
      expect(find.text(es.timelineEventCount(3)), findsOneWidget);

      owner().focusOn(
        const TimelineScope.document(itemId: 'cesar', label: 'César'),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.timelineEventCount(1)), findsOneWidget);
      expect(shows(tester, 'César'), isTrue);
    });

    testWidgets('una rama del Atlas tiene su chip, y se quita', (tester) async {
      owner().focusOn(
        const TimelineScope.branch(valueId: 'no-existe', label: 'Imperio'),
      );
      await pumpScreen(tester);

      final chip = find.byKey(const ValueKey('timeline-scope-branch'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text('Imperio')),
        findsOneWidget,
      );
      // Esa rama no tiene ningún hecho.
      expect(find.text(es.timelineNoResults), findsOneWidget);

      await tester.tap(find.byTooltip(es.timelineBranchFilterTooltip));
      await tester.pumpAndSettle();

      expect(chip, findsNothing);
      expect(find.text(es.timelineEventCount(3)), findsOneWidget);
    });

    testWidgets('abrirla recortada borra lo que se había buscado, también en '
        'el campo de texto', (tester) async {
      await pumpScreen(tester);
      final field = find.widgetWithText(TextField, es.timelineSearchHint);
      await tester.enterText(field.first, 'césar');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text(es.timelineEventCount(1)), findsOneWidget);

      owner().focusOn(
        const TimelineScope.document(itemId: 'roma', label: 'Caída de Roma'),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(field.first).controller!.text, isEmpty);
      expect(find.text(es.timelineEventCount(1)), findsOneWidget);
      expect(shows(tester, 'Caída de Roma'), isTrue);
    });

    testWidgets('lo que se escribe en el campo no se pisa a sí mismo', (
      tester,
    ) async {
      await pumpScreen(tester);
      final field = find.widgetWithText(TextField, es.timelineSearchHint);

      await tester.enterText(field.first, 'Caída de Roma ');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(field.first).controller!.text,
        'Caída de Roma ',
      );
    });

    testWidgets('el panel quita solo lo suyo: ni el recorte ni la búsqueda', (
      tester,
    ) async {
      owner()
        ..focusOn(
          const TimelineScope.document(itemId: 'roma', label: 'Caída de Roma'),
        )
        ..toggleSourceKind(SourceKind.webPage);
      await pumpScreen(tester);

      await tester.tap(find.byTooltip(es.timelineFiltersTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.timelineFilterClear));
      await tester.pumpAndSettle();

      final filter = harness.container.read(timelineFilterProvider);
      expect(filter.sourceKinds, isEmpty);
      expect(filter.scope?.id, 'roma');
    });
  });

  group('el encuadre se mueve, no salta (F40)', () {
    setUp(() async {
      await seedEvent('x', dateOf(1000), title: 'Extremo uno');
      await seedEvent('a', dateOf(1240), title: 'Uno');
      await seedEvent('b', dateOf(1260), title: 'Dos');
      await seedEvent('y', dateOf(1500), title: 'Extremo dos');
    });

    Future<void> zoomIn(WidgetTester tester, [int times = 3]) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.byTooltip(es.timelineZoomIn));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('«Mostrar todo» pasa por vistas intermedias hasta la de '
        'siempre', (tester) async {
      await pumpScreen(tester);
      final fitted = left(tester, 'Uno');
      await zoomIn(tester);
      final zoomed = left(tester, 'Uno');
      expect(zoomed, isNot(closeTo(fitted, 1)));

      await tester.tap(find.byTooltip(es.timelineFit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // En el camino: ni donde estaba ni donde va.
      final midway = left(tester, 'Uno');
      expect((midway - zoomed).abs(), greaterThan(1));
      expect((midway - fitted).abs(), greaterThan(1));
      expect(
        midway,
        inInclusiveRange(
          fitted < zoomed ? fitted : zoomed,
          fitted < zoomed ? zoomed : fitted,
        ),
      );

      await tester.pumpAndSettle();
      expect(left(tester, 'Uno'), closeTo(fitted, 0.01));
    });

    testWidgets('con las animaciones apagadas del sistema, de golpe', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpScreen(tester);
      final fitted = left(tester, 'Uno');
      await zoomIn(tester);

      await tester.tap(find.byTooltip(es.timelineFit));
      await tester.pump();

      expect(left(tester, 'Uno'), closeTo(fitted, 0.01));
    });

    testWidgets('tocar la pantalla en medio del movimiento lo corta', (
      tester,
    ) async {
      await pumpScreen(tester);
      await zoomIn(tester);
      await tester.tap(find.byTooltip(es.timelineFit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Un pellizco o un arrastre toma el control: la vista obedece al dedo y
      // el movimiento que venía no la sigue arrastrando.
      await tester.drag(find.byType(TimelineCanvas), const Offset(-120, 0));
      await tester.pump();
      final afterDrag = left(tester, 'Uno');
      await tester.pumpAndSettle();

      expect(left(tester, 'Uno'), closeTo(afterDrag, 0.01));
    });

    testWidgets('cambiar el filtro mueve el eje hasta encuadrar lo que quedó, '
        'sin desarmar el lienzo ni mostrar la espera', (tester) async {
      final queries = <LibraryQuery, StreamController<List<TimelineEvent>>>{};
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          timelineEventsProvider.overrideWith((ref, query) {
            final controller = StreamController<List<TimelineEvent>>();
            ref.onDispose(controller.close);
            queries[query] = controller;
            return controller.stream;
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router(),
          ),
        ),
      );
      queries[const LibraryQuery(scope: LibraryScope.processed)]!.add([
        eventAt('a', dateOf(100), title: 'Antiguo'),
        eventAt('b', dateOf(1900), title: 'Moderno'),
      ]);
      await tester.pumpAndSettle();
      final canvas = tester.state(find.byType(TimelineCanvas));
      final before = left(tester, 'Antiguo');

      container
          .read(timelineFilterProvider.notifier)
          .focusOn(const TimelineScope.document(itemId: 'b', label: 'Moderno'));
      await tester.pump();

      // La consulta nueva todavía no respondió: el eje sigue ahí, quieto, y no
      // hay un giro de espera en su lugar.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.state(find.byType(TimelineCanvas)), same(canvas));
      expect(left(tester, 'Antiguo'), before);

      queries[container.read(timelineFilterProvider).query]!.add([
        eventAt('b', dateOf(1900), title: 'Moderno'),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Se está moviendo hacia la época del documento elegido.
      expect(tester.state(find.byType(TimelineCanvas)), same(canvas));
      expect(shows(tester, 'Moderno'), isTrue);
      final mid = left(tester, 'Moderno');

      await tester.pumpAndSettle();
      final end = left(tester, 'Moderno');
      expect(end, isNot(closeTo(mid, 1)));
      // Al final, el único hecho queda en el medio de la pantalla.
      final box = boxOf(tester, 'Moderno');
      expect(box.rect.center.dx, closeTo(450, 60));
    });

    group('doble toque', () {
      Offset empty(WidgetTester tester) =>
          tester.getTopLeft(canvasKey) + const Offset(200, 500);

      testWidgets('acerca ahí con el mismo paso que el «+»', (tester) async {
        await pumpScreen(tester);
        final point = empty(tester);
        final x = point.dx - tester.getTopLeft(canvasKey).dx;
        final before = left(tester, 'Uno');
        final gapBefore = left(tester, 'Dos') - before;

        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(point);
        await tester.pumpAndSettle();

        // 1,5 veces más cerca...
        expect(
          left(tester, 'Dos') - left(tester, 'Uno'),
          closeTo(gapBefore * 1.5, 0.05),
        );
        // ...alrededor del punto tocado: lo que estaba bajo el dedo sigue ahí.
        expect(left(tester, 'Uno'), closeTo(x + (before - x) * 1.5, 0.05));
      });

      testWidgets('un solo toque en el fondo no acerca', (tester) async {
        await pumpScreen(tester);
        final before = left(tester, 'Uno');

        await tester.tapAt(empty(tester));
        await tester.pumpAndSettle();

        expect(left(tester, 'Uno'), before);
      });

      testWidgets('dos toques con tiempo de por medio son dos toques '
          'simples', (tester) async {
        await pumpScreen(tester);
        final before = left(tester, 'Uno');

        await tester.tapAt(empty(tester));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tapAt(empty(tester));
        await tester.pumpAndSettle();

        expect(left(tester, 'Uno'), before);
      });

      testWidgets('dos toques lejos uno del otro tampoco', (tester) async {
        await pumpScreen(tester);
        final before = left(tester, 'Uno');

        await tester.tapAt(empty(tester));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(empty(tester) + const Offset(300, 0));
        await tester.pumpAndSettle();

        expect(left(tester, 'Uno'), before);
      });

      testWidgets('tocar un hecho lo abre al instante: el doble toque no '
          'retrasa el simple', (tester) async {
        await pumpScreen(tester);

        await tapEvent(tester, 'Uno');
        // Sin esperar el tiempo del segundo toque.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('detalle de a'), findsOneWidget);
      });
    });

    group('mini mapa', () {
      final minimap = find.byKey(const ValueKey('timeline-minimap'));

      TimelineMinimapPainter painterOf(WidgetTester tester) =>
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: minimap,
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as TimelineMinimapPainter;

      testWidgets('está arriba del eje, con todo el rango a la vista', (
        tester,
      ) async {
        await pumpScreen(tester);

        expect(minimap, findsOneWidget);
        expect(
          tester.getBottomLeft(minimap).dy,
          lessThan(tester.getTopLeft(canvasKey).dy + 1),
        );
        final painter = painterOf(tester);
        // Con todo encuadrado, la ventana abarca casi todo el ancho.
        expect(painter.windowTo - painter.windowFrom, greaterThan(0.85));
      });

      testWidgets('la ventana marcada se achica y se corre con la vista', (
        tester,
      ) async {
        await pumpScreen(tester);
        final all = painterOf(tester);

        await zoomIn(tester);
        final zoomed = painterOf(tester);

        expect(
          zoomed.windowTo - zoomed.windowFrom,
          lessThan((all.windowTo - all.windowFrom) / 2),
        );

        await tester.drag(find.byType(TimelineCanvas), const Offset(-200, 0));
        await tester.pumpAndSettle();
        expect(painterOf(tester).windowFrom, greaterThan(zoomed.windowFrom));
      });

      testWidgets('la densidad se arma con la lista de hechos, no en cada '
          'cuadro: arrastrar y acercar no la recalculan', (tester) async {
        await pumpScreen(tester);
        final density = painterOf(tester).density;

        await zoomIn(tester);
        await tester.drag(find.byType(TimelineCanvas), const Offset(-150, 0));
        await tester.pumpAndSettle();

        expect(painterOf(tester).density, same(density));
      });

      testWidgets('tocarlo lleva la vista a esa época', (tester) async {
        await pumpScreen(tester);
        await zoomIn(tester, 4);
        expect(shows(tester, 'Extremo dos'), isFalse);

        final box = tester.getRect(minimap);
        await tester.tapAt(Offset(box.left + box.width * 0.97, box.center.dy));
        await tester.pumpAndSettle();

        expect(shows(tester, 'Extremo dos'), isTrue);
        expect(shows(tester, 'Uno'), isFalse);
      });

      testWidgets('tocarlo se desliza hasta esa época: pasa por vistas '
          'intermedias', (tester) async {
        await pumpScreen(tester);
        await zoomIn(tester, 4);
        final start = painterOf(tester);
        final startCenter = (start.windowFrom + start.windowTo) / 2;

        final box = tester.getRect(minimap);
        await tester.tapAt(Offset(box.left + box.width * 0.95, box.center.dy));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        final mid = painterOf(tester);
        final midCenter = (mid.windowFrom + mid.windowTo) / 2;
        expect(midCenter, greaterThan(startCenter + 0.01));
        expect(midCenter, lessThan(0.94));

        await tester.pumpAndSettle();
        final end = painterOf(tester);
        expect((end.windowFrom + end.windowTo) / 2, closeTo(0.95, 0.02));
      });

      testWidgets('arrastrarlo no se anima: sigue al dedo en el mismo cuadro', (
        tester,
      ) async {
        await pumpScreen(tester);
        await zoomIn(tester, 4);

        final box = tester.getRect(minimap);
        final gesture = await tester.startGesture(
          Offset(box.left + box.width * 0.4, box.center.dy),
        );
        await gesture.moveTo(Offset(box.left + box.width * 0.6, box.center.dy));
        await gesture.moveTo(Offset(box.left + box.width * 0.9, box.center.dy));
        await tester.pump();

        final window = painterOf(tester);
        expect((window.windowFrom + window.windowTo) / 2, closeTo(0.9, 0.02));
        await gesture.up();
        await tester.pumpAndSettle();
      });

      testWidgets('tocarlo no cambia el zoom', (tester) async {
        await pumpScreen(tester);
        await zoomIn(tester, 2);
        final span = painterOf(tester);
        final width = span.windowTo - span.windowFrom;

        final box = tester.getRect(minimap);
        await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
        await tester.pumpAndSettle();

        final after = painterOf(tester);
        expect(after.windowTo - after.windowFrom, closeTo(width, 1e-9));
      });

      testWidgets('arrastrarlo mueve la vista con el dedo', (tester) async {
        await pumpScreen(tester);
        await zoomIn(tester, 4);
        final before = painterOf(tester).windowFrom;

        final box = tester.getRect(minimap);
        await tester.dragFrom(
          Offset(box.left + box.width * 0.2, box.center.dy),
          Offset(box.width * 0.77, 0),
        );
        await tester.pumpAndSettle();

        // La ventana queda centrada donde se soltó el dedo: al 97 % del ancho.
        final after = painterOf(tester);
        expect(after.windowFrom, greaterThan(before));
        expect((after.windowFrom + after.windowTo) / 2, closeTo(0.97, 0.02));
        expect(shows(tester, 'Extremo dos'), isTrue);
      });
    });
  });

  testWidgets('el botón de filtros cuenta solo los del panel: el recorte tiene '
      'su propio chip', (tester) async {
    await seedEvent('roma', dateOf(476), title: 'Caída de Roma');
    harness.container
        .read(timelineFilterProvider.notifier)
        .focusOn(
          const TimelineScope.document(itemId: 'roma', label: 'Caída de Roma'),
        );
    await pumpScreen(tester);

    final badge = tester.widget<Badge>(
      find.descendant(
        of: find.byTooltip(es.timelineFiltersTooltip),
        matching: find.byType(Badge),
      ),
    );
    expect(badge.isLabelVisible, isFalse);
  });

  testWidgets('el lienzo le pasa al pintor cómo colorear cada hecho (colores '
      'por documento)', (tester) async {
    Color byDocument(TimelineEvent event) =>
        event.itemId == 'a' ? Colors.red : Colors.blue;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TimelineCanvas(
            events: [eventAt('a', dateOf(1000)), eventAt('b', dateOf(1010))],
            onOpen: (_) {},
            colorOf: byDocument,
          ),
        ),
      ),
    );

    final painter =
        tester.widget<CustomPaint>(canvasKey).painter! as TimelineEventsPainter;
    expect(painter.colorOf, same(byDocument));
  });

  testWidgets('tocar un hecho entrega el evento entero, para decidir qué '
      'abrir', (tester) async {
    final opened = <TimelineEvent>[];
    final event = eventAt('a', dateOf(1000), title: 'Uno');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TimelineCanvas(events: [event], onOpen: opened.add),
        ),
      ),
    );

    await tapEvent(tester, 'Uno');

    expect(opened, [event]);
  });

  group('escala', () {
    /// Diez mil hechos sin pasar por la base: lo que se prueba es cuánto
    /// dibuja la pantalla, no cuánto tarda en guardarse.
    List<TimelineEvent> tenThousand() => [
      for (var i = 0; i < 10000; i++)
        eventAt(
          'e$i',
          dateOf(1 + (i * 7) % 2000, bce: i % 5 == 0),
          title: 'Hecho $i',
        ),
    ];

    Future<void> pumpWith(
      WidgetTester tester,
      List<TimelineEvent> events, {
      required Size size,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timelineEventsProvider.overrideWith(
              (ref, filter) => Stream.value(events),
            ),
          ],
          child: MaterialApp.router(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('con diez mil hechos solo se dibuja lo que se ve', (
      tester,
    ) async {
      await pumpWith(tester, tenThousand(), size: const Size(900, 900));

      final built = frameOf(tester).boxes.length;

      expect(built, greaterThan(0));
      expect(built, lessThan(400));
      expect(find.text(es.timelineEventCount(10000)), findsOneWidget);
    });

    testWidgets('diez mil hechos, uno de cada tres un tramo, también se '
        'dibujan solo los que se ven (F40)', (tester) async {
      final mixed = [
        for (final (i, event) in tenThousand().indexed)
          if (i % 3 == 0)
            event.copyWith(
              datedEventId: 'h$i',
              end: event.date.copyWith(
                precision: DatePrecision.century,
                month: null,
                day: null,
                isCirca: false,
              ),
            )
          else
            event,
      ];
      await pumpWith(tester, mixed, size: const Size(900, 900));

      final boxes = frameOf(tester).boxes;
      expect(boxes.length, greaterThan(0));
      expect(boxes.length, lessThan(400));
      expect(
        boxes.any((box) => box.event.barStyle == TimelineBarStyle.range),
        isTrue,
      );
      expect(find.text(es.timelineEventCount(10000)), findsOneWidget);

      // Y acercar y mover sigue igual de liviano.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip(es.timelineZoomIn));
        await tester.pump();
      }
      await tester.drag(find.byType(TimelineCanvas), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(frameOf(tester).boxes.length, lessThan(400));
    });

    testWidgets('acercar y mover con diez mil hechos sigue dibujando poco', (
      tester,
    ) async {
      await pumpWith(tester, tenThousand(), size: const Size(900, 900));

      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byTooltip(es.timelineZoomIn));
        await tester.pump();
      }
      await tester.drag(find.byType(TimelineCanvas), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(frameOf(tester).boxes.length, lessThan(400));
    });

    testWidgets('con diez mil hechos el mini mapa está y su densidad no se '
        'recalcula al mover la vista', (tester) async {
      await pumpWith(tester, tenThousand(), size: const Size(900, 900));
      TimelineMinimapPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byKey(const ValueKey('timeline-minimap')),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as TimelineMinimapPainter;
      final density = painter().density;

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip(es.timelineZoomIn));
        await tester.pump();
      }
      await tester.drag(find.byType(TimelineCanvas), const Offset(-250, 0));
      await tester.pumpAndSettle();

      expect(painter().density, same(density));
      expect(density.levels.where((l) => l > 0).length, greaterThan(20));
    });

    testWidgets('lo que no cabe se cuenta y se avisa', (tester) async {
      // Treinta hechos en el mismo año, en una ventana baja: no hay carriles
      // para todos.
      final crowd = [
        for (var i = 0; i < 30; i++) eventAt('c$i', dateOf(500), title: 'C$i'),
      ];
      await pumpWith(tester, crowd, size: const Size(900, 500));

      final shown = frameOf(tester).boxes.length;

      expect(shown, lessThan(30));
      expect(find.text(es.timelineHidden(30 - shown)), findsOneWidget);
    });
  });

  testWidgets('se abre con el router real, como un destino de la barra, en '
      '«Organizar» arriba del Atlas (F40)', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.goTo(RoutePaths.timeline);
    await tester.pumpAndSettle();

    expect(find.byType(TimelineScreen), findsOneWidget);
    // Con la barra: ya no se abre encima de ella.
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(
      (rail.destinations[rail.selectedIndex!].label as Text).data,
      es.navTimeline,
    );
  });

  testWidgets('desde el riel se llega a ella con "Todo" y sin filtros', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();

    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(harness.container.read(timelineFilterProvider).scope, isNull);
  });
}
