import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import 'fake_file_chooser.dart';
import 'fake_id_generator.dart';
import 'in_memory_file_store.dart';
import 'vault_test_doubles.dart';

/// Lo que necesita cualquier prueba de las pantallas de la biblioteca.
///
/// Monta una base **real en memoria**, no un repositorio simulado. Estas
/// pantallas viven de un stream que se actualiza cuando la base cambia, y con
/// un doble habría que simular a mano cuándo emite qué — o sea, probar la
/// simulación en vez de la pantalla. Con la base de verdad, guardar algo y
/// ver aparecer la fila es exactamente lo que hará el usuario.
class LibraryHarness {
  LibraryHarness._(
    this.container,
    this.database,
    this.ids,
    this.fileChooser,
    this.files,
  );

  /// Prepara todo y programa la limpieza. Llamar desde `setUp`.
  static Future<LibraryHarness> create({
    DateTime? now,
    String locale = 'es',

    /// Lo que devuelve el selector de archivos. `null` —el valor por
    /// defecto— simula que el usuario lo abre y cancela.
    CapturedFile? chosenFile,

    /// Si está, el selector lanza esto en vez de devolver.
    Object? fileChooserError,
  }) async {
    // El router lee `EnvConfig.current` al construirse; mismo contrato que
    // cumplen los entry points de flavor.
    EnvConfig.initialize(AppFlavor.dev);
    SharedPreferences.setMockInitialValues({'app_locale': locale});
    final prefs = await SharedPreferences.getInstance();

    final database = AppDatabase(NativeDatabase.memory());
    final ids = FakeIdGenerator();
    final chooser = FakeFileChooser(file: chosenFile, error: fileChooserError);
    final files = InMemoryFileStore();
    final fixedNow = now ?? DateTime(2026, 9, 11, 10);

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(prefs),
        idGeneratorProvider.overrideWithValue(ids),
        // El selector del sistema necesita una ventana: es lo único de este
        // camino que no se puede probar.
        fileChooserProvider.overrideWithValue(chooser),
        // El almacén real escribe en la carpeta de documentos de la app, y
        // esa ruta la resuelve un canal de plataforma que en un test no
        // existe: la llamada nunca contesta y la prueba se cuelga. Además,
        // una prueba de pantalla no tiene por qué dejar archivos en el disco
        // de quien la corre.
        fileStoreProvider.overrideWithValue(files),
        clockProvider.overrideWithValue(() => fixedNow),
        // La bóveda, para las pruebas que montan el router real: su guard
        // decide qué pantalla se ve.
        vaultLocalDataSourceProvider.overrideWithValue(
          FakeVaultLocalDataSource.withPin('246810'),
        ),
        pinHasherProvider.overrideWithValue(FakePinHasher()),
        // La cola no procesa en los tests que no la están probando. Sin
        // esto, abrir la biblioteca dispararía descargas reales y el estado
        // de cada elemento cambiaría bajo los pies de las aserciones.
        processingQueueProvider.overrideWith(
          (ref) => InertProcessingQueue(
            processItem: ref.watch(processItemUseCaseProvider),
            repository: ref.watch(libraryRepositoryProvider),
            logger: ref.watch(appLoggerProvider),
          ),
        ),
      ],
    );

    addTearDown(() {
      container.dispose();
      return database.close();
    });

    return LibraryHarness._(container, database, ids, chooser, files);
  }

  final ProviderContainer container;
  final AppDatabase database;
  final FakeIdGenerator ids;

  /// El selector de archivos de mentira, para comprobar que se abrió.
  final FakeFileChooser fileChooser;

  /// El almacén en memoria, para comprobar qué archivo quedó guardado.
  final InMemoryFileStore files;

  /// La cola inerte, para comprobar qué se le pidió procesar.
  ///
  /// Las pantallas no procesan nada por su cuenta: le piden a la cola. Que le
  /// pidan lo correcto es justamente lo que se rompe en silencio cuando
  /// alguien mueve un proveedor de sitio.
  InertProcessingQueue get queue =>
      container.read(processingQueueProvider.notifier) as InertProcessingQueue;

  /// Guarda algo pasando por el mismo camino que usa la app.
  ///
  /// No inserta filas a mano: si el test construyera los datos por su cuenta,
  /// podría armar combinaciones que la app nunca produce y dejar sin probar
  /// las que sí.
  Future<void> capture(String rawInput, {String? title, String? note}) async {
    final result = await container.read(captureItemUseCaseProvider)(
      CaptureRequest.text(rawInput: rawInput, title: title, note: note),
    );

    result.match(
      (failure) => throw StateError('la captura de prueba falló: $failure'),
      (_) {},
    );
  }

  /// Envuelve una pantalla con lo mínimo para que viva en un test.
  Widget wrap(Widget child, {Locale locale = const Locale('es')}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  /// Lleva el router a una ruta concreta, ya montado.
  ///
  /// Hace falta para probar pantallas que navegan —la de captura vuelve
  /// atrás al guardar— porque `context.pop()` necesita un router de verdad
  /// arriba. Montarlas sueltas en un MaterialApp funciona hasta que se toca
  /// el botón que cierra la pantalla, y ahí revienta con "No GoRouter found
  /// in context".
  /// Apila, no reemplaza: es lo que hace el botón de la app, y lo que deja
  /// una pila de la que la pantalla pueda volver.
  void pushTo(String location) {
    unawaited(container.read(goRouterProvider).push<void>(location));
  }

  /// Navega reemplazando, sin dejar pila.
  ///
  /// Simula llegar por un enlace directo —escribiendo la dirección en el
  /// navegador— que es el caso en el que una pantalla no tiene a dónde
  /// volver.
  void goTo(String location) {
    container.read(goRouterProvider).go(location);
  }

  /// Monta la app con su router de verdad, con la bóveda ya abierta.
  ///
  /// Para las pruebas de navegación: tocar una fila y llegar al detalle, o
  /// el botón de guardar y llegar a la captura. Con un router de mentira se
  /// estaría probando el router de mentira.
  Widget wrapWithAppRouter({Locale locale = const Locale('es')}) {
    container.read(vaultSessionControllerProvider.notifier).markUnlocked();

    return UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: ref.watch(goRouterProvider),
        ),
      ),
    );
  }
}
