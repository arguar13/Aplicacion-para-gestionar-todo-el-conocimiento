import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/domain/services/study_cost.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_keywords_fill_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_analysis_start.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El original donde se marca el resumen, la síntesis y las palabras clave
/// (F43, paso 15, M5): el de un documento procesado o el de una fuente de la
/// Biblioteca. **Una sola barra y una sola pantalla para los dos** (F45, paso
/// 7b, decisión H): los mismos botones, el mismo visor y el mismo lector
/// flotante.
///
/// **Cada uno marca lo suyo, por su propia clave, como siempre**: el de
/// Procesado, sobre su copia; el de la Biblioteca, sobre la fuente. Nada de
/// uno pinta al otro, y de la Biblioteca no se borra ningún texto ni archivo:
/// lo que se marca son las marcas de estudiar de la persona.
///
/// - [ProcessedOriginalStudy]: la copia del original de un documento
///   procesado. Lo marcado ahí es lo estudiado del procesado mismo —el
///   resumen, la síntesis y las palabras clave de su texto propio, con la
///   clave `procesado:…`—, en las posiciones del original: ver
///   `ProcessedOriginalStudyRepository`.
/// - [SourceOriginalStudy]: el original de una fuente, con su texto
///   extraído. Se analiza y se marca ese mismo texto, con la clave de su
///   forma (F36).
@immutable
sealed class OriginalStudy {
  /// La copia del original del procesado `documentId`, con el texto de la
  /// fuente con que se corresponde (`original`).
  const factory OriginalStudy({
    required String documentId,
    required StudyText original,
  }) = ProcessedOriginalStudy;

  const OriginalStudy._();

  /// El original de una fuente de la Biblioteca, con su texto extraído.
  const factory OriginalStudy.source(StudyText text) = SourceOriginalStudy;

  /// El texto que el visor pinta: el de la copia o el de la fuente. Su
  /// `renditionId` es la clave con que se miran y se eligen las marcas.
  StudyText get original;

  /// La clave del texto que se analiza con la IA: la del análisis y su
  /// avance.
  String get ownKey;

  /// El elemento cuyo texto se analiza: el documento procesado o la fuente.
  String get itemId;

  /// Si se ofrece «Borrar las marcas»: en Procesado, sí; en la Biblioteca,
  /// no (ver [clearOriginalMarks]).
  bool get canClear;
}

/// La copia del original de un documento procesado: ver [OriginalStudy].
final class ProcessedOriginalStudy extends OriginalStudy {
  const ProcessedOriginalStudy({
    required this.documentId,
    required this.original,
  }) : super._();

  final String documentId;

  @override
  final StudyText original;

  @override
  String get ownKey => processedStudyKeyFor(documentId);

  @override
  String get itemId => documentId;

  @override
  bool get canClear => true;

  @override
  bool operator ==(Object other) =>
      other is ProcessedOriginalStudy &&
      other.documentId == documentId &&
      other.original == original;

  @override
  int get hashCode => Object.hash(documentId, original);
}

/// El original de una fuente de la Biblioteca: ver [OriginalStudy]. Su texto
/// es a la vez lo que se pinta y lo que se analiza.
final class SourceOriginalStudy extends OriginalStudy {
  const SourceOriginalStudy(this.original) : super._();

  @override
  final StudyText original;

  @override
  String get ownKey => original.renditionId;

  @override
  String get itemId => original.itemId;

  @override
  bool get canClear => false;

  @override
  bool operator ==(Object other) =>
      other is SourceOriginalStudy && other.original == original;

  @override
  int get hashCode => original.hashCode;
}

/// Lo oculto de lo marcado en el original de [study]: el del documento
/// procesado o el de la fuente, cada uno por su lado.
AutoDisposeStateNotifierProvider<OriginalLayers, Set<StudyMarkKind>>
originalHiddenProviderOf(OriginalStudy study) => switch (study) {
  ProcessedOriginalStudy(:final documentId) => processedOriginalHiddenProvider(
    documentId,
  ),
  SourceOriginalStudy(:final original) => sourceOriginalHiddenProvider(
    original.renditionId,
  ),
};

