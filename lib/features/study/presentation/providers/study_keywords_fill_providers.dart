import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/domain/usecases/fill_study_keywords.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';

/// Desde cuántos caracteres un texto se completa en otro hilo: partir y
/// contar un libro entero se nota en la pantalla; uno corto, no, y levantar
/// un hilo costaría más que el trabajo.
const kStudyFillIsolateChars = 50000;

/// Quien parte y cuenta el texto para completar las palabras clave: en otro
/// hilo si el texto es largo (`kStudyFillIsolateChars`), en el momento si no.
final studyFillRunnerProvider = Provider<StudyFillRunner>(
  (ref) =>
      (job) async => job.content.length >= kStudyFillIsolateChars
      ? compute(missingKeywordsOfText, job)
      : missingKeywordsOfText(job),
);

/// Los textos que ya se completaron en esta sesión: completar es mirar el
/// texto entero, y una vez por texto alcanza. Se anota `renditionId:largo`,
/// así un texto que se vuelve a extraer se mira de nuevo.
final studyKeywordsFilledProvider = Provider<Set<String>>((ref) => <String>{});

/// Se asegura de que **toda** oración con contenido del texto [text] ya
/// analizado tenga sus palabras clave (`FillStudyKeywords`): lo analizado
/// antes de que el análisis lo garantizara queda completo, sin IA y sin red.
/// Devuelve cuántas palabras agregó.
///
/// No hace nada mientras el texto se está analizando —el propio análisis pone
/// las palabras de cada parte—, ni si ya se completó en esta sesión. Una falla
/// se registra y no se nota: se vuelve a intentar la próxima vez.
Future<int> ensureStudyKeywords(WidgetRef ref, StudyText text) async {
  if (ref.read(studyAnalysisProvider(text.renditionId))
      is StudyAnalysisRunning) {
    return 0;
  }
  final filled = ref.read(studyKeywordsFilledProvider);
  final key = '${text.renditionId}:${text.content.length}';
  if (!filled.add(key)) return 0;

  final fill = FillStudyKeywords(
    repository: ref.read(studyRepositoryProvider),
    runner: ref.read(studyFillRunnerProvider),
  );
  final telemetry = ref.read(telemetryServiceProvider);
  try {
    return await fill(
      renditionId: text.renditionId,
      content: text.content,
      markdown: text.markdown,
    );
    // El hilo aparte y la base pueden fallar de formas sin tipo propio.
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    filled.remove(key);
    telemetry.recordError(
      error,
      stackTrace,
      hint: 'ensureStudyKeywords: no se pudieron completar las palabras clave',
    );
    return 0;
  }
}
