import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';

/// Cuánto falta para terminar el análisis de un texto, aproximado (F39): por
/// el ritmo de las partes que ya se hicieron en esta pasada.
///
/// Cuenta desde [start], con el [Clock] inyectado para que las pruebas no
/// esperen. No inventa nada antes de la primera parte: una sola parte ya
/// dice cuánto tarda cada una, pero sin ninguna no hay con qué calcular. Si
/// el total crece porque una parte no entró entera, la estimación crece con
/// él, que es lo que pasa de verdad.
class StudyEta {
  StudyEta({required Clock clock}) : _clock = clock;

  final Clock _clock;
  DateTime? _startedAt;

  /// Empieza a contar: la pasada recién arranca.
  void start() => _startedAt = _clock();

  /// Lo que falta según [progress], redondeado a los segundos; `null` si
  /// todavía no hay una parte hecha en esta pasada o ya no queda nada.
  Duration? remaining(StudyProgress progress) {
    final startedAt = _startedAt;
    if (startedAt == null || progress.partsDone <= 0) return null;
    final left = progress.partsTotal - progress.partsDone;
    if (left <= 0) return null;
    final elapsed = _clock().difference(startedAt);
    if (elapsed.isNegative) return null;
    final perPart = elapsed.inMilliseconds / progress.partsDone;
    return Duration(seconds: (perPart * left / 1000).round());
  }
}
