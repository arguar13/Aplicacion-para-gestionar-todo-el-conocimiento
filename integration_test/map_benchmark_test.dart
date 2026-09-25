import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_repository_impl.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/screens/map_screen.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_schema_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../test/benchmark/map_benchmark.dart';
import '../test/benchmark/structured_map_repository.dart';
import '../test/benchmark/structured_topics.dart';
import '../test/benchmark/synthetic_vault.dart';
import '../test/benchmark/vault_benchmark.dart';
import '../test/support/fake_id_generator.dart';
import '../test/support/in_memory_file_store.dart';
import 'support/device_benchmark_directory.dart';

const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

/// Los cuadros de un gesto sostenido en una línea, sin las listas cuadro por
/// cuadro: esas quedan enteras en el JSON de su clave.
String _framesSummary(String what, Map<dynamic, dynamic>? frames) {
  if (frames == null) return '- $what: sin cifras de cuadros';
  String ms(String key) =>
      ((frames[key] as num?) ?? double.nan).toStringAsFixed(1);
  final built = frames['frame_count'] as num? ?? 0;
  final missedBuild = frames['missed_frame_build_budget_count'] as num? ?? 0;
  final missedRaster =
      frames['missed_frame_rasterizer_budget_count'] as num? ?? 0;
  String share(num missed) =>
      built == 0 ? 'n/d' : '${(missed * 100 / built).toStringAsFixed(1)} %';
  return '- $what, $built cuadros. Armado: promedio '
      '${ms('average_frame_build_time_millis')} ms, '
      'p90 ${ms('90th_percentile_frame_build_time_millis')}, '
      'p99 ${ms('99th_percentile_frame_build_time_millis')}, '
      'peor ${ms('worst_frame_build_time_millis')}. '
      'Raster: promedio ${ms('average_frame_rasterizer_time_millis')} ms, '
      'p90 ${ms('90th_percentile_frame_rasterizer_time_millis')}, '
      'p99 ${ms('99th_percentile_frame_rasterizer_time_millis')}, '
      'peor ${ms('worst_frame_rasterizer_time_millis')}. '
      'Cuadros fuera del presupuesto: $missedBuild de armado '
      '(${share(missedBuild)}) y $missedRaster de raster '
      '(${share(missedRaster)}). '
      'Recolecciones de memoria: ${frames['new_gen_gc_count']} de la '
      'generación nueva y ${frames['old_gen_gc_count']} de la vieja.';
}

/// El presupuesto de un cuadro (F14, D5): 16,6 ms, con menos del 5 % de los
/// cuadros por fuera.
const _kFrameBudgetMs = 16.6;
const _kMaxMissedShare = 0.05;

/// Compara [frames] contra el criterio de cierre de F14 —p90 de armado y de
/// raster bajo el presupuesto de un cuadro, menos del 5 % de cuadros fuera de
/// él— y agrega a [violations] una línea si no lo cumple (F18, 18.1, decisión
/// C). No interrumpe el benchmark: cada escenario se mide igual y el test
/// falla recién al final, con todas las violaciones juntas —así un informe
/// leído a mano deja de ser necesario para saber si el criterio se cumple,
/// pero se sigue midiendo todo aunque el primero ya haya fallado—.
void _checkFrameBudget(
  String what,
  Map<dynamic, dynamic>? frames,
  List<String> violations,
) {
  if (frames == null) {
    violations.add('$what: sin cifras de cuadros');
    return;
  }
  double ms(String key) => (frames[key] as num?)?.toDouble() ?? double.nan;
  final built = (frames['frame_count'] as num?) ?? 0;
  double share(String key) =>
      built == 0 ? 0 : ((frames[key] as num?) ?? 0) / built;

  final p90Build = ms('90th_percentile_frame_build_time_millis');
  final p90Raster = ms('90th_percentile_frame_rasterizer_time_millis');
  final missedBuildShare = share('missed_frame_build_budget_count');
  final missedRasterShare = share('missed_frame_rasterizer_budget_count');

  final missedBuildText =
      '${(missedBuildShare * 100).toStringAsFixed(1)} % de cuadros de '
      'armado fuera de presupuesto';
  final missedRasterText =
      '${(missedRasterShare * 100).toStringAsFixed(1)} % de cuadros de '
      'raster fuera de presupuesto';
  final problems = [
    if (p90Build > _kFrameBudgetMs)
      'p90 de armado ${p90Build.toStringAsFixed(1)} ms',
    if (p90Raster > _kFrameBudgetMs)
      'p90 de raster ${p90Raster.toStringAsFixed(1)} ms',
    if (missedBuildShare > _kMaxMissedShare) missedBuildText,
    if (missedRasterShare > _kMaxMissedShare) missedRasterText,
  ];
  if (problems.isNotEmpty) {
    violations.add('$what: ${problems.join(', ')}');
  }
}

