import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/navigation/nav_destinations.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';

import '../../support/fake_shared_content_listener.dart';
import '../../support/vault_test_doubles.dart';

/// Que `ShellBranch` diga la verdad: el índice de cada rama es su lugar en el
/// `StatefulShellRoute`. Si alguien suma, saca o mueve una rama en el router
/// sin tocar el enum, la barra abriría otra pantalla que la que dice.
void main() {
  late ProviderContainer container;

  setUp(() async {
    EnvConfig.initialize(AppFlavor.dev);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        vaultLocalDataSourceProvider.overrideWithValue(
          FakeVaultLocalDataSource.withPin('246810'),
        ),
        deviceBootProvider.overrideWithValue(testDeviceBoot),
        pinHasherProvider.overrideWithValue(FakePinHasher()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sharedContentListenerProvider.overrideWithValue(
          FakeSharedContentListener(),
        ),
        appDatabaseProvider.overrideWith((ref) {
          final db = AppDatabase(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
      ],
    );
    addTearDown(container.dispose);
  });

  List<GoRoute> topLevel() => [
    for (final route in container.read(goRouterProvider).configuration.routes)
      if (route is GoRoute) route,
  ];

  StatefulShellRoute shell() => container
      .read(goRouterProvider)
      .configuration
      .routes
      .whereType<StatefulShellRoute>()
      .single;

  test('cada rama del router está en el lugar que dice ShellBranch', () {
    final paths = [
      for (final branch in shell().branches)
        (branch.routes.first as GoRoute).path,
    ];

    expect(paths, [
      for (final branch in ShellBranch.values)
        switch (branch) {
          ShellBranch.library => RoutePaths.library,
          ShellBranch.inbox => RoutePaths.inbox,
          ShellBranch.graph => RoutePaths.graph,
          ShellBranch.chat => RoutePaths.chat,
          ShellBranch.review => RoutePaths.review,
          ShellBranch.settings => RoutePaths.settings,
          ShellBranch.atlas => RoutePaths.atlas,
          ShellBranch.notebooks => RoutePaths.notebooks,
          ShellBranch.timeline => RoutePaths.timeline,
          ShellBranch.processed => RoutePaths.processed,
        },
    ]);
  });

  test('la línea de tiempo (F40) es una rama de la barra y no una ruta plana '
      'que se abre encima', () {
    final branchPaths = [
      for (final branch in shell().branches)
        for (final route in branch.routes)
          if (route is GoRoute) route.path,
    ];

    expect(branchPaths, contains(RoutePaths.timeline));
    expect(topLevel().where((r) => r.path == RoutePaths.timeline), isEmpty);
  });

  test('«Procesado» (F41) es una rama de la barra, y su documento se abre '
      'encima, en la raíz, como el detalle de un elemento', () {
    final branch = shell().branches[ShellBranch.processed.index];
    final list = branch.routes.single as GoRoute;
    final document = list.routes.single as GoRoute;

    expect(list.path, RoutePaths.processed);
    expect(
      '${list.path}/${document.path}',
      RoutePaths.processedDocumentPattern,
    );
    // En la raíz: se abre desde pantallas que están encima del shell.
    expect(document.parentNavigatorKey, isNotNull);
    expect(topLevel().where((r) => r.path == RoutePaths.processed), isEmpty);
  });

  test('el material de un tema (el Explorador de antes) ya no es una rama de '
      'la barra, sino una pantalla que se abre encima (F36)', () {
    final branchPaths = [
      for (final branch in shell().branches)
        for (final route in branch.routes)
          if (route is GoRoute) route.path,
    ];

    expect(branchPaths, isNot(contains(RoutePaths.explorer)));
    expect(
      topLevel().where((r) => r.path == RoutePaths.explorer),
      hasLength(1),
    );
  });
}
