import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_density.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_viewport.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_minimap.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../timeline_fixtures.dart';

/// El mini mapa de la línea de tiempo (F40): la densidad de hechos de todo el
/// rango, con la ventana que se ve marcada.
void main() {
  final es = AppLocalizationsEs();

  // Datos de 1000 a 2000, con la mayoría de los hechos al principio.
  final density = TimelineDensity.of(
    [
      for (var i = 0; i < 6; i++) eventAt('a$i', dateOf(1000 + i)),
      eventAt('z', dateOf(1999)),
    ],
    from: 1000,
    to: 2000,
    bins: 10,
  );

  TimelineMinimapPainter painter({
    double windowFrom = 0.25,
    double windowTo = 0.5,
    TimelineDensity? density_,
    Color bar = Colors.teal,
  }) => TimelineMinimapPainter(
    density: density_ ?? density,
    windowFrom: windowFrom,
    windowTo: windowTo,
    barColor: bar,
    windowColor: Colors.indigo,
    trackColor: Colors.grey,
  );

  group('la ventana', () {
    test('ocupa la parte del ancho que se está viendo', () {
      final window = painter().visibleWindow(400);

      expect(window.left, 100);
      expect(window.right, 200);
    });

    test('una vista que se sale de los datos se recorta al ancho', () {
      final window = painter(
        windowFrom: -0.5,
        windowTo: 1.5,
      ).visibleWindow(400);

      expect(window.left, 0);
      expect(window.right, 400);
    });

    test('con mucho zoom no se vuelve una raya: tiene un mínimo para poder '
        'agarrarla', () {
      final window = painter(
        windowFrom: 0.5,
        windowTo: 0.5001,
      ).visibleWindow(400);

      expect(window.width, TimelineMinimapPainter.minWindowWidth);
    });

    test('el mínimo tampoco la saca del lienzo en el borde derecho', () {
      final window = painter(
        windowFrom: 0.9999,
        windowTo: 1,
      ).visibleWindow(400);

      expect(window.width, TimelineMinimapPainter.minWindowWidth);
      expect(window.right, lessThanOrEqualTo(400));
    });
  });

  group('lo que dibuja', () {
    testWidgets('una barra por tramo con hechos, y la ventana', (tester) async {
      // Seis tramos vacíos y cuatro con hechos (los dos extremos y dos más).
      final sparse = TimelineDensity.of(
        [
          eventAt('a', dateOf(1000)),
          eventAt('b', dateOf(1250)),
          eventAt('c', dateOf(1500)),
          eventAt('d', dateOf(1999)),
        ],
        from: 1000,
        to: 2000,
        bins: 10,
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          // Arriba a la izquierda y no centrado: las medidas de abajo son las
          // del lienzo, desde su esquina.
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: kTimelineMinimapHeight,
              child: CustomPaint(
                key: const ValueKey('mm'),
                painter: painter(density_: sparse),
              ),
            ),
          ),
        ),
      );

      // Las cuatro barras con hechos y los dos rectángulos de la ventana
      // (relleno y borde): los tramos vacíos no dibujan nada.
      expect(
        tester.renderObject(find.byKey(const ValueKey('mm'))),
        paintsExactlyCountTimes(#drawRect, 6),
      );
    });

    testWidgets('un tramo con un solo hecho entre muchos no desaparece: tiene '
        'una altura mínima', (tester) async {
      final lopsided = TimelineDensity.of(
        [
          for (var i = 0; i < 10000; i++) eventAt('m$i', dateOf(1000)),
          eventAt('solo', dateOf(1999)),
        ],
        from: 1000,
        to: 2000,
        bins: 10,
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          // Arriba a la izquierda y no centrado: las medidas de abajo son las
          // del lienzo, desde su esquina.
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: kTimelineMinimapHeight,
              child: CustomPaint(
                key: const ValueKey('mm'),
                painter: painter(density_: lopsided),
              ),
            ),
          ),
        ),
      );

      // Primero la barra de los diez mil, entera; después la última: 40 px de
      // ancho, pegada abajo, de 3 px de alto.
      expect(
        tester.renderObject(find.byKey(const ValueKey('mm'))),
        paints
          ..rect(
            rect: const Rect.fromLTWH(0, 6, 40, kTimelineMinimapHeight - 6),
          )
          ..rect(
            rect: const Rect.fromLTWH(360, kTimelineMinimapHeight - 3, 40, 3),
          ),
      );
    });
  });

  group('cuándo se repinta', () {
    test('si se mueve la ventana o cambian los colores', () {
      final original = painter();

      expect(painter().shouldRepaint(original), isFalse);
      expect(painter(windowFrom: 0.3).shouldRepaint(original), isTrue);
      expect(painter(windowTo: 0.6).shouldRepaint(original), isTrue);
      expect(painter(bar: Colors.red).shouldRepaint(original), isTrue);
    });

    test('si llegan otros hechos (otra densidad)', () {
      final otherDensity = TimelineDensity.of(
        const [],
        from: 1000,
        to: 2000,
        bins: 10,
      );

      expect(painter(density_: otherDensity).shouldRepaint(painter()), isTrue);
    });
  });

  group('en pantalla', () {
    Future<void> pumpMinimap(
      WidgetTester tester, {
      TimelineViewport viewport = const TimelineViewport(from: 1250, to: 1500),
      ValueChanged<double>? onJumpTo,
      ValueChanged<double>? onDragTo,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: TimelineMinimap(
                  density: density,
                  viewport: viewport,
                  onJumpTo: onJumpTo ?? (_) {},
                  onDragTo: onDragTo ?? (_) {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    final minimap = find.byKey(const ValueKey('timeline-minimap'));

    testWidgets('dibuja la ventana donde está la vista', (tester) async {
      await pumpMinimap(tester);

      final paint = tester.widget<CustomPaint>(
        find.descendant(of: minimap, matching: find.byType(CustomPaint)),
      );
      final painted = paint.painter! as TimelineMinimapPainter;

      expect(painted.windowFrom, closeTo(0.25, 1e-9));
      expect(painted.windowTo, closeTo(0.5, 1e-9));
      expect(painted.density, same(density));
    });

    testWidgets('tocarlo salta al año tocado', (tester) async {
      final jumps = <double>[];
      await pumpMinimap(tester, onJumpTo: jumps.add);

      // Tres cuartos del ancho: 1750.
      await tester.tapAt(tester.getTopLeft(minimap) + const Offset(300, 20));

      expect(jumps, hasLength(1));
      expect(jumps.single, closeTo(1750, 1));
    });

    testWidgets('arrastrarlo sigue al dedo, sin saltar (no es un toque)', (
      tester,
    ) async {
      final jumps = <double>[];
      final drags = <double>[];
      await pumpMinimap(tester, onJumpTo: jumps.add, onDragTo: drags.add);

      await tester.dragFrom(
        tester.getTopLeft(minimap) + const Offset(100, 20),
        const Offset(200, 0),
      );

      expect(jumps, isEmpty);
      expect(drags, isNotEmpty);
      // Termina donde se soltó el dedo: 300 de 400 píxeles.
      expect(drags.last, closeTo(1750, 1));
      // Va en el sentido del dedo.
      expect(drags, orderedEquals([...drags]..sort()));
    });

    testWidgets('un toque fuera del rango (el borde) no da un año fuera de los '
        'datos', (tester) async {
      final jumps = <double>[];
      await pumpMinimap(tester, onJumpTo: jumps.add);

      await tester.tapAt(tester.getTopLeft(minimap) + const Offset(399, 20));

      expect(jumps.single, lessThanOrEqualTo(2000));
      expect(jumps.single, greaterThan(1990));
    });

    testWidgets('tiene su lectura de accesibilidad', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMinimap(tester);

      expect(find.bySemanticsLabel(es.timelineMinimapLabel), findsOneWidget);
      handle.dispose();
    });
  });
}