/// El texto que se analiza para marcar un original, o `null` si
/// no tiene: el texto propio del documento procesado —sus páginas de
/// «Texto», o el de su fuente—, o el de la fuente misma.
final originalOwnTextProvider = Provider.autoDispose
    .family<AsyncValue<StudyText?>, OriginalStudy>(
      (ref, study) => switch (study) {
        ProcessedOriginalStudy(:final documentId) =>
          ref
              .watch(processedStudyTextProvider(documentId))
              .whenData((own) => own.toNullable()?.asStudyText),
        SourceOriginalStudy(:final original) => AsyncData(original),
      },
    );

/// Qué estimar al marcar con la IA un original: cuál y si el análisis
/// empieza de cero —«Rehacer con IA»—.
typedef OriginalStudyPlanKey = ({OriginalStudy study, bool fromStart});

/// Lo que va a pedirle a la IA marcar un original —desde el principio con
/// `fromStart`—: lo que mide «Con tu IA actual» antes de empezar.
final originalStudyPlanProvider = Provider.autoDispose
    .family<AsyncValue<StudyAnalysisPlan>, OriginalStudyPlanKey>(
      (ref, key) => switch (key.study) {
        ProcessedOriginalStudy(:final documentId) => ref.watch(
          processedStudyPlanProvider((
            documentId: documentId,
            fromStart: key.fromStart,
          )),
        ),
        SourceOriginalStudy(:final original) => ref.watch(
          sourceStudyPlanProvider((text: original, fromStart: key.fromStart)),
        ),
      },
    );

/// El resaltado de oraciones de [kind], o `null` si son las palabras clave.
StudyLayer? studyLayerOf(StudyMarkKind kind) =>
    StudyLayer.values.where((layer) => layer.kind == kind).firstOrNull;

/// Si [view] deja ver lo de [kind].
bool originalShows(StudyView view, StudyMarkKind kind) => switch (kind) {
  StudyMarkKind.summary => view.summary,
  StudyMarkKind.synthesis => view.synthesis,
  StudyMarkKind.keyword => view.keywords,
};

/// Muestra u oculta [kind] en el original de [study], y lo recuerda para ese
/// original ([originalHiddenProviderOf]): lo oculto sigue oculto la próxima
/// vez que se abre (M5), en Procesado y en la Biblioteca.
///
/// Ocultar lo que se está eligiendo a mano deja de elegirlo: se elige lo que
/// se ve. Mostrar las palabras clave completa, sin IA, las oraciones de [own]
/// —el texto propio— que quedaron sin las suyas (decisión 85).
Future<void> setOriginalShown(
  WidgetRef ref,
  OriginalStudy study,
  StudyMarkKind kind, {
  required bool shown,
  StudyText? own,
}) async {
  final view = ref.read(studyViewProvider(study.original.renditionId).notifier);
  final layer = studyLayerOf(kind);
  final next = layer == null
      ? view.state.copyWith(keywords: shown)
      : view.state.withLayer(layer, on: shown);
  view.state = next.copyWith(
    pick: () => !shown && next.pick == kind ? null : next.pick,
  );
  await ref
      .read(originalHiddenProviderOf(study).notifier)
      .setHidden(kind, hidden: !shown);
  if (shown && kind == StudyMarkKind.keyword && own != null) {
    unawaited(ensureStudyKeywords(ref, own));
  }
}

