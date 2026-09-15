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
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import 'fake_chat_model.dart';
import 'fake_chat_model_manager.dart';
import 'fake_directory_chooser.dart';
import 'fake_directory_writer.dart';
import 'fake_file_chooser.dart';
import 'fake_file_opener.dart';
import 'fake_file_saver.dart';
import 'fake_id_generator.dart';
import 'fake_relation_suggestion_service.dart';
import 'fake_shared_content_listener.dart';
import 'fake_summarization_service.dart';
import 'fake_text_to_speech_service.dart';
import 'fake_whisper_model_manager.dart';
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
    this.fileOpener,
    this.fileSaver,
    this.notebookLmDirectoryChooser,
    this.notebookLmDirectoryWriter,
    this.sharedContent,
    this.whisperModel,
    this.chatModel,
    this.chatModelManager,
    this.chatModelManagerGemma3n,
    this.chatModelManagerGemma412b,
    this.relationSuggestionService,
    this.summarizationService,
    this.textToSpeechService,
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

    /// La carpeta que "elige" quien prueba el paquete de NotebookLM. `null`
    /// —el valor por defecto, igual que con el archivo elegido más arriba—
    /// simula cancelar el selector.
    String? notebookLmDirectoryPath,

    /// Lo que "trajo" el arranque de la app, como si el sistema operativo
    /// hubiera entregado esto por el botón de compartir de otra app antes de
    /// que la pantalla de captura llegara a pedirlo.
    List<CaptureRequest> initialSharedContent = const [],

    /// Si el modelo de transcripción "ya está descargado" al arrancar.
    bool whisperModelReady = false,

    /// Si el modelo de chat "ya está descargado" al arrancar.
    bool chatModelReady = false,

    /// Lo que "contesta" el modelo de chat de mentira, tanto en el modo con
    /// la bóveda como en una conversación libre.
    String? chatModelResponse,

    /// Lo que "contesta" el resumidor de mentira.
    String? summarizeResponse,

    /// Si está, el resumidor lanza esto en vez de contestar.
    Object? summarizeError,

    /// Qué opción de modelo de chat está elegida al arrancar.
    ///
    /// Fija en [ChatModelOption.gemma4E4b] por defecto y no según la
    /// plataforma real —a diferencia de `defaultChatModelOption`—: qué
    /// modelo por defecto le toca a una prueba no puede depender de si
    /// quien la corre usa Windows, Linux o Android, o las mismas pruebas
    /// pasarían distinto según la máquina.
    ChatModelOption initialChatModelOption = ChatModelOption.gemma4E4b,
  }) async {
    // El router lee `EnvConfig.current` al construirse; mismo contrato que
    // cumplen los entry points de flavor.
    EnvConfig.initialize(AppFlavor.dev);
    SharedPreferences.setMockInitialValues({
      'app_locale': locale,
      'chat_model_option': initialChatModelOption.name,
    });
    final prefs = await SharedPreferences.getInstance();

    final database = AppDatabase(NativeDatabase.memory());
    final ids = FakeIdGenerator();
    final chooser = FakeFileChooser(file: chosenFile, error: fileChooserError);
    final files = InMemoryFileStore();
    final opener = FakeFileOpener();
    final saver = FakeFileSaver();
    final directoryChooser = FakeDirectoryChooser(
      path: notebookLmDirectoryPath,
    );
    final directoryWriter = FakeDirectoryWriter();
    final sharedContent = FakeSharedContentListener(
      initial: initialSharedContent,
    );
    final whisperModel = FakeWhisperModelManager(ready: whisperModelReady);
    final chatModel = FakeChatModel(response: chatModelResponse);
    final chatModelManager = FakeChatModelManager(ready: chatModelReady);
    final chatModelManagerGemma3n = FakeChatModelManager();
    final chatModelManagerGemma412b = FakeChatModelManager();
    final relationSuggestionService = FakeRelationSuggestionService();
    final summarizationService = FakeSummarizationService(
      response: summarizeResponse,
      error: summarizeError,
    );
    final textToSpeechService = FakeTextToSpeechService();
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
        // El complemento nativo que abre archivos con la app del sistema no
        // tiene con qué hablar en un test: no hay sistema operativo real que
        // responda al otro lado del canal.
        fileOpenerProvider.overrideWithValue(opener),
        // Mismo motivo: el diálogo de guardado y el selector de carpeta son
        // los dos ventanas del sistema, y escribir en una carpeta de verdad
        // no tiene sentido en una prueba de pantalla.
        fileSaverProvider.overrideWithValue(saver),
        directoryChooserProvider.overrideWithValue(directoryChooser),
        directoryWriterProvider.overrideWithValue(directoryWriter),
        // Sin un sistema operativo real, el plugin de compartir no tiene con
        // qué hablar; y sin esto, cada prueba que monta el router de verdad
        // construiría uno igual, con su propio canal roto.
        sharedContentListenerProvider.overrideWithValue(sharedContent),
        // El modelo de Whisper pesa cientos de megas y se baja de una URL de
        // verdad: nada de eso tiene sentido en una prueba de pantalla.
        whisperModelManagerProvider.overrideWithValue(whisperModel),
        // Mismo motivo que el modelo de Whisper: `flutter_gemma` no tiene
        // con qué hablar en un test, y ni el chat ni las flashcards lo
        // necesitan de verdad para probar la pantalla.
        chatModelProvider.overrideWithValue(chatModel),
        // Uno de mentira por opción, no un solo `overrideWithValue`: así
        // `ChatModelScreen` puede probarse consultando y "descargando" la
        // opción que corresponde según lo que elija quien la mira, en vez
        // de que las dos opciones compartan sin querer el mismo estado. La
        // gran mayoría de las pruebas no le presta atención a esto —usan
        // `chatModelReady`, que sigue controlando solo la opción por
        // defecto, exactamente como antes de este cambio—.
        chatModelManagerProvider.overrideWith((ref) {
          final option = ref.watch(chatModelOptionNotifierProvider);
          return switch (option) {
            ChatModelOption.gemma4E4b => chatModelManager,
            ChatModelOption.gemma3nE4b => chatModelManagerGemma3n,
            ChatModelOption.gemma412b => chatModelManagerGemma412b,
          };
        }),
        relationSuggestionServiceProvider.overrideWithValue(
          relationSuggestionService,
        ),
        summarizationServiceProvider.overrideWithValue(summarizationService),
        // `flutter_tts` habla con un canal de plataforma que no existe en
        // un test, mismo motivo que el modelo de Whisper o el de Gemma.
        textToSpeechServiceProvider.overrideWithValue(textToSpeechService),
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

    return LibraryHarness._(
      container,
      database,
      ids,
      chooser,
      files,
      opener,
      saver,
      directoryChooser,
      directoryWriter,
      sharedContent,
      whisperModel,
      chatModel,
      chatModelManager,
      chatModelManagerGemma3n,
      chatModelManagerGemma412b,
      relationSuggestionService,
      summarizationService,
      textToSpeechService,
    );
  }

  final ProviderContainer container;
  final AppDatabase database;
  final FakeIdGenerator ids;

  /// El selector de archivos de mentira, para comprobar que se abrió.
  final FakeFileChooser fileChooser;

  /// El almacén en memoria, para comprobar qué archivo quedó guardado.
  final InMemoryFileStore files;

  /// El abridor de archivos de mentira, para comprobar qué se le pidió abrir
  /// y simular qué contesta el sistema operativo.
  final FakeFileOpener fileOpener;

  /// El selector de guardado de mentira, para el botón de exportar del
  /// detalle.
  final FakeFileSaver fileSaver;

  /// El selector de carpeta y el escritor de mentira, para el paquete de
  /// NotebookLM.
  final FakeDirectoryChooser notebookLmDirectoryChooser;
  final FakeDirectoryWriter notebookLmDirectoryWriter;

  /// Lo que "comparte" otra app, de mentira. `add()` simula que llega algo
  /// con la app ya abierta.
  final FakeSharedContentListener sharedContent;

  /// El modelo de transcripción de mentira, para simular su descarga.
  final FakeWhisperModelManager whisperModel;

  /// El modelo de chat de mentira, para comprobar qué se le preguntó —tanto
  /// en el modo con la bóveda como en una conversación libre— y controlar
  /// qué contesta.
  final FakeChatModel chatModel;

  /// El estado del modelo de chat de mentira para la opción por defecto
  /// ([ChatModelOption.gemma4E4b]), para simular que ya está descargado o
  /// no.
  final FakeChatModelManager chatModelManager;

  /// El estado del modelo de chat de mentira para la otra opción
  /// ([ChatModelOption.gemma3nE4b]) — independiente del de arriba, para
  /// probar que cambiar de opción en `ChatModelScreen` de verdad consulta
  /// y descarga la que corresponde, no siempre la misma.
  final FakeChatModelManager chatModelManagerGemma3n;

  /// El estado del modelo de chat de mentira para la opción más pesada
  /// ([ChatModelOption.gemma412b]) — independiente de las otras dos, por
  /// el mismo motivo.
  final FakeChatModelManager chatModelManagerGemma412b;

  /// El servicio de sugerencias de vínculos de mentira, para comprobar qué
  /// se le pidió al "asistente con IA" del grafo y controlar qué contesta.
  final FakeRelationSuggestionService relationSuggestionService;

  /// El resumidor de mentira, para comprobar qué se le pidió resumir y
  /// controlar qué contesta.
  final FakeSummarizationService summarizationService;

  /// El motor de voz de mentira, para comprobar qué se le pidió leer y
  /// simular que termina —o falla— de leer un fragmento.
  final FakeTextToSpeechService textToSpeechService;

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
