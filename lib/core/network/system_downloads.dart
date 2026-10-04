import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// En qué está una descarga del gestor del sistema.
enum SystemDownloadStatus {
  /// En la fila, todavía sin empezar.
  pending,
  running,

  /// Esperando la red o un reintento: sigue sola cuando puede.
  paused,
  successful,
  failed,

  /// El sistema no la conoce: se canceló, o se borraron los datos del
  /// gestor de descargas.
  unknown,
}

/// Por qué falló una descarga del sistema, si no fue el servidor.
enum SystemDownloadError {
  /// No hay lugar en el dispositivo.
  insufficientSpace,

  /// Se cortó y el servidor no deja retomarla.
  cannotResume,

  /// Otra cosa: el disco, demasiadas redirecciones, algo que el sistema no
  /// supo clasificar.
  other,
}

/// Lo que dice el sistema de una descarga.
@immutable
class SystemDownloadState {
  const SystemDownloadState({
    required this.status,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.httpStatus,
    this.error,
  });

  const SystemDownloadState.unknown()
    : this(status: SystemDownloadStatus.unknown);

  final SystemDownloadStatus status;
  final int downloadedBytes;

  /// `null` hasta que el servidor lo dice.
  final int? totalBytes;

  /// Si falló porque el servidor dijo que no: lo que contestó.
  final int? httpStatus;

  /// Si falló por otra cosa.
  final SystemDownloadError? error;

  @override
  String toString() =>
      'SystemDownloadState(${status.name} $downloadedBytes/$totalBytes'
      '${httpStatus == null ? '' : ' http $httpStatus'}'
      '${error == null ? '' : ' ${error!.name}'})';
}

/// El gestor de descargas del sistema (F29): en Android,
/// `android.app.DownloadManager`, que baja en su propio proceso —sigue con
/// la app cerrada y tras reiniciar el teléfono, retoma solo y muestra su
/// notificación—.
abstract interface class SystemDownloads {
  /// La carpeta donde el sistema puede dejar archivos de la app: en Android,
  /// la carpeta propia de la app en el almacenamiento compartido
  /// (`Android/data/<app>/files`). El gestor no puede escribir en la carpeta
  /// interna.
  Directory get directory;

  /// Pide bajar [url] a [destination], dentro de [directory], con
  /// [headers]; [label] dice qué es, para la notificación. Devuelve el
  /// número con que el sistema la reconoce.
  Future<int> enqueue({
    required String url,
    required File destination,
    Map<String, String> headers = const {},
    String? label,
  });

  Future<SystemDownloadState> query(int id);

  /// Olvida la descarga [id]: la corta si sigue, y borra el archivo que
  /// estaba escribiendo si sigue en su lugar.
  Future<void> remove(int id);

  /// Cuánto lugar libre hay donde está [directory]; `null` si no se sabe.
  Future<int?> freeBytes();
}

/// [SystemDownloads] sobre `DownloadManager`, por el canal
/// `app.sinapsis/system_downloads` (ver `SystemDownloadsChannel` en
/// Android).
class MethodChannelSystemDownloads implements SystemDownloads {
  MethodChannelSystemDownloads._(this._channel, this.directory);

  static const _defaultChannel = MethodChannel('app.sinapsis/system_downloads');

  /// El gestor del sistema, si este dispositivo lo tiene disponible: Android
  /// con el gestor de descargas habilitado y el almacenamiento compartido
  /// montado —eso lo dice Android contestando `null`—. `null` también fuera
  /// de Android —el escritorio, la web—, y se baja dentro de la app. Un
  /// error del canal no se toma por "no hay": es un error.
  static Future<MethodChannelSystemDownloads?> resolve({
    MethodChannel channel = _defaultChannel,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final path = await channel.invokeMethod<String>('directory');
    if (path == null) return null;
    return MethodChannelSystemDownloads._(channel, Directory(path));
  }

  final MethodChannel _channel;

  @override
  final Directory directory;

  @override
  Future<int> enqueue({
    required String url,
    required File destination,
    Map<String, String> headers = const {},
    String? label,
  }) async {
    final id = await _channel.invokeMethod<int>('enqueue', {
      'url': url,
      'path': destination.path,
      'headers': headers,
      'label': ?label,
    });
    return id!;
  }

  @override
  Future<SystemDownloadState> query(int id) async {
    final state = await _channel.invokeMapMethod<String, Object?>('query', {
      'id': id,
    });
    if (state == null) return const SystemDownloadState.unknown();
    return SystemDownloadState(
      status: SystemDownloadStatus.values.firstWhere(
        (s) => s.name == state['status'],
        orElse: () => SystemDownloadStatus.unknown,
      ),
      downloadedBytes: (state['downloaded'] as int?) ?? 0,
      totalBytes: switch (state['total']) {
        final int total when total > 0 => total,
        _ => null,
      },
      httpStatus: state['httpStatus'] as int?,
      error: switch (state['error']) {
        'insufficient_space' => SystemDownloadError.insufficientSpace,
        'cannot_resume' => SystemDownloadError.cannotResume,
        null => null,
        _ => SystemDownloadError.other,
      },
    );
  }

  @override
  Future<void> remove(int id) =>
      _channel.invokeMethod<void>('remove', {'id': id});

  @override
  Future<int?> freeBytes() => _channel.invokeMethod<int>('freeBytes');
}