/// Marca [kind] en el original con el modelo elegido (M5): el análisis de
/// siempre (F36) sobre el texto propio del documento, por partes y con el
/// servicio en primer plano. Lo prende en el original antes de empezar: lo
/// marcado aparece a medida que llega cada parte.
///
/// [own] es el texto propio y [complete], si su análisis ya terminó: lo que
/// la pantalla ya tiene a la vista, sin volver a leer un libro entero con
/// cada toque. Una sola pasada da el resumen, la síntesis y las palabras
/// clave. Si ya terminó —y lo de [kind] se borró, o la IA no encontró nada—,
/// pedirlo con la IA es rehacer lo de la IA desde el principio: lo elegido a
/// mano queda. Sin el modelo listo, lo avisa con el botón que lo resuelve y
/// no empieza.
Future<void> markOriginalWithAi(
  WidgetRef ref,
  BuildContext context,
  OriginalStudy study,
  StudyMarkKind kind, {
  required StudyText? own,
  required bool complete,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (own == null) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.f43OrigNoOwnText)));
    return;
  }
  final ready = await ensureStudyModelReady(context, ref);
  if (!ready || !context.mounted) return;
  await setOriginalShown(ref, study, kind, shown: true, own: own);
  final notifier = ref.read(studyAnalysisProvider(own.renditionId).notifier);
  if (notifier.isRunning) return;
  if (complete) {
    await reanalyzeForStudy(
      ref,
      renditionId: own.renditionId,
      content: own.content,
      markdown: own.markdown,
      itemId: own.itemId,
    );
    return;
  }
  unawaited(
    notifier.start(
      content: own.content,
      markdown: own.markdown,
      itemId: own.itemId,
    ),
  );
}

/// «Rehacer con IA» (M5): borra lo que marcó la IA —el resumen, la síntesis
/// y las palabras clave— y vuelve a analizar el texto entero. Lo elegido a
/// mano queda (F39, decisión A).
Future<void> redoOriginalWithAi(
  WidgetRef ref,
  BuildContext context,
  OriginalStudy study,
  StudyMarkKind kind, {
  required StudyText? own,
}) async {
  if (own == null) return;
  final ready = await ensureStudyModelReady(context, ref);
  if (!ready || !context.mounted) return;
  await setOriginalShown(ref, study, kind, shown: true, own: own);
  await reanalyzeForStudy(
    ref,
    renditionId: own.renditionId,
    content: own.content,
    markdown: own.markdown,
    itemId: own.itemId,
  );
}

/// Pasa a elegir [kind] a mano en el original (M5): lo muestra y un toque en
/// una oración —o en una palabra, en las palabras clave— la suma o la saca.
Future<void> pickOnOriginal(
  WidgetRef ref,
  OriginalStudy study,
  StudyMarkKind kind, {
  StudyText? own,
}) async {
  await setOriginalShown(ref, study, kind, shown: true, own: own);
  final view = ref.read(studyViewProvider(study.original.renditionId).notifier);
  view.state = view.state.copyWith(pick: () => kind);
}

/// Deja de elegir a mano: lo elegido se sigue viendo.
void stopPickingOnOriginal(WidgetRef ref, OriginalStudy study) {
  final view = ref.read(studyViewProvider(study.original.renditionId).notifier);
  view.state = view.state.copyWith(pick: () => null);
}

/// «Borrar las marcas» de [kind] (M5): las de la IA y las elegidas a mano, en
/// el documento procesado. El original y la fuente no cambian. Lo dice si no
/// se pudo.
///
/// Solo en Procesado ([OriginalStudy.canClear]): de la Biblioteca nada se
/// borra de una vez, y lo marcado sobre una fuente se retoca a mano, de a
/// una.
Future<void> clearOriginalMarks(
  WidgetRef ref,
  BuildContext context,
  OriginalStudy study,
  StudyMarkKind kind,
) async {
  if (!study.canClear) return;
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (kind == ref.read(studyViewProvider(study.original.renditionId)).pick) {
    stopPickingOnOriginal(ref, study);
  }
  final result = await ref
      .read(studyRepositoryProvider)
      .clearKind(study.original.renditionId, kind);
  result.mapLeft(
    (failure) => messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
  );
}
