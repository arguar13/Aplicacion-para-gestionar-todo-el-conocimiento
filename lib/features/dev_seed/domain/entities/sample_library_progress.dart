import 'package:flutter/foundation.dart';

/// Un recurso de la biblioteca de ejemplo que no se pudo cargar, y por qué.
@immutable
class SampleLoadFailure {
  const SampleLoadFailure({required this.title, required this.reason});

  final String title;

  /// El motivo, tal como lo dio quien falló: es una función de desarrollo y
  /// quien la usa quiere ver el error de verdad, no uno traducido.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is SampleLoadFailure &&
      other.title == title &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(title, reason);

  @override
  String toString() => 'SampleLoadFailure($title: $reason)';
}

/// Cuánto va la carga de la biblioteca de ejemplo.
///
/// [total] cuenta solo lo que falta cargar en esta pasada: lo que ya se
/// había cargado antes no se vuelve a tocar y va aparte, en
/// [alreadyLoaded].
@immutable
class SampleLoadProgress {
  const SampleLoadProgress({
    required this.total,
    required this.batch,
    required this.batches,
    this.loaded = 0,
    this.alreadyLoaded = 0,
    this.failures = const [],
    this.current,
  });

  /// Cuántos hay que cargar en esta pasada.
  final int total;

  /// Cuántos se cargaron.
  final int loaded;

  /// Cuántos ya estaban de una pasada anterior y no se tocaron.
  final int alreadyLoaded;

  /// Los que fallaron, en el orden en que fallaron.
  final List<SampleLoadFailure> failures;

  /// La tanda en curso, desde 1; `0` antes de empezar la primera.
  final int batch;

  /// Cuántas tandas hay.
  final int batches;

  /// El título de lo último que empezó a cargarse, o `null` si todavía no
  /// empezó nada.
  final String? current;

  /// Cuántos se terminaron de mirar, bien o mal.
  int get done => loaded + failures.length;

  SampleLoadProgress copyWith({
    int? loaded,
    List<SampleLoadFailure>? failures,
    int? batch,
    String? current,
  }) => SampleLoadProgress(
    total: total,
    batches: batches,
    alreadyLoaded: alreadyLoaded,
    loaded: loaded ?? this.loaded,
    failures: failures ?? this.failures,
    batch: batch ?? this.batch,
    current: current ?? this.current,
  );

  @override
  bool operator ==(Object other) =>
      other is SampleLoadProgress &&
      other.total == total &&
      other.loaded == loaded &&
      other.alreadyLoaded == alreadyLoaded &&
      listEquals(other.failures, failures) &&
      other.batch == batch &&
      other.batches == batches &&
      other.current == current;

  @override
  int get hashCode => Object.hash(
    total,
    loaded,
    alreadyLoaded,
    Object.hashAll(failures),
    batch,
    batches,
    current,
  );

  @override
  String toString() =>
      'SampleLoadProgress($done/$total, tanda $batch/$batches, '
      '${failures.length} fallidos, $alreadyLoaded ya estaban)';
}

/// Cómo terminó una pasada de la carga.
@immutable
class SampleLoadReport {
  const SampleLoadReport({required this.progress, required this.cancelled});

  /// Hasta dónde llegó.
  final SampleLoadProgress progress;

  /// Si se cortó a pedido antes de terminar. Lo que quedó sin cargar se
  /// carga en la próxima pasada.
  final bool cancelled;

  int get loaded => progress.loaded;
  int get alreadyLoaded => progress.alreadyLoaded;
  List<SampleLoadFailure> get failures => progress.failures;

  @override
  bool operator ==(Object other) =>
      other is SampleLoadReport &&
      other.progress == progress &&
      other.cancelled == cancelled;

  @override
  int get hashCode => Object.hash(progress, cancelled);
}
