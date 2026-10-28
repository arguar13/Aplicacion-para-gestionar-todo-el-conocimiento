import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_notice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_task_providers.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_run_usage_saver.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_original_study_repository.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_study_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/data/repositories/keyed_study_repository.dart';
import 'package:sinapsis/features/study/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/study/domain/services/study_eta.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Dónde se guarda lo estudiado: el texto de una forma de la Biblioteca, en
/// `study_marks`; el texto propio de un documento procesado (F41, decisión I),
/// en sus partes —por su clave `procesado:…`—; y la copia del original de un
/// procesado (decisión H) muestra lo elegido de él, sin guardar nada —por su
/// clave `procesado-original:…`—.
final studyRepositoryProvider = Provider<StudyRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  final telemetry = ref.watch(telemetryServiceProvider);
  return KeyedStudyRepository(
    fallback: StudyRepositoryImpl(database: database, telemetry: telemetry),
    byPrefix: {
      kProcessedStudyKeyPrefix: ProcessedStudyRepositoryImpl(
        database: database,
        telemetry: telemetry,
      ),
      kProcessedOriginalStudyKeyPrefix: ProcessedOriginalStudyRepository(
        ref.watch(processedRepositoryProvider),
      ),
    },
  );
});

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

/// El pedido que falló por algo pasajero y se está repitiendo solo (F39):
/// «Reintentando (2 de 4)…».
@immutable
class StudyRetry {
  const StudyRetry({
    required this.attempt,
    required this.maxAttempts,
    required this.failure,
  });

  /// El intento que viene, de 2 a [maxAttempts].
  final int attempt;
  final int maxAttempts;
  final CloudModelFailure failure;

  @override
  bool operator ==(Object other) =>
      other is StudyRetry &&
      other.attempt == attempt &&
      other.maxAttempts == maxAttempts &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(attempt, maxAttempts, failure);
}

/// Analizando: [progress], o `null` mientras se prepara la primera parte.
class StudyAnalysisRunning extends StudyAnalysisState {
  const StudyAnalysisRunning(this.progress, {this.retry, this.remaining});

  final StudyProgress? progress;

  /// Si la IA en la nube falló por algo pasajero y se está reintentando.
  final StudyRetry? retry;

  /// Cuánto falta, aproximado, por el ritmo de las partes ya hechas; `null`
  /// hasta tener una parte hecha (F39).
  final Duration? remaining;
}

/// Terminó la pasada; [unreadParts] partes no se pudieron leer.
class StudyAnalysisDone extends StudyAnalysisState {
  const StudyAnalysisDone({this.unreadParts = 0});

  final int unreadParts;
}

/// Se cortó por un error del modelo —sin conexión, sin cuota—: lo analizado
/// hasta ahí quedó guardado, y volver a pedirlo sigue desde ahí. Si [error]
/// es un `CloudModelException`, [failure] trae la clase de falla (F39).
class StudyAnalysisFailed extends StudyAnalysisState {
  const StudyAnalysisFailed(this.error);

  final Object error;

  /// La clase de falla de la IA en la nube; `null` si fue otra cosa (Gemma,
  /// un error del programa).
  CloudModelFailure? get failure {
    final error = this.error;
    return error is CloudModelException ? error.failure : null;
  }
}

