import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_library_progress.dart';

/// En qué anda la carga de la biblioteca de ejemplo.
@immutable
sealed class SampleLibraryState {
  const SampleLibraryState();
}

/// No se está cargando nada, y en esta sesión no se cargó.
final class SampleLibraryIdle extends SampleLibraryState {
  const SampleLibraryIdle();
}

/// Cargando, con su avance. [cancelling] desde que se pidió cortar hasta
/// que lo que estaba en curso termina de soltarse.
final class SampleLibraryLoading extends SampleLibraryState {
  const SampleLibraryLoading({this.progress, this.cancelling = false});

  /// `null` hasta que la carga informa cuánto hay.
  final SampleLoadProgress? progress;
  final bool cancelling;
}

/// Terminó una pasada —entera o cancelada—, con lo que pasó.
final class SampleLibraryFinished extends SampleLibraryState {
  const SampleLibraryFinished(this.report);

  final SampleLoadReport report;
}

/// La pasada se cortó por un error que no es de un recurso sino de la carga
/// misma: no se pudo preparar la carpeta temporal, por ejemplo.
final class SampleLibraryFailed extends SampleLibraryState {
  const SampleLibraryFailed(this.message);

  final String message;
}
