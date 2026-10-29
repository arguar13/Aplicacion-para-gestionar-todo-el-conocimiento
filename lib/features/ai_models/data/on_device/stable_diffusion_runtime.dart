import 'dart:typed_data';

import 'package:meta/meta.dart';

/// El motor que dibuja en el teléfono (F43, «Exigente»): stable-diffusion.cpp
/// detrás de `libsinapsis_sd.so`. Detrás de una interfaz porque el de verdad
/// solo existe en un teléfono Android con la app armada con el motor: las
/// pruebas usan uno de mentira.
///
/// Dibuja **fuera del isolate de la pantalla** —cargar el modelo y dibujar
/// tardan segundos en el procesador— y de a una imagen por vez: lo que llega
/// mientras dibuja espera su turno.
abstract interface class StableDiffusionRuntime {
  /// Dibuja [job]. Si el modelo de [job] no está cargado, lo carga primero
  /// (y suelta el otro, si había). Falla con [StableDiffusionException].
  Future<StableDiffusionImage> generate(StableDiffusionJob job);

  /// Corta la imagen en curso cuanto antes: la espera de [generate] termina
  /// con `StableDiffusionFailure.cancelled`. Sin una en curso, no hace nada.
  Future<void> cancel();

  /// Saca el modelo de la memoria. El próximo [generate] lo vuelve a cargar.
  Future<void> release();

  /// Si hay un modelo cargado.
  bool get isLoaded;
}

/// Lo que se le pide al motor.
@immutable
class StableDiffusionJob {
  const StableDiffusionJob({
    required this.modelPath,
    required this.prompt,
    required this.width,
    required this.height,
    required this.steps,
    required this.cfg,
    this.seed = -1,
    this.threads = 0,
  });

  final String modelPath;
  final String prompt;

  /// Múltiplos de 64.
  final int width;
  final int height;
  final int steps;
  final double cfg;

  /// -1: al azar.
  final int seed;

  /// Cuántos hilos; 0: los núcleos físicos, lo que elige stable-diffusion.cpp.
  final int threads;
}

/// Una imagen del motor, ya en PNG, con lo que tardó.
@immutable
class StableDiffusionImage {
  const StableDiffusionImage({
    required this.png,
    required this.width,
    required this.height,
    required this.drawTime,
    this.loadTime,
  });

  final Uint8List png;
  final int width;
  final int height;

  /// Lo que tardó en dibujar (sin cargar el modelo).
  final Duration drawTime;

  /// Lo que tardó en cargar el modelo, si esta imagen lo cargó.
  final Duration? loadTime;
}

/// Por qué el motor no dibujó.
enum StableDiffusionFailure {
  /// La app no trae el motor, o es de otra versión.
  unavailable,

  /// El archivo del modelo no se pudo cargar.
  load,

  /// No alcanzó la memoria.
  memory,

  /// Dibujó, pero no devolvió ninguna imagen.
  generate,

  /// Se canceló a pedido.
  cancelled,

  /// Lo pedido no tiene sentido (un tamaño que no es múltiplo de 64).
  arguments,
}

class StableDiffusionException implements Exception {
  const StableDiffusionException(this.failure, [this.detail]);

  final StableDiffusionFailure failure;

  /// Para el registro, nunca para mostrar.
  final String? detail;

  @override
  String toString() =>
      'StableDiffusionException(${failure.name}'
      '${detail == null ? '' : ': $detail'})';
}