/// El mapa de conocimiento con 10.000 elementos y 2.000 temas, EN el
/// dispositivo: los escenarios de cálculo y lectura, y —lo que solo un
/// dispositivo dice— la pantalla real: cuánto tarda en abrirse cada vista y
/// cuántos cuadros se pierden con un gesto sostenido, con y sin un recálculo
/// del mapa corriendo de fondo.
///
/// Es el criterio de cierre de F14 —«interacción fluida con 2.000 temas»—: el
/// percentil 90 de armado y de raster bajo el presupuesto de un cuadro y menos
/// del 5 % de cuadros fuera de él.
///
/// Se corre en modo profile con
/// `tool/bench_android.ps1 -Target map_benchmark_test -PushVaults`.
///
/// Los temas de la pantalla son los ESTRUCTURADOS (ver
/// `structured_topics.dart`): con los de la base, asignados al azar, el mapa
/// entero es una sola comunidad y el panorama, un solo nodo, que no mide nada.
/// Lo demás —el tablero, el esquema, los elementos de un tema— sale de la
/// base.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final reports = <String, dynamic>{};

  void save(String name, String content) {
    reports[name] = content;
    binding.reportData = <String, dynamic>{...?binding.reportData, ...reports};
  }

  BenchmarkEnvironment environment() => BenchmarkEnvironment(
    open: () async =>
        openBenchmarkVault(directory: await deviceBenchmarkDirectory()),
    log: debugPrint,
    save: save,
    description: _deviceInfo,
  );

  group(
    'benchmark del mapa de conocimiento, en el dispositivo',
    () => registerMapBenchmark(environment()),
  );

  testWidgets(
    'pantallas: abrir cada vista y recorrer el grafo con gestos sostenidos',
    (tester) async {
      final es = AppLocalizationsEs();
      final report = StringBuffer('# El mapa en pantalla\n\n')
        ..writeln('Equipo: $_deviceInfo')
        ..writeln();
      // F18, 18.1, decisión C: cada escenario se compara contra el
      // presupuesto de un cuadro aunque uno anterior ya haya fallado —se
      // sigue midiendo todo—, y el test falla al final con todas las
      // violaciones juntas.
      final violations = <String>[];
      void say(String line) {
        debugPrint(line);
        report.writeln(line);
      }

      int rssMb() => ProcessInfo.currentRss ~/ (1024 * 1024);

      final opened = await tester.runAsync(
        () async =>
            openBenchmarkVault(directory: await deviceBenchmarkDirectory()),
      );
      final db = opened!.db;
      final vault = opened.vault;
      addTearDown(db.close);

      final telemetry = MockTelemetryService();
      final real = KnowledgeMapRepositoryImpl(
        database: db,
        library: LibraryRepositoryImpl(
          database: db,
          telemetry: telemetry,
          files: InMemoryFileStore(),
          ids: FakeIdGenerator(prefix: 'bench'),
          clock: () => vault.now,
        ),
      );
      final realInput = (await tester.runAsync(
        () => real.readTopicInput(vault.temaDefinitionId),
      ))!;
      final input = structuredTopicInput(
        realInput,
        items: vault.profile.items,
        relations: vault.profile.relations,
      );
      // Los temas que tienen elementos en la base, con sus ancestros: los
      // elementos de un tema salen de la base, y abrir uno sin ninguno no
      // dibuja nada.
      final withItems = <String>{};
      final parentOf = {for (final v in realInput.values) v.id: v.parentId};
      for (final item in realInput.items) {
        for (final id in item.valueIds) {
          String? current = id;
          while (current != null && withItems.add(current)) {
            current = parentOf[current];
          }
        }
      }
      final structured = StructuredMapRepository(real, input);
      addTearDown(structured.dispose);
      say(
        '- temas de la pantalla: ${input.values.length} temas, '
        '${input.items.length} elementos, ${input.relations.length} vínculos',
      );

      final rssStart = rssMb();

      /// Espera, sin pasar de un minuto, a que [finder] encuentre algo.
      Future<void> until(Finder finder) async {
        final watch = Stopwatch()..start();
        while (finder.evaluate().isEmpty) {
          await tester.pump(const Duration(milliseconds: 20));
          expect(
            watch.elapsed,
            lessThan(const Duration(minutes: 1)),
            reason: 'no apareció $finder',
          );
        }
      }

      Finder graphNode(String prefix) => find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('map-graph-node-$prefix');
      });

      /// Lo que tarda [action] hasta que aparece [finder] y la pantalla se
      /// aquieta, en milisegundos.
      Future<int> timeTo(Finder finder, Future<void> Function() action) async {
        final watch = Stopwatch()..start();
        await action();
        await until(finder);
        await tester.pumpAndSettle();
        return watch.elapsedMilliseconds;
      }

      // 1. El tablero: lo primero que se ve al abrir la pantalla.
      final boardMs = await timeTo(
        find.byType(MapBoardView),
        () => tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              telemetryServiceProvider.overrideWithValue(telemetry),
              knowledgeMapRepositoryProvider.overrideWithValue(structured),
            ],
            child: const MaterialApp(
              locale: Locale('es'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MapScreen(),
            ),
          ),
        ),
      );
      say(
        '- abrir la pantalla, hasta ver el tablero (mapa + lecturas de la '
        'base): $boardMs ms',
      );

      // 2. El esquema.
      final schemaMs = await timeTo(
        find.byType(MapSchemaView),
        () => tester.tap(find.text(es.mapViewSchema)),
      );
      say('- pasar al esquema, hasta verlo dibujado: $schemaMs ms');

      // Un arrastre sostenido en el esquema.
      await binding.watchPerformance(() async {
        for (var pass = 0; pass < 4; pass++) {
          await tester.timedDrag(
            find.byType(InteractiveViewer).last,
            const Offset(-300, -200),
            const Duration(milliseconds: 1500),
          );
          await tester.timedDrag(
            find.byType(InteractiveViewer).last,
            const Offset(300, 200),
            const Duration(milliseconds: 1500),
          );
        }
      }, reportKey: 'map_schema_drag');
      final schemaDragFrames = binding.reportData?['map_schema_drag'] as Map?;
      say(
        _framesSummary(
          'arrastre sostenido en el esquema, ocho pasadas de 1,5 s',
          schemaDragFrames,
        ),
      );
      _checkFrameBudget(
        'esquema: arrastre sostenido',
        schemaDragFrames,
        violations,
      );

      // 3. El grafo: el panorama, con una comunidad por nodo.
      final graphMs = await timeTo(
        graphNode('overview:0'),
        () => tester.tap(find.text(es.mapViewGraph)),
      );
      final overviewNodes = graphNode('overview:').evaluate().length;
      say(
        '- pasar al grafo, hasta ver el panorama ($overviewNodes nodos): '
        '$graphMs ms',
      );

      final canvas = find.byKey(const ValueKey('map-graph-canvas'));

      /// El nodo con [prefix] más cerca del centro del lienzo: a la vista
      /// aunque un gesto anterior haya movido el mapa, y no tapado por los de
      /// un borde.
      Finder centerMost(String prefix, {bool Function(String id)? where}) {
        final target = tester.getCenter(canvas);
        Element? best;
        var bestDistance = double.infinity;
        for (final element in graphNode(prefix).evaluate()) {
          final key = element.widget.key! as ValueKey<String>;
          final id = key.value.substring(
            'map-graph-node-'.length + prefix.length,
          );
          if (where != null && !where(id)) continue;
          final box = element.renderObject! as RenderBox;
          final at = box.localToGlobal(box.size.center(Offset.zero));
          final distance = (at - target).distanceSquared;
          if (distance < bestDistance) {
            bestDistance = distance;
            best = element;
          }
        }
        return find.byElementPredicate((element) => element == best);
      }

      Future<void> drag({int passes = 6}) async {
        for (var pass = 0; pass < passes; pass++) {
          await tester.timedDrag(
            canvas,
            const Offset(-300, 0),
            const Duration(milliseconds: 1500),
          );
          await tester.timedDrag(
            canvas,
            const Offset(300, 0),
            const Duration(milliseconds: 1500),
          );
        }
      }

      /// Dos dedos que se abren (o se cierran) sin llegar a cambiar de nivel.
      Future<void> pinch({required bool open}) async {
        final center = tester.getCenter(canvas);
        const start = 50.0;
        const travel = 40.0;
        final sign = open ? 1.0 : -1.0;
        final first = await tester.startGesture(
          center - Offset(open ? start : start + travel, 0),
          pointer: 1,
        );
        final second = await tester.startGesture(
          center + Offset(open ? start : start + travel, 0),
          pointer: 2,
        );
        const steps = 30;
        for (var i = 0; i < steps; i++) {
          await first.moveBy(Offset(-sign * travel / steps, 0));
          await second.moveBy(Offset(sign * travel / steps, 0));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
      }

      await binding.watchPerformance(
        drag,
        reportKey: 'map_graph_overview_drag',
      );
      final overviewDragFrames =
          binding.reportData?['map_graph_overview_drag'] as Map?;
      say(
        _framesSummary(
          'arrastre sostenido en el panorama, doce pasadas de 1,5 s',
          overviewDragFrames,
        ),
      );
      _checkFrameBudget(
        'panorama: arrastre sostenido',
        overviewDragFrames,
        violations,
      );

      await binding.watchPerformance(() async {
        for (var i = 0; i < 4; i++) {
          await pinch(open: true);
          await pinch(open: false);
        }
      }, reportKey: 'map_graph_overview_zoom');
      final overviewZoomFrames =
          binding.reportData?['map_graph_overview_zoom'] as Map?;
      say(
        _framesSummary(
          'acercar y alejar con dos dedos en el panorama, ocho gestos',
          overviewZoomFrames,
        ),
      );
      _checkFrameBudget(
        'panorama: zoom con dos dedos',
        overviewZoomFrames,
        violations,
      );

      // 4. Los temas de la comunidad más grande.
      final topicsMs = await timeTo(
        graphNode('topic:'),
        () => tester.tap(graphNode('overview:0'), warnIfMissed: false),
      );
      final topicNodes = graphNode('topic:').evaluate().length;
      say(
        '- bajar a los temas de la comunidad mayor ($topicNodes nodos), '
        'hasta verlos: $topicsMs ms',
      );
      await binding.watchPerformance(
        () => drag(passes: 4),
        reportKey: 'map_graph_topics_drag',
      );
      final topicsDragFrames =
          binding.reportData?['map_graph_topics_drag'] as Map?;
      say(
        _framesSummary(
          'arrastre sostenido en el nivel de temas, ocho pasadas de 1,5 s',
          topicsDragFrames,
        ),
      );
      _checkFrameBudget(
        'temas (rama de primer nivel entera): arrastre sostenido',
        topicsDragFrames,
        violations,
      );

      // 5. Los elementos de un tema.
      final visibleTopics = graphNode('topic:').evaluate().length;
      final withRows = [
        for (final e in graphNode('topic:').evaluate())
          if (withItems.contains(
            (e.widget.key! as ValueKey<String>).value.substring(
              'map-graph-node-topic:'.length,
            ),
          ))
            e,
      ].length;
      say(
        '- temas a la vista: $visibleTopics; con elementos en la base: '
        '$withRows (de ${withItems.length} en toda la bóveda)',
      );
      final itemsMs = await timeTo(graphNode('item:'), () async {
        await tester.tap(
          centerMost('topic:', where: withItems.contains),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('map-graph-action-items')));
      });
      final itemNodes = graphNode('item:').evaluate().length;
      say(
        '- bajar a los elementos de un tema ($itemNodes nodos, lectura de la '
        'base incluida), hasta verlos: $itemsMs ms',
      );
      await binding.watchPerformance(
        () => drag(passes: 4),
        reportKey: 'map_graph_items_drag',
      );
      final itemsDragFrames =
          binding.reportData?['map_graph_items_drag'] as Map?;
      say(
        _framesSummary(
          'arrastre sostenido en el nivel de elementos, ocho pasadas de 1,5 s',
          itemsDragFrames,
        ),
      );
      _checkFrameBudget(
        'elementos: arrastre sostenido',
        itemsDragFrames,
        violations,
      );

      // 6. El criterio de F14: el mapa se recalcula de fondo —en otro
      // isolate— mientras se sigue arrastrando, y la interfaz no se detiene.
      await tester.tap(find.byKey(const ValueKey('map-graph-crumb-overview')));
      await until(graphNode('overview:0'));
      await tester.pumpAndSettle();
      var writes = 0;
      final writer = Timer.periodic(const Duration(seconds: 2), (_) {
        writes++;
        structured.write(
          TopicGraphInput(
            definitionId: input.definitionId,
            definitionName: input.definitionName,
            values: input.values,
            items: [
              ...input.items,
              for (var i = 0; i < writes; i++)
                TopicItem(id: 'nuevo-$i', valueIds: input.items[i].valueIds),
            ],
            relations: input.relations,
          ),
        );
      });
      await binding.watchPerformance(
        drag,
        reportKey: 'map_graph_drag_recompute',
      );
      writer.cancel();
      final recomputeDragFrames =
          binding.reportData?['map_graph_drag_recompute'] as Map?;
      say(
        _framesSummary(
          'arrastre sostenido en el panorama con el mapa recalculándose de '
          'fondo ($writes escrituras en 18 s)',
          recomputeDragFrames,
        ),
      );
      _checkFrameBudget(
        'panorama: arrastre con recálculo de fondo',
        recomputeDragFrames,
        violations,
      );

      // 7. F18, 18.1: la misma pregunta, pero agrupando los temas por
      // SUB-RAMA (profundidad 2 del árbol de Temas) en vez de por rama de
      // primer nivel entera —«Historia › Roma», no «Historia» completa—: el
      // caso que un usuario navega de verdad. `structured.write` reusa el
      // mismo mecanismo que el recálculo de fondo del paso 6, sin reabrir
      // la bóveda ni la pantalla.
      final narrowInput = structuredTopicInput(
        realInput,
        items: vault.profile.items,
        relations: vault.profile.relations,
        areaDepth: 2,
      );
      await tester.tap(find.byKey(const ValueKey('map-graph-crumb-overview')));
      await tester.pumpAndSettle();
      structured.write(narrowInput);
      // El recálculo corre en otro isolate: un pump acotado, no
      // `pumpAndSettle` (que podría cortar antes de que el resultado
      // vuelva), seguido de un settle una vez que ya tuvo tiempo de llegar.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final narrowTopicsMs = await timeTo(
        graphNode('topic:'),
        () => tester.tap(graphNode('overview:0'), warnIfMissed: false),
      );
      final narrowTopicNodes = graphNode('topic:').evaluate().length;
      say(
        '- F18, 18.1, agrupando por sub-rama (profundidad 2): la comunidad '
        'mayor tiene $narrowTopicNodes nodos, hasta verlos: $narrowTopicsMs '
        'ms',
      );
      await binding.watchPerformance(
        () => drag(passes: 4),
        reportKey: 'map_graph_topics_drag_narrow',
      );
      final narrowTopicsDragFrames =
          binding.reportData?['map_graph_topics_drag_narrow'] as Map?;
      say(
        _framesSummary(
          'arrastre sostenido en el nivel de temas con sub-rama, ocho '
          'pasadas de 1,5 s',
          narrowTopicsDragFrames,
        ),
      );
      _checkFrameBudget(
        'temas (sub-rama, profundidad 2): arrastre sostenido',
        narrowTopicsDragFrames,
        violations,
      );

      say(
        '- memoria residente: $rssStart MB al empezar, ${rssMb()} MB al '
        'terminar, ${ProcessInfo.maxRss ~/ (1024 * 1024)} MB máxima',
      );
      save('latest_map_screens_report.md', report.toString());

      // F18, 18.1, decisión C: el criterio de cierre de F14 queda verde o
      // rojo solo, sin depender de leer este informe a mano.
      expect(
        violations,
        isEmpty,
        reason:
            'No cumplen el presupuesto de un cuadro (16,6 ms de p90, menos '
            'del 5 % de cuadros fuera):\n${violations.join('\n')}',
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
