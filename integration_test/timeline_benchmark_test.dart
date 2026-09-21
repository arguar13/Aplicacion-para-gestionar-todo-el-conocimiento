import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/repositories/timeline_repository.dart';
import 'package:sinapsis/features/timeline/domain/services/lane_layout.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_index.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_canvas.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_events_painter.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../test/features/timeline/timeline_fixtures.dart';

const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

/// Un repositorio que entrega siempre los mismos eventos: lo que se mide es la
/// pantalla, no la lectura de la base —esa ya la mide el benchmark de la
/// bóveda—.
class _FixedTimelineRepository implements TimelineRepository {
  const _FixedTimelineRepository(this.events);

  final List<TimelineEvent> events;

  @override
  Stream<List<TimelineEvent>> watchEvents(LibraryQuery filter) =>
      Stream.value(events);
}

/// La línea de tiempo con diez mil hechos, EN el dispositivo: armar el árbol
/// de intervalos, recorrer mil ventanas y —lo que solo un teléfono dice— la
/// pantalla real con un arrastre sostenido, con lo que le cuesta a la memoria.
///
/// Es la presión de memoria y de dibujo lo que un escritorio predice peor: en
/// `test/features/timeline` ya está lo que decide —cuántos nodos mira el
/// índice por ventana, que no depende de la máquina—; esto mide el tiempo y
/// los cuadros. Se corre en modo profile con
/// `tool/bench_android.ps1 -Target timeline_benchmark_test`.
/// Los cuadros del arrastre sostenido en una línea, sin las listas cuadro por
/// cuadro: esas quedan enteras en `timeline_drag.json`.
String _dragSummary(Map<dynamic, dynamic> drag) {
  String ms(String key) =>
      ((drag[key] as num?) ?? double.nan).toStringAsFixed(1);
  return '- arrastre sostenido, doce pasadas de 1,5 s, ${drag['frame_count']} '
      'cuadros. Armado: promedio ${ms('average_frame_build_time_millis')} ms, '
      'p90 ${ms('90th_percentile_frame_build_time_millis')}, '
      'p99 ${ms('99th_percentile_frame_build_time_millis')}, '
      'peor ${ms('worst_frame_build_time_millis')}. '
      'Raster: promedio ${ms('average_frame_rasterizer_time_millis')} ms, '
      'p90 ${ms('90th_percentile_frame_rasterizer_time_millis')}, '
      'p99 ${ms('99th_percentile_frame_rasterizer_time_millis')}, '
      'peor ${ms('worst_frame_rasterizer_time_millis')}. '
      'Cuadros fuera del presupuesto: '
      '${drag['missed_frame_build_budget_count']} de armado y '
      '${drag['missed_frame_rasterizer_budget_count']} de raster. '
      'Recolecciones de memoria: ${drag['new_gen_gc_count']} de la generación '
      'nueva y ${drag['old_gen_gc_count']} de la vieja.';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('línea de tiempo: diez mil hechos, armado y arrastre sostenido', (
    tester,
  ) async {
    final report = StringBuffer('# Línea de tiempo a escala\n\n')
      ..writeln('Equipo: $_deviceInfo')
      ..writeln();
    void say(String line) {
      debugPrint(line);
      report.writeln(line);
    }

    int rssMb() => ProcessInfo.currentRss ~/ (1024 * 1024);

    final events = tenThousandTimelineEvents();
    final rssStart = rssMb();

    // 1. El árbol de intervalos, con lo que hace la pantalla al recibir los
    // eventos.
    final buildWatch = Stopwatch()..start();
    final index = TimelineIndex(events);
    say(
      '- armar el árbol de intervalos de ${index.length} eventos: '
      '${buildWatch.elapsedMilliseconds} ms',
    );

    // 2. Mil ventanas de un gesto de arrastre: la consulta y el reparto en
    // carriles, sin dibujar.
    final windowsWatch = Stopwatch()..start();
    var placed = 0;
    for (var frame = 0; frame < 1000; frame++) {
      final from = -3000 + frame * 5.0;
      placed += layoutLanes(
        index.window(from, from + 40).events,
        maxLanes: 12,
      ).placed.length;
    }
    say(
      '- mil ventanas de arrastre, consulta y carriles, sin dibujar: '
      '${windowsWatch.elapsedMilliseconds} ms ($placed eventos ubicados)',
    );

    // 3. La pantalla de verdad.
    final shownWatch = Stopwatch()..start();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timelineRepositoryProvider.overrideWithValue(
            _FixedTimelineRepository(events),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TimelineScreen(),
        ),
      ),
    );
    while (find.byType(TimelineCanvas).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(shownWatch.elapsed, lessThan(const Duration(minutes: 1)));
    }
    await tester.pumpAndSettle();
    say(
      '- abrir la pantalla con ${events.length} eventos, hasta verla: '
      '${shownWatch.elapsedMilliseconds} ms',
    );

    // Un acercamiento medio: el arrastre tiene que mover una ventana con
    // cientos de eventos, no la vista entera —donde casi no hay adónde ir— ni
    // una vacía.
    final zoomIn = find.byIcon(Icons.add);
    for (var i = 0; i < 6; i++) {
      await tester.tap(zoomIn);
      await tester.pumpAndSettle();
    }

    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('timeline-events')),
                )
                .painter!
            as TimelineEventsPainter;
    say('- barras en pantalla tras acercar: ${painter.frame.boxes.length}');

    // 4. El arrastre sostenido, con los cuadros que produce.
    await binding.watchPerformance(() async {
      for (var pass = 0; pass < 6; pass++) {
        await tester.timedDrag(
          find.byType(TimelineCanvas),
          const Offset(-500, 0),
          const Duration(milliseconds: 1500),
        );
        await tester.timedDrag(
          find.byType(TimelineCanvas),
          const Offset(500, 0),
          const Duration(milliseconds: 1500),
        );
      }
    }, reportKey: 'timeline_drag');

    final drag = binding.reportData?['timeline_drag'] as Map?;
    say(
      drag == null
          ? '- arrastre sostenido: sin cifras de cuadros'
          : _dragSummary(drag),
    );
    say(
      '- memoria residente: $rssStart MB al empezar, ${rssMb()} MB al '
      'terminar, ${ProcessInfo.maxRss ~/ (1024 * 1024)} MB máxima',
    );

    binding.reportData = {
      ...?binding.reportData,
      'latest_timeline_report.md': report.toString(),
    };
  }, timeout: const Timeout(Duration(minutes: 10)));
}
