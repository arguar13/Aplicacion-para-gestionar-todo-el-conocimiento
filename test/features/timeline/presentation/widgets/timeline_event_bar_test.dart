import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';

import '../../timeline_fixtures.dart';

/// Cómo se dibuja un hecho según lo que se sabe de su fecha (F40): en
/// particular un tramo, de punta a punta con su inicio y su fin marcados.
void main() {
  TimelineEvent range({
    HistoricalDate? start,
    HistoricalDate? end,
    bool circa = false,
  }) => TimelineEvent(
    itemId: 'libro',
    title: 'La Gran Guerra',
    date: start ?? dateOf(1914, circa: circa),
    end: end ?? dateOf(1918),
    sourceKind: SourceKind.document,
    datedEventId: 'h',
  );

  group('qué estilo le toca a cada hecho', () {
    test('un tramo con fin propio es un tramo', () {
      expect(range().barStyle, TimelineBarStyle.range);
    });

    test('un tramo es un tramo aunque sus extremos sean décadas o siglos: se '
        'sabe de cuándo a cuándo', () {
      final event = range(
        start: dateOf(1900, precision: DatePrecision.decade),
        end: dateOf(1930, precision: DatePrecision.decade),
      );

      expect(event.isPeriod, isFalse);
      expect(event.barStyle, TimelineBarStyle.range);
    });

    test(
      'un tramo aproximado sigue siendo un tramo, con los bordes difusos',
      () {
        final event = range(circa: true);

        expect(event.barStyle, TimelineBarStyle.range);
        expect(event.fuzz, greaterThan(0));
      },
    );

    test('lo que no tiene fin se dibuja como siempre', () {
      expect(eventAt('a', dateOf(1914)).barStyle, TimelineBarStyle.exact);
      expect(
        eventAt('a', dateOf(1914, circa: true)).barStyle,
        TimelineBarStyle.approximate,
      );
      expect(
        eventAt('a', dateOf(1900, precision: DatePrecision.decade)).barStyle,
        TimelineBarStyle.period,
      );
      expect(
        eventAt(
          'a',
          dateOf(1900, precision: DatePrecision.century, circa: true),
        ).barStyle,
        TimelineBarStyle.approximatePeriod,
      );
    });
  });

  group('cómo se pinta un tramo', () {
    const red = Color(0xFFFF0000);

    /// Pinta [style] en una imagen de 120×30 con la barra en (10, 10)–(110, 20)
    /// y devuelve los bytes RGBA.
    Future<ByteData> paint(
      WidgetTester tester,
      TimelineBarStyle style, {
      double fuzzPx = 0,
    }) async {
      final data = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        paintTimelineBar(
          Canvas(recorder),
          const Rect.fromLTWH(10, 10, 100, kTimelineBarHeight),
          style: style,
          color: red,
          fuzzPx: fuzzPx,
          corePx: 100 - fuzzPx * 2,
          paint: Paint(),
        );
        final image = await recorder.endRecording().toImage(120, 30);
        return image.toByteData();
      });
      return data!;
    }

    int alphaAt(ByteData bytes, int x, int y) =>
        bytes.getUint8((y * 120 + x) * 4 + 3);

    testWidgets('el cuerpo es tenue y las dos puntas, firmes', (tester) async {
      final bytes = await paint(tester, TimelineBarStyle.range);

      // El cuerpo, con la mitad del color o menos.
      final body = alphaAt(bytes, 60, 15);
      expect(body, inInclusiveRange(90, 115));
      // La punta de adelante y la de atrás, enteras.
      expect(alphaAt(bytes, 11, 15), 255);
      expect(alphaAt(bytes, 108, 15), 255);
    });

    testWidgets('las puntas sobresalen de la barra, arriba y abajo', (
      tester,
    ) async {
      final bytes = await paint(tester, TimelineBarStyle.range);

      // Por encima y por debajo de la barra (y 10..20): la punta, no el cuerpo.
      for (final y in [8, 9, 20, 21]) {
        expect(
          alphaAt(bytes, 11, y),
          greaterThan(200),
          reason: 'punta de adelante y=$y',
        );
        expect(
          alphaAt(bytes, 108, y),
          greaterThan(200),
          reason: 'punta de atrás y=$y',
        );
        expect(alphaAt(bytes, 60, y), 0, reason: 'el cuerpo no sobresale y=$y');
      }
      // Pero no más de lo que sobresalen.
      expect(alphaAt(bytes, 11, 7), 0);
      expect(alphaAt(bytes, 11, 22), 0);
    });

    testWidgets('empiezan y terminan donde empieza y termina el tramo', (
      tester,
    ) async {
      final bytes = await paint(tester, TimelineBarStyle.range);

      // La barra va de x=10 a x=110: las puntas son los 3 px de cada extremo.
      expect(alphaAt(bytes, 9, 15), 0);
      expect(alphaAt(bytes, 10, 15), 255);
      expect(alphaAt(bytes, 12, 15), 255);
      expect(alphaAt(bytes, 13, 15), inInclusiveRange(90, 115));
      expect(alphaAt(bytes, 106, 15), inInclusiveRange(90, 115));
      expect(alphaAt(bytes, 107, 15), 255);
      expect(alphaAt(bytes, 109, 15), 255);
      expect(alphaAt(bytes, 110, 15), 0);
    });

    testWidgets('un hecho exacto es una barra llena y sin puntas', (
      tester,
    ) async {
      final bytes = await paint(tester, TimelineBarStyle.exact);

      expect(alphaAt(bytes, 60, 15), 255);
      expect(alphaAt(bytes, 11, 8), 0);
      expect(alphaAt(bytes, 11, 21), 0);
    });

    testWidgets('con un «circa», los bordes se desvanecen y las puntas quedan '
        'en el tramo mismo', (tester) async {
      final bytes = await paint(tester, TimelineBarStyle.range, fuzzPx: 12);

      // Dentro del borde difuso, a media altura: algo, pero no firme.
      expect(alphaAt(bytes, 10, 15), lessThan(40));
      // El tramo empieza donde termina el borde difuso.
      expect(alphaAt(bytes, 23, 15), 255);
      expect(alphaAt(bytes, 96, 15), 255);
    });
  });
}
