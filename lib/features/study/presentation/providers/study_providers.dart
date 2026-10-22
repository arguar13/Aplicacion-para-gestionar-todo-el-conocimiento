import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/study/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

final studyRepositoryProvider = Provider<StudyRepository>(
  (ref) => StudyRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  ),
);

/// Lo estudiado del texto de una forma (F36), y cada cambio: lo que se
/// resalta en el documento y lo que se extrae.
final documentStudyProvider = StreamProvider.autoDispose
    .family<DocumentStudy, String>(
      (ref, renditionId) =>
          ref.watch(studyRepositoryProvider).watch(renditionId),
    );

/// Cómo va el análisis de un texto (F36).
@immutable
sealed class StudyAnalysisState {
  const StudyAnalysisState();
}

/// Sin análisis en curso.
class StudyAnalysisIdle extends StudyAnalysisState {
  const StudyAnalysisIdle();
}

/// Analizando: [progress], o `null` mientras se prepara la primera parte.
class StudyAnalysisRunning extends StudyAnalysisState {
  const StudyAnalysisRunning(this.progress);

  final StudyProgress? progress;
}

/// Terminó la pasada; [unreadParts] partes no se pudieron leer.
class StudyAnalysisDone extends StudyAnalysisState {
  const StudyAnalysisDone({this.unreadParts = 0});

  final int unreadParts;
}

/// Se cortó por un error del modelo —sin conexión, sin cuota—: lo analizado
/// hasta ahí quedó guardado, y volver a pedirlo sigue desde ahí.
class StudyAnalysisFailed extends StudyAnalysisState {
  const StudyAnalysisFailed(this.error);

  final Object error;
}

/// El análisis de un texto para estudiarlo (F36), por partes.
///
/// Vive aparte de la pantalla, como la bajada del audio de YouTube: salir del
/// detalle no lo corta, y volver muestra cuánto va. Mientras analiza mantiene
/// viva la app con el servicio en primer plano: un libro con Gemma en el
/// teléfono son muchos minutos, y al minimizar la app se congelaría.
class StudyAnalysisNotifier extends StateNotifier<StudyAnalysisState> {
  StudyAnalysisNotifier({
    required this.renditionId,
    required AnalyzeForStudy Function() analyze,
    LongWorkKeeper Function()? keeper,
  }) : _analyze = analyze,
       _keeperOf = keeper,
       super(const StudyAnalysisIdle());

  final String renditionId;
  final AnalyzeForStudy Function() _analyze;

  /// El servicio en primer plano; `null` en las pruebas que no lo miran.
  final LongWorkKeeper Function()? _keeperOf;
  LongWorkKeeper? _keeper;

  var _stopRequested = false;

  bool get isRunning => state is StudyAnalysisRunning;

  /// Analiza lo que falta de [content]. Si ya está analizando, no hace nada.
  Future<void> start({required String content, required bool markdown}) async {
    if (isRunning) return;
    _stopRequested = false;
    state = const StudyAnalysisRunning(null);
    final keeper = _keeper ??= _keeperOf?.call();
    keeper?.working(done: 0, total: 0);

    var unread = 0;
    try {
      await for (final progress in _analyze()(
        renditionId: renditionId,
        content: content,
        markdown: markdown,
        shouldStop: () => _stopRequested || !mounted,
      )) {
        unread = progress.unreadParts;
        if (!mounted) return;
        state = StudyAnalysisRunning(progress);
        keeper?.working(done: progress.partsDone, total: progress.partsTotal);
      }
      if (mounted) {
        state = _stopRequested
            ? const StudyAnalysisIdle()
            : StudyAnalysisDone(unreadParts: unread);
      }
      // El motor es de terceros —flutter_gemma, un servicio en la nube— y
      // puede fallar de formas que no tienen un tipo propio en Dart.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      if (mounted) state = StudyAnalysisFailed(error);
    } finally {
      keeper?.idle();
    }
  }

  /// Para después de la parte que se está analizando: lo hecho queda.
  void stop() => _stopRequested = true;

  /// Vuelve a mostrar que no hay nada en curso —después de leer un error o
  /// el aviso de que terminó—.
  void acknowledge() {
    if (!isRunning) state = const StudyAnalysisIdle();
  }

  @override
  void dispose() {
    _stopRequested = true;
    _keeper?.idle();
    super.dispose();
  }
}

/// Deliberadamente NO autoDispose: el análisis sigue aunque se salga del
/// detalle.
final studyAnalysisProvider =
    StateNotifierProvider.family<
      StudyAnalysisNotifier,
      StudyAnalysisState,
      String
    >(
      (ref, renditionId) => StudyAnalysisNotifier(
        renditionId: renditionId,
        analyze: () => AnalyzeForStudy(
          repository: ref.read(studyRepositoryProvider),
          marker: ref.read(studyMarkerProvider),
        ),
        keeper: () => ref
            .read(longWorkCoordinatorProvider)
            .keeperFor(LongWorkOwner.study),
      ),
    );

/// Vuelve a analizar el texto desde cero (F36): borra lo estudiado —también
/// las palabras elegidas a mano— y lo analiza de nuevo.
Future<void> reanalyzeForStudy(
  WidgetRef ref, {
  required String renditionId,
  required String content,
  required bool markdown,
}) async {
  final notifier = ref.read(studyAnalysisProvider(renditionId).notifier);
  if (notifier.isRunning) return;
  await ref.read(studyRepositoryProvider).clear(renditionId);
  unawaited(notifier.start(content: content, markdown: markdown));
}
