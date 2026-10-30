import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/domain/services/study_cost.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_keywords_fill_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';

/// Lo que se dejó oculto de lo marcado en un original (F43, paso 15, M5): el
/// resumen, la síntesis o las palabras clave. El de cada documento procesado
/// ([processedOriginalHiddenProvider]) y, desde que la Biblioteca abre su
/// original con la misma barra (F45, paso 7b, decisión H), el de cada fuente
/// ([sourceOriginalHiddenProvider]): cada uno por su lado.
///
/// **Lo marcado se ve siempre, salvo que se oculte.** Las palabras clave, una
/// vez hechas, quedan en rosa cada vez que se abre el original; ocultarlas
/// queda recordado para ese original, y lo mismo el resumen y la síntesis:
/// lo que la persona apagó no vuelve a prenderse solo. Se guarda en el
/// teléfono, con el tema y el idioma: es cómo se mira, no lo que el documento
/// tiene —no pasa por la copia ni por la unión de bóvedas—.
///
/// El de un documento procesado se guarda por documento y no por texto: el
/// original de un documento es siempre la misma copia, aunque el texto de su
/// fuente se vuelva a extraer. El de una fuente, por su forma de texto, que es
/// la que lleva sus marcas.
class OriginalLayers extends StateNotifier<Set<StudyMarkKind>> {
  OriginalLayers({required SharedPreferences prefs, required this.key})
    : _prefs = prefs,
      super(_read(prefs, key));

  final SharedPreferences _prefs;

  /// Dónde se guarda: [processedKeyOf] o [sourceKeyOf].
  final String key;

  /// La clave del original del procesado [documentId].
  static String processedKeyOf(String documentId) =>
      'processed_original_hidden.$documentId';

  /// La clave del original de la fuente cuyo texto es [renditionId].
  static String sourceKeyOf(String renditionId) =>
      'source_original_hidden.$renditionId';

  static Set<StudyMarkKind> _read(SharedPreferences prefs, String key) {
    final names = prefs.getStringList(key) ?? const [];
    return {
      for (final kind in StudyMarkKind.values)
        if (names.contains(kind.name)) kind,
    };
  }

  /// Oculta [kind] o lo vuelve a mostrar, y lo recuerda.
  Future<void> setHidden(StudyMarkKind kind, {required bool hidden}) async {
    final next = {...state};
    if (hidden) {
      next.add(kind);
    } else {
      next.remove(kind);
    }
    if (next.length == state.length && next.containsAll(state)) return;
    state = next;
    if (next.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setStringList(key, [for (final kind in next) kind.name]);
    }
  }
}

/// Lo oculto del original de un documento procesado, por su id.
final processedOriginalHiddenProvider = StateNotifierProvider.autoDispose
    .family<OriginalLayers, Set<StudyMarkKind>, String>(
      (ref, documentId) => OriginalLayers(
        prefs: ref.watch(sharedPreferencesProvider),
        key: OriginalLayers.processedKeyOf(documentId),
      ),
    );

/// Lo oculto del original de una fuente de la Biblioteca, por su forma de
/// texto (F45, paso 7b).
final sourceOriginalHiddenProvider = StateNotifierProvider.autoDispose
    .family<OriginalLayers, Set<StudyMarkKind>, String>(
      (ref, renditionId) => OriginalLayers(
        prefs: ref.watch(sharedPreferencesProvider),
        key: OriginalLayers.sourceKeyOf(renditionId),
      ),
    );

/// Si las palabras clave de un documento procesado —por su id— se muestran
/// resaltadas de entrada: sí, salvo que la persona las haya ocultado en ese
/// documento (M5). Lo leen el original y cualquier otra pantalla que muestre
/// su texto —los visores de Repasar, que ofrecen «resaltar palabras clave»
/// prendido por defecto—: una sola preferencia por documento, la misma en
/// todos lados. Para cambiarla, `processedOriginalHiddenProvider(...).notifier
/// .setHidden(StudyMarkKind.keyword, hidden: …)`.
///
/// Las marcas mismas no viven acá: son las de estudiar del documento (F36,
/// clave `processedStudyKeyFor`), la única fuente del resumen, la síntesis y
/// las palabras clave —las que se marcan en el original y las que Repasar
/// muestra como vistas vivas (decisión E)—.
final processedKeywordsShownProvider = Provider.autoDispose
    .family<bool, String>(
      (ref, documentId) => !ref
          .watch(processedOriginalHiddenProvider(documentId))
          .contains(StudyMarkKind.keyword),
    );

/// Qué estimar al marcar con la IA el original de un documento (M5): el
/// documento y si el análisis empieza de cero —«Rehacer con IA» borra lo que
/// hizo la IA y vuelve a empezar—.
typedef ProcessedStudyPlanKey = ({String documentId, bool fromStart});

/// Lo que va a pedirle a la IA marcar el original de un documento procesado
/// (M5): el análisis de siempre (F36) sobre su texto propio, desde donde
/// quedó —o desde el principio, si ya terminó o se pide de cero—, en pedidos y
/// tokens. Es lo que mide el aviso «Con tu IA actual» antes de empezar.
///
/// Parte el texto como el análisis, en otro hilo si es un libro.
final processedStudyPlanProvider = FutureProvider.autoDispose
    .family<StudyAnalysisPlan, ProcessedStudyPlanKey>((ref, key) async {
      final own =
          (await ref
                  .watch(processedRepositoryProvider)
                  .studyTextOf(key.documentId))
              .toNullable();
      if (own == null) return StudyAnalysisPlan.nothing;
      return _planOf(ref, own.asStudyText, fromStart: key.fromStart);
    });

/// Qué estimar al marcar con la IA el original de una fuente (F45, paso 7b):
/// su texto y si el análisis empieza de cero.
typedef SourceStudyPlanKey = ({StudyText text, bool fromStart});

/// [processedStudyPlanProvider] para el original de una fuente de la
/// Biblioteca: el mismo análisis, sobre su texto extraído.
final sourceStudyPlanProvider = FutureProvider.autoDispose
    .family<StudyAnalysisPlan, SourceStudyPlanKey>(
      (ref, key) => _planOf(ref, key.text, fromStart: key.fromStart),
    );

/// Lo que va a pedirle a la IA analizar [text] desde donde quedó, o desde el
/// principio con [fromStart] o si ya terminó.
Future<StudyAnalysisPlan> _planOf(
  Ref ref,
  StudyText text, {
  required bool fromStart,
}) async {
  final studied = await ref
      .read(studyRepositoryProvider)
      .read(text.renditionId);
  final job = (
    content: text.content,
    markdown: text.markdown,
    analyzedUntil: fromStart || studied.complete ? 0 : studied.analyzedUntil,
    charBudget: ref.read(studyMarkerProvider).partCharBudget,
  );
  return text.content.length >= kStudyFillIsolateChars
      ? compute(planStudyAnalysisOf, job)
      : planStudyAnalysisOf(job);
}