/// El análisis de un texto para estudiarlo (F36), por partes.
///
/// Vive aparte de la pantalla, como la bajada del audio de YouTube: salir del
/// detalle no lo corta, y volver muestra cuánto va. Mientras analiza mantiene
/// viva la app con el servicio en primer plano: un libro con Gemma en el
/// teléfono son muchos minutos, y al minimizar la app se congelaría.
///
/// Cada pasada es una tarea de la IA (F39, paso 6): «Lo que hizo la IA» la
/// muestra en vivo —la parte que va, el modelo, el tiempo y los tokens— y, al
/// terminar, deja una pasada de estudio (`AiRunScope.study`) con lo que costó.
class StudyAnalysisNotifier extends StateNotifier<StudyAnalysisState> {
  StudyAnalysisNotifier({
    required this.renditionId,
    required AnalyzeForStudy Function() analyze,
    LongWorkKeeper Function()? keeper,
    Stream<AiNotice>? notices,
    Clock? clock,
    AiTaskTracker? tasks,
    AiRunRepository Function()? runs,
    TelemetryService? telemetry,
    String? Function()? modelName,
    Future<String?> Function(String itemId)? titleOf,
  }) : _analyze = analyze,
       _keeperOf = keeper,
       _notices = notices,
       _eta = StudyEta(clock: clock ?? DateTime.now),
       _tasks = tasks,
       _runs = runs,
       _telemetry = telemetry,
       _modelName = modelName,
       _titleOf = titleOf,
       super(const StudyAnalysisIdle());

  final String renditionId;
  final AnalyzeForStudy Function() _analyze;

  /// Los avisos de la IA en la nube: de ahí salen los reintentos (F39).
  final Stream<AiNotice>? _notices;
  final StudyEta _eta;

  /// El servicio en primer plano; `null` en las pruebas que no lo miran.
  final LongWorkKeeper Function()? _keeperOf;
  LongWorkKeeper? _keeper;

  /// Lo que la IA está haciendo ahora, y dónde queda lo que costó cada pasada
  /// (F39, paso 6). Sin ellos —las pruebas que no los miran—, el análisis
  /// anda igual.
  final AiTaskTracker? _tasks;
  final AiRunRepository Function()? _runs;
  final TelemetryService? _telemetry;
  final String? Function()? _modelName;

  /// El título del documento, para decir qué se analiza.
  final Future<String?> Function(String itemId)? _titleOf;

  /// La tarea en curso, para contarle los reintentos.
  AiTaskHandle? _task;

  var _stopRequested = false;

  bool get isRunning => state is StudyAnalysisRunning;

  /// Analiza lo que falta de [content]. Si ya está analizando, no hace nada.
  /// [itemId] es el documento: con él la pasada queda en «Lo que hizo la IA».
  Future<void> start({
    required String content,
    required bool markdown,
    String? itemId,
  }) async {
    if (isRunning) return;
    _stopRequested = false;
    state = const StudyAnalysisRunning(null);
    final keeper = _keeper ??= _keeperOf?.call();
    keeper?.working(done: 0, total: 0);
    _eta.start();

    var unread = 0;
    final retries = _notices?.listen(_onNotice);
    final task = _task = _tasks?.begin(
      kind: AiTaskKind.studyAnalysis,
      title: (itemId == null ? null : await _titleOf?.call(itemId)) ?? '',
      itemId: itemId,
      model: _modelName?.call(),
      steps: const [
        AiTaskStepKind.studySplit,
        AiTaskStepKind.studySend,
        AiTaskStepKind.studyJoin,
      ],
    );
    String? runId;
    AiRunUsageSaver? usage;
    try {
      Future<void> analyze() async {
        await for (final progress in _analyze()(
          renditionId: renditionId,
          content: content,
          markdown: markdown,
          shouldStop: () => _stopRequested || !mounted,
        )) {
          unread = progress.unreadParts;
          if (!mounted) return;
          // Una parte terminada es que lo pasajero pasó.
          state = StudyAnalysisRunning(
            progress,
            remaining: _eta.remaining(progress),
          );
          keeper?.working(done: progress.partsDone, total: progress.partsTotal);
          task?.parts(progress.partsDone, progress.partsTotal);
          // La pasada se abre cuando hay partes que analizar: un texto sin
          // nada por hacer no deja nada en «Lo que hizo la IA».
          if (runId == null && itemId != null && progress.partsTotal > 0) {
            runId = await _openRun(itemId);
            if (runId != null && task != null) {
              usage = AiRunUsageSaver(
                runs: _runs!(),
                telemetry: _telemetry!,
                runId: runId!,
                task: task,
                hint: 'StudyAnalysisNotifier',
              );
            }
          }
        }
      }

      await (task == null ? analyze() : task.run(analyze));
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
      unawaited(retries?.cancel());
      keeper?.idle();
      // Lo que costó, y la pasada cerrada, antes de que la tarea deje de
      // verse: «Lo que hizo la IA» vuelve a leer cuando termina. También si
      // se cortó o falló: los tokens ya se gastaron.
      await usage?.save();
      await _closeRun(runId);
      if (usage != null) {
        usage!.end();
      } else {
        task?.end();
      }
      _task = null;
    }
  }

