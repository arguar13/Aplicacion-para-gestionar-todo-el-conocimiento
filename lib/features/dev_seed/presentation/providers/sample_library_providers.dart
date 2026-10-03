import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/config_providers.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/network/interceptors/logging_interceptor.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/dev_seed/data/repositories/shared_preferences_sample_library_ledger.dart';
import 'package:sinapsis/features/dev_seed/data/services/dio_sample_file_downloader.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/dev_seed/domain/repositories/sample_library_ledger.dart';
import 'package:sinapsis/features/dev_seed/domain/sample_library.dart';
import 'package:sinapsis/features/dev_seed/domain/services/sample_file_downloader.dart';
import 'package:sinapsis/features/dev_seed/domain/usecases/load_sample_library_usecase.dart';
import 'package:sinapsis/features/dev_seed/presentation/providers/sample_library_state.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Si la biblioteca de ejemplo existe en esta flavor: en dev y en staging sí;
/// en prod no, ni la sección de Ajustes que la ofrece.
final sampleLibraryAvailableProvider = Provider<bool>(
  (ref) => ref.watch(appFlavorProvider) != AppFlavor.prod,
);

/// Los recursos de la biblioteca de ejemplo. Un provider para que las
/// pruebas carguen una lista chica y conocida.
final sampleLibraryResourcesProvider = Provider<List<SampleResource>>(
  (ref) => sampleLibrary,
);

/// Cliente HTTP para bajar los archivos de ejemplo, sin el aviso global de
/// errores —por la misma razón que `resourceFetchDioProvider`—: que falle
/// uno es parte de lo que la carga informa al final, no algo que tenga que
/// interrumpir al usuario.
///
/// El límite de recepción es entre un pedazo y el siguiente, no para la
/// bajada entera: un libro o un audio largo tarda, y eso no es un error.
final sampleLibraryDioProvider = Provider<Dio>((ref) {
  final logger = ref.watch(appLoggerProvider);

  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: const {
        'User-Agent': 'Sinapsis/0.1 (+lector de contenido personal)',
      },
    ),
  )..interceptors.add(NetworkLoggingInterceptor(logger: logger));
});

final sampleFileDownloaderProvider = Provider<SampleFileDownloader>(
  (ref) => DioSampleFileDownloader(
    dio: ref.watch(sampleLibraryDioProvider),
    temporaryRoot: getTemporaryDirectory,
  ),
);

final sampleLibraryLedgerProvider = Provider<SampleLibraryLedger>(
  (ref) => SharedPreferencesSampleLibraryLedger(
    ref.watch(sharedPreferencesProvider),
  ),
);

final loadSampleLibraryUseCaseProvider = Provider<LoadSampleLibraryUseCase>(
  (ref) => LoadSampleLibraryUseCase(
    resources: ref.watch(sampleLibraryResourcesProvider),
    ledger: ref.watch(sampleLibraryLedgerProvider),
    downloader: ref.watch(sampleFileDownloaderProvider),
    captureItem: ref.watch(captureItemUseCaseProvider),
    repository: ref.watch(libraryRepositoryProvider),
    // Lo mismo que hace la captura a mano: encolar sin esperar.
    enqueue: (itemId) =>
        ref.read(processingQueueProvider.notifier).enqueue(itemId),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Lo que pide la carga para mantener viva la app mientras baja.
final sampleLibraryLongWorkKeeperProvider = Provider<LongWorkKeeper>(
  (ref) => ref
      .watch(longWorkCoordinatorProvider)
      .keeperFor(LongWorkOwner.sampleLibrary),
);

/// Lleva la carga de la biblioteca de ejemplo: la arranca, la corta y dice
/// cuánto va.
///
/// Vive lo que la app, no lo que la pantalla de Ajustes: se toca «Cargar»,
/// se sale a usar la app, y la carga sigue —con la notificación del trabajo
/// largo, para que el sistema no la congele en segundo plano—. Sus
/// dependencias se piden al usarlas, por la misma razón que en la cola de
/// procesamiento: que una reconstrucción de la cadena de proveedores no
/// descarte una carga en curso.
class SampleLibraryNotifier extends StateNotifier<SampleLibraryState> {
  SampleLibraryNotifier({
    required LoadSampleLibraryUseCase Function() load,
    required LongWorkKeeper Function() longWork,
    required AppLogger logger,
  }) : _load = load,
       _longWork = longWork,
       _logger = logger,
       super(const SampleLibraryIdle());

  final LoadSampleLibraryUseCase Function() _load;
  final LongWorkKeeper Function() _longWork;
  final AppLogger _logger;

  CancellationSignal? _cancellation;

  /// Carga lo que falta. Si ya hay una carga en curso no hace nada: tocar
  /// dos veces no arranca dos.
  Future<void> start() async {
    if (_cancellation != null) return;
    final cancellation = _cancellation = CancellationSignal();
    final keeper = _longWork();
    state = const SampleLibraryLoading();

    try {
      final report = await _load()(
        cancellation: cancellation,
        onProgress: (progress) {
          keeper.working(done: progress.done, total: progress.total);
          if (!mounted) return;
          state = SampleLibraryLoading(
            progress: progress,
            cancelling: cancellation.isCancelled,
          );
        },
      );
      for (final failure in report.failures) {
        _logger.warning(
          'Biblioteca de ejemplo: no se cargó «${failure.title}»: '
          '${failure.reason}',
        );
      }
      _logger.info(
        'Biblioteca de ejemplo: ${report.loaded} cargados, '
        '${report.failures.length} fallidos, ${report.alreadyLoaded} ya '
        'estaban${report.cancelled ? ' (cancelada)' : ''}.',
      );
      if (mounted) state = SampleLibraryFinished(report);
    } on Exception catch (e, stackTrace) {
      // Lo que falla en un recurso lo informa la carga en su lista; lo que
      // llega acá es de la carga entera —no se pudo limpiar la carpeta
      // temporal, por ejemplo— y se muestra tal cual.
      _logger.error('La biblioteca de ejemplo se cortó.', e, stackTrace);
      if (mounted) state = SampleLibraryFailed(e.toString());
    } finally {
      keeper.idle();
      _cancellation = null;
    }
  }

  /// Corta la carga: no empieza nada más y suelta lo que se esté bajando.
  /// Lo que ya se guardó, queda.
  void cancel() {
    final cancellation = _cancellation;
    if (cancellation == null) return;
    cancellation.cancel();
    final current = state;
    if (current is SampleLibraryLoading) {
      state = SampleLibraryLoading(
        progress: current.progress,
        cancelling: true,
      );
    }
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }
}

final sampleLibraryProvider =
    StateNotifierProvider<SampleLibraryNotifier, SampleLibraryState>(
      (ref) => SampleLibraryNotifier(
        load: () => ref.read(loadSampleLibraryUseCaseProvider),
        longWork: () => ref.read(sampleLibraryLongWorkKeeperProvider),
        logger: ref.read(appLoggerProvider),
      ),
    );
