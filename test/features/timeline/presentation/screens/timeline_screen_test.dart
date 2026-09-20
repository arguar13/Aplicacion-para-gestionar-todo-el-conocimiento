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
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_canvas.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_events_painter.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_frame.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
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

  /// Guarda un elemento y le pone [date] como "Fecha del hecho", por el
  /// camino de la app.
  Future<void> seedEvent(
    String id,
    HistoricalDate date, {
    String? title,
    SourceKind kind = SourceKind.webPage,
  }) async {
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: title ?? 'Hecho $id',
            source: Source(
              id: 'src-$id',
              kind: kind,
              capturedAt: now,
              url: kind == SourceKind.manualNote ? null : 'https://e.org/$id',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
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

      // Y se va sola.
      await tester.pump(const Duration(seconds: 4));
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

  testWidgets('se abre con el router real', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.goTo(RoutePaths.timeline);
    await tester.pumpAndSettle();

    expect(find.byType(TimelineScreen), findsOneWidget);
  });
}
