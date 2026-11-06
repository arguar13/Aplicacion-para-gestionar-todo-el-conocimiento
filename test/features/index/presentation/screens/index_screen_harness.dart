import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/index/presentation/export/index_pdf_exporter.dart';
import 'package:sinapsis/features/index/presentation/index_download.dart';
import 'package:sinapsis/features/index/presentation/providers/index_providers.dart';
import 'package:sinapsis/features/index/presentation/screens/index_screen.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_leader_line.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_panels.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../support/fake_file_saver.dart';
import '../../../../support/fake_index_repository.dart';

/// El momento de las pruebas del Índice: «Nuevo» se mide contra esto.
final kIndexTestNow = DateTime(2026, 11, 5, 10);

/// La pantalla del Índice (F46, paso 3) sobre [repository], con un router
/// mínimo: el Índice, el lector único —que solo dice qué abrió—, Procesado y
/// la Biblioteca.
///
/// El panel de la derecha de una pantalla ancha dice qué tiene abierto y
/// ofrece cerrarlo: el lector entero lo prueba `index_screen_vault_test`.
class IndexScreenHarness {
  IndexScreenHarness(this.repository);

  final FakeIndexRepository repository;

  /// Lo que se sabe de cada documento para el toque largo (F46, paso 4).
  final documents = FakeIndexDocumentAccess();

  /// Lo que se guardó con «Descargar el índice»; se cambia antes de
  /// [pump] para probar un selector que se cancela.
  FakeFileSaver saver = FakeFileSaver();
  late GoRouter router;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(420, 900),
    double textScale = 1,
    ThemeData? theme,
    Map<String, Object> prefs = const {},
    List<Override> overrides = const [],
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();

    router = GoRouter(
      initialLocation: RoutePaths.index,
      routes: [
        GoRoute(
          path: RoutePaths.index,
          builder: (context, state) => const IndexScreen(),
        ),
        GoRoute(
          path: RoutePaths.extractReadingPattern,
          builder: (context, state) =>
              Scaffold(appBar: AppBar(), body: Text('lector ${state.uri}')),
        ),
        GoRoute(
          path: RoutePaths.processed,
          builder: (context, state) => const Scaffold(body: Text('Procesado')),
          routes: [
            GoRoute(
              path: ':id/original',
              builder: (context, state) => Scaffold(
                appBar: AppBar(),
                body: Text('original ${state.uri}'),
              ),
            ),
          ],
        ),
        // La Biblioteca: la ficha de una fuente y su original, que abre «Abrir
        // en el original» sin copia en Procesado (F46, paso 5c).
        GoRoute(
          path: RoutePaths.library,
          builder: (context, state) => const Scaffold(body: Text('Biblioteca')),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  Scaffold(appBar: AppBar(), body: Text('ficha ${state.uri}')),
              routes: [
                GoRoute(
                  path: 'original',
                  builder: (context, state) => Scaffold(
                    appBar: AppBar(),
                    body: Text('biblioteca ${state.uri}'),
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: RoutePaths.chat,
          builder: (context, state) => const Scaffold(body: Text('chat')),
        ),
      ],
    );
    addTearDown(router.dispose);
    container = ProviderContainer(
      overrides: [
        indexRepositoryProvider.overrideWithValue(repository),
        indexDocumentAccessProvider.overrideWithValue(documents),
        fileSaverProvider.overrideWithValue(saver),
        // El PDF del índice, en el mismo hilo —con el reloj de mentira no hay
        // otro— y con las letras de la app leídas del disco.
        indexPdfExporterProvider.overrideWithValue(
          IndexPdfExporter(
            fonts: (asset) async =>
                ByteData.sublistView(File(asset).readAsBytesSync()),
            worker: (build, job) => build(job),
          ),
        ),
        sharedPreferencesProvider.overrideWithValue(preferences),
        clockProvider.overrideWithValue(() => kIndexTestNow),
        indexReaderBuilderProvider.overrideWithValue(
          (opening, onClose) => Column(
            key: const Key('test-beside'),
            children: [
              Text('al lado ${opening.documentId} ${opening.entry?.key}'),
              TextButton(onPressed: onClose, child: const Text('cerrar')),
            ],
          ),
        ),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: theme,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  /// Escribe [text] en el buscador y espera la pausa de quien escribe.
  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('index-search')), text);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }
}

/// El renglón de la entrada que se titula [title].
Finder indexEntry(String title) => find.byWidgetPredicate(
  (widget) => widget is IndexLeaderLine && widget.plainTitle == title,
  description: 'la entrada «$title»',
);

/// Los títulos de las entradas que se ven, de arriba abajo.
List<String> shownEntries(WidgetTester tester) {
  final lines = find.byType(IndexLeaderLine).evaluate().toList()
    ..sort(
      (a, b) => tester
          .getTopLeft(find.byWidget(a.widget))
          .dy
          .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
    );
  return [for (final e in lines) (e.widget as IndexLeaderLine).plainTitle];
}
