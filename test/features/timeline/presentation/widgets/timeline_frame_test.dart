import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/features/timeline/domain/services/lane_layout.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_events_painter.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_frame.dart';

import '../../timeline_fixtures.dart';

/// El cuadro de la línea de tiempo (F12): dónde queda cada evento en píxeles,
/// qué se toca y cómo se dibuja. Es lo que antes eran cientos de widgets, y lo
/// que ahora se dibuja en un solo lienzo; estas pruebas fijan lo que ese lienzo
/// tiene que respetar.
void main() {
  // 10 píxeles por año, la vista empieza en el año 1000.
  const from = 1000.0;
  const pxPerYear = 10.0;
  const top = 8.0;

  TimelineFrame place(
    List<PlacedEvent> placed, {
    double labelYears = 0,
    double viewFrom = from,
  }) => TimelineFrame.place(
    placed,
    from: viewFrom,
    pxPerYear: pxPerYear,
    top: top,
    labelYears: (_) => labelYears,
  );

  group('dónde queda cada evento', () {
    test('proporcional a los años, con el carril como altura', () {
      final a = eventAt('a', dateOf(1010));
      final b = eventAt('b', dateOf(1030));

      final frame = place([(event: a, lane: 0), (event: b, lane: 2)]);

      expect(frame.boxes, hasLength(2));
      final first = frame.boxes.first.rect;
      final second = frame.boxes.last.rect;
      expect(first.left, closeTo((a.reachFrom - from) * pxPerYear, 1e-9));
      expect(second.left - first.left, closeTo(200, 1e-9));
      expect(first.top, top);
      expect(second.top, top + 2 * kTimelineLaneHeight);
      expect(first.height, kTimelineLaneHeight);
    });

    test('la caja nunca es más chica que el mínimo, ni que su rótulo', () {
      final event = eventAt('a', dateOf(1010));

      expect(
        place([(event: event, lane: 0)]).boxes.single.rect.width,
        kTimelineMinBoxWidth,
      );
      // Un rótulo que necesita 15 años a 10 px por año: 150 px.
      expect(
        place([
          (event: event, lane: 0),
        ], labelYears: 15).boxes.single.rect.width,
        150,
      );
    });

    test('un tramo largo ocupa lo que dura', () {
      final century = eventAt(
        'siglo',
        dateOf(1100, precision: DatePrecision.century),
      );

      final box = place([(event: century, lane: 0)]).boxes.single;

      expect(box.rect.width, closeTo((century.to - century.from) * 10, 1e-6));
      expect(box.corePx, closeTo((century.to - century.from) * 10, 1e-6));
    });

    test('lo aproximado lleva borde difuso; lo exacto, no', () {
      final exact = eventAt('a', dateOf(1010));
      final circa = eventAt('b', dateOf(1030, circa: true));

      final frame = place([(event: exact, lane: 0), (event: circa, lane: 1)]);

      expect(frame.boxes.first.fuzzPx, 0);
      expect(frame.boxes.last.fuzzPx, closeTo(circa.fuzz * pxPerYear, 1e-9));
      expect(frame.boxes.last.fuzzPx, greaterThan(0));
    });

    test('un evento que empieza antes de la pantalla deja el rótulo a la '
        'vista', () {
      // Un siglo que arranca 60 años antes del borde izquierdo.
      final century = eventAt(
        'siglo',
        dateOf(1000, precision: DatePrecision.century),
      );

      final box = place([
        (event: century, lane: 0),
      ], viewFrom: 1040).boxes.single;

      expect(box.rect.left, lessThan(0));
      expect(box.labelOffset, greaterThan(0));
      // El rótulo no se corre más de lo que la caja deja.
      expect(box.labelOffset, lessThanOrEqualTo(box.rect.width - 28));
      // Y uno que empieza adentro no se corre.
      final inside = eventAt('b', dateOf(1050));
      expect(place([(event: inside, lane: 0)]).boxes.single.labelOffset, 0);
    });

    test('sin eventos no hay nada que tocar', () {
      final frame = place(const []);

      expect(frame.boxes, isEmpty);
      expect(frame.hitTest(const Offset(10, 10)), isNull);
    });
  });

  group('qué se toca', () {
    test('el evento bajo el dedo, y ninguno donde no hay', () {
      final a = eventAt('a', dateOf(1010));
      final b = eventAt('b', dateOf(1030));
      final frame = place([(event: a, lane: 0), (event: b, lane: 1)]);

      expect(frame.hitTest(frame.boxes.first.rect.center)?.event.itemId, 'a');
      expect(frame.hitTest(frame.boxes.last.rect.center)?.event.itemId, 'b');
      // Debajo del último carril y a la derecha de todo.
      expect(frame.hitTest(const Offset(900, 400)), isNull);
    });

    test('si dos cajas se solapan, gana la que se dibuja encima', () {
      final a = eventAt('a', dateOf(1010));
      final b = eventAt('b', dateOf(1010));
      final frame = place([(event: a, lane: 0), (event: b, lane: 0)]);

      final at = frame.boxes.first.rect.center;

      expect(frame.hitTest(at)?.event.itemId, 'b');
    });

    test('los bordes de la caja cuentan como adentro; un píxel más, no', () {
      final frame = place([(event: eventAt('a', dateOf(1010)), lane: 0)]);
      final rect = frame.boxes.single.rect;

      expect(frame.hitTest(rect.topLeft + const Offset(1, 1)), isNotNull);
      expect(frame.hitTest(rect.bottomRight - const Offset(1, 1)), isNotNull);
      expect(frame.hitTest(rect.bottomRight + const Offset(2, 2)), isNull);
    });
  });

  group('los rótulos ya medidos', () {
    const style = TextStyle(fontSize: 11);
    late TimelineLabelCache cache;

    setUp(() => cache = TimelineLabelCache());
    tearDown(() => cache.clear());

    test('el mismo título con el mismo ancho se mide una sola vez', () {
      final first = cache.labelFor('Caída de Roma', 120, style);
      final again = cache.labelFor('Caída de Roma', 120, style);

      expect(identical(first, again), isTrue);
      expect(cache.length, 1);
    });

    test('otro ancho o otro título se miden aparte', () {
      final base = cache.labelFor('Caída de Roma', 120, style);

      expect(
        identical(cache.labelFor('Caída de Roma', 200, style), base),
        isFalse,
      );
      expect(identical(cache.labelFor('Otro', 120, style), base), isFalse);
      expect(cache.length, 3);
    });

    test('un ancho que solo difiere en una fracción de píxel es el mismo', () {
      final base = cache.labelFor('Caída de Roma', 120.2, style);

      expect(
        identical(cache.labelFor('Caída de Roma', 119.8, style), base),
        isTrue,
      );
    });

    test('un rótulo que no cabe se acorta con puntos suspensivos', () {
      final label = cache.labelFor(
        'Un título larguísimo que no entra',
        40,
        style,
      );

      expect(label.width, lessThanOrEqualTo(40));
      expect(label.didExceedMaxLines, isTrue);
    });

    test('cambiar el estilo empieza de cero', () {
      cache
        ..labelFor('A', 50, style)
        ..labelFor('B', 50, style)
        ..labelFor('A', 50, style.copyWith(fontSize: 14));

      expect(cache.length, 1);
    });

    test('no crece sin límite: pasado el tope, empieza de cero', () {
      for (var i = 0; i < 1300; i++) {
        cache.labelFor('Título $i', 80, style);
      }

      expect(cache.length, lessThan(1300));
      expect(cache.length, greaterThan(0));
    });

    test('un ancho negativo no rompe', () {
      expect(() => cache.labelFor('A', -5, style), returnsNormally);
    });
  });

  group('el pintor', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    const style = TextStyle(fontSize: 11);

    TimelineEventsPainter painter(
      TimelineFrame frame,
      TimelineLabelCache labels, {
      ColorScheme? colors,
      void Function(String)? onOpen,
    }) => TimelineEventsPainter(
      frame: frame,
      scheme: colors ?? scheme,
      labelStyle: style,
      labels: labels,
      onOpen: onOpen ?? (_) {},
    );

    test('solo se repinta si cambió el cuadro o los colores', () {
      final labels = TimelineLabelCache();
      addTearDown(labels.clear);
      final frame = place([(event: eventAt('a', dateOf(1010)), lane: 0)]);
      final original = painter(frame, labels);

      expect(painter(frame, labels).shouldRepaint(original), isFalse);
      expect(
        painter(
          place([(event: eventAt('a', dateOf(1010)), lane: 0)]),
          labels,
        ).shouldRepaint(original),
        isTrue,
      );
      expect(
        painter(
          frame,
          labels,
          colors: ColorScheme.fromSeed(seedColor: Colors.red),
        ).shouldRepaint(original),
        isTrue,
      );
    });

    test('la semántica trae un nodo por evento, con su título y su fecha', () {
      final labels = TimelineLabelCache();
      addTearDown(labels.clear);
      final opened = <String>[];
      final frame = place([
        (
          event: eventAt('cesar', dateOf(44, bce: true), title: 'César'),
          lane: 0,
        ),
        (event: eventAt('roma', dateOf(476), title: 'Caída de Roma'), lane: 1),
      ]);

      final nodes = painter(
        frame,
        labels,
        onOpen: opened.add,
      ).semanticsBuilder(const Size(900, 500));

      expect(nodes, hasLength(2));
      expect(nodes.first.properties.label, 'César, 44 a.C.');
      expect(nodes.last.properties.label, 'Caída de Roma, 476');
      expect(nodes.every((n) => n.properties.button ?? false), isTrue);
      expect(nodes.first.rect, frame.boxes.first.rect);

      nodes.last.properties.onTap!();
      expect(opened, ['roma']);
    });

    test('la semántica se rearma solo con un cuadro nuevo', () {
      final labels = TimelineLabelCache();
      addTearDown(labels.clear);
      final frame = place([(event: eventAt('a', dateOf(1010)), lane: 0)]);
      final original = painter(frame, labels);

      expect(painter(frame, labels).shouldRebuildSemantics(original), isFalse);
      expect(
        painter(place(const []), labels).shouldRebuildSemantics(original),
        isTrue,
      );
    });
  });
}
