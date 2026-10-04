import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// En qué va la descarga de un modelo.
sealed class ModelDownloadState {
  const ModelDownloadState();
}

/// Sin descarga en curso: no empezó, terminó bien o se canceló. Si el
/// modelo está, lo dice su gestor (`isReady`), no este estado.
class ModelDownloadIdle extends ModelDownloadState {
  const ModelDownloadIdle();
}

/// Bajando: [progress] de 0 a 1.
class ModelDownloadRunning extends ModelDownloadState {
  const ModelDownloadRunning(this.progress);

  final double progress;
}

/// La última descarga falló por [error] —el que traduce el gestor del
/// modelo—.
class ModelDownloadFailed extends ModelDownloadState {
  const ModelDownloadFailed(this.error);

  final Object error;
}

/// La descarga de un modelo, viva aparte de su pantalla: una sola por
/// modelo.
///
/// Antes la llevaba la pantalla. Salir de ella no cortaba la descarga —el
/// gestor la seguía—, pero al volver la pantalla no la veía y ofrecía
/// «Descargar» otra vez: una segunda descarga escribiendo sobre el mismo
/// archivo, que en los modelos de Gemma —sin huella con qué comprobarlo—
/// podía dejarlo corrupto. Ahora la pantalla mira este estado: al volver
/// muestra el avance de la que sigue, y [start] no arranca otra.
///
/// Con el gestor de descargas del sistema (F29) la descarga sigue aunque se
/// cierre la app: al volver a abrirla, [resume] se engancha a la que sigue
/// —o recoge cómo terminó— sin empezar otra.
///
/// Si la baja la app y no el sistema, mientras baja mantiene viva la app con
/// el servicio en primer plano (`keeper`): así sigue con la app minimizada,
/// y la notificación dice qué modelo se baja y cuánto va ([detail], ver
/// `LongWorkDetail`). Si la baja el sistema no hace falta: baja en su propio
/// proceso, con su propia notificación.
class ModelDownloadNotifier extends StateNotifier<ModelDownloadState> {
  ModelDownloadNotifier({
    required LongWorkKeeper Function()? keeper,
    required this.detail,
    void Function()? onFinished,
  }) : _keeperOf = keeper,
       _onFinished = onFinished,
       super(const ModelDownloadIdle());

  /// Qué modelo es, para la notificación.
  final String detail;

  /// `null` si la descarga no necesita que la app siga viva.
  final LongWorkKeeper Function()? _keeperOf;

  /// Lo que sigue a una descarga terminada —despertar a quien esperaba el
  /// modelo—, haya o no una pantalla mirando.
  final void Function()? _onFinished;

  LongWorkKeeper? _keeper;
  StreamSubscription<double>? _subscription;

  /// En milésimas: la notificación muestra el porcentaje, y el coordinador
  /// solo le habla a Android cuando ese porcentaje cambia.
  static const _steps = 1000;

  /// Empieza a bajar con [download] —la descarga del gestor del modelo—, si
  /// no hay una en curso. Devuelve si la empezó.
  bool start(Stream<double> Function() download) {
    if (state is ModelDownloadRunning) return false;

    final keeper = _keeper ??= _keeperOf?.call();
    state = const ModelDownloadRunning(0);
    keeper?.working(done: 0, total: _steps, detail: detail);

    _subscription = download().listen(
      (progress) {
        if (!mounted) return;
        state = ModelDownloadRunning(progress);
        keeper?.working(
          done: (progress * _steps).round(),
          total: _steps,
          detail: detail,
        );
      },
      onError: (Object error) {
        keeper?.idle();
        if (!mounted) return;
        // Cancelada desde otro lado: no es un error que mostrar.
        state = error is ModelDownloadCancelledException
            ? const ModelDownloadIdle()
            : ModelDownloadFailed(error);
      },
      onDone: () {
        keeper?.idle();
        if (mounted) state = const ModelDownloadIdle();
        _onFinished?.call();
      },
      // Los gestores cierran el stream después de un error: sin esto, ese
      // cierre llegaba como «terminó» y pisaba el error con «listo».
      cancelOnError: true,
    );
    return true;
  }

  /// Al abrir la app: si el gestor del modelo tiene una descarga en curso
  /// ([isDownloading]) —con el gestor del sistema, también una que siguió
  /// con la app cerrada, terminada o no—, se engancha a esa con [download],
  /// que la sigue en vez de empezar otra. Si no hay ninguna, no hace nada:
  /// nada se baja sin que la persona lo pida. Devuelve si se enganchó.
  Future<bool> resume({
    required Future<bool> Function() isDownloading,
    required Stream<double> Function() download,
  }) async {
    if (state is ModelDownloadRunning) return false;
    if (!await isDownloading()) return false;
    if (!mounted) return false;
    return start(download);
  }

  /// Corta la descarga en curso y borra lo bajado, con [cancelDownload] —la
  /// del gestor del modelo—. Queda como si nunca hubiera empezado.
  Future<void> cancel(Future<void> Function() cancelDownload) async {
    if (state is! ModelDownloadRunning) return;
    await _subscription?.cancel();
    _subscription = null;
    _keeper?.idle();
    state = const ModelDownloadIdle();
    await cancelDownload();
  }

  /// Olvida el error de la última descarga —se eligió otro modelo, por
  /// ejemplo—. Una descarga en curso no se toca.
  void clearError() {
    if (state is ModelDownloadFailed) state = const ModelDownloadIdle();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _keeper?.idle();
    super.dispose();
  }
}