  /// Abre la pasada de estudio de [itemId]; `null` si no se pudo, y se
  /// registra: el análisis sigue sin dejar su historia.
  Future<String?> _openRun(String itemId) async {
    final runs = _runs;
    final telemetry = _telemetry;
    if (runs == null || telemetry == null) return null;
    final started = await runs().startRun(
      itemId,
      model: _modelName?.call(),
      scope: AiRunScope.study,
    );
    return started.fold((failure) {
      telemetry.recordError(
        failure,
        StackTrace.current,
        hint: 'StudyAnalysisNotifier: no se pudo abrir la pasada de estudio',
      );
      return null;
    }, (id) => id);
  }

  Future<void> _closeRun(String? runId) async {
    final runs = _runs;
    final telemetry = _telemetry;
    if (runId == null || runs == null || telemetry == null) return;
    (await runs().finishRun(runId)).match(
      (failure) => telemetry.recordError(
        failure,
        StackTrace.current,
        hint: 'StudyAnalysisNotifier: no se pudo cerrar la pasada de estudio',
      ),
      (_) {},
    );
  }

  /// Un reintento de la IA en la nube mientras se analiza: se muestra en la
  /// franja hasta que la respuesta vuelve a llegar o se termina la parte.
  void _onNotice(AiNotice notice) {
    final current = state;
    if (!mounted || current is! StudyAnalysisRunning) return;
    switch (notice) {
      case AiRetryNotice():
        _task?.retry(
          AiTaskRetry(
            attempt: notice.attempt,
            maxAttempts: notice.maxAttempts,
            failure: notice.failure,
          ),
        );
        state = StudyAnalysisRunning(
          current.progress,
          remaining: current.remaining,
          retry: StudyRetry(
            attempt: notice.attempt,
            maxAttempts: notice.maxAttempts,
            failure: notice.failure,
          ),
        );
      case AiRetryEndedNotice():
        if (current.retry == null) return;
        _task?.retry(null);
        state = StudyAnalysisRunning(
          current.progress,
          remaining: current.remaining,
        );
      // Los demás avisos los muestra la app arriba de todo.
      // ignore: no_default_cases
      default:
        return;
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
        notices: ref.read(aiNoticeBusProvider).notices,
        clock: ref.read(clockProvider),
        tasks: ref.read(aiTaskTrackerProvider),
        runs: () => ref.read(aiRunRepositoryProvider),
        telemetry: ref.read(telemetryServiceProvider),
        modelName: ref.read(languageModelNameProvider),
        titleOf: (itemId) async =>
            (await ref.read(libraryRepositoryProvider).findById(itemId))
                .getRight()
                .toNullable()
                ?.title,
      ),
    );

/// Vuelve a analizar el texto desde cero (F36): borra lo estudiado —también
/// las palabras elegidas a mano— y lo analiza de nuevo.
Future<void> reanalyzeForStudy(
  WidgetRef ref, {
  required String renditionId,
  required String content,
  required bool markdown,
  String? itemId,
}) async {
  final notifier = ref.read(studyAnalysisProvider(renditionId).notifier);
  if (notifier.isRunning) return;
  await ref.read(studyRepositoryProvider).clearAi(renditionId);
  unawaited(
    notifier.start(content: content, markdown: markdown, itemId: itemId),
  );
}
