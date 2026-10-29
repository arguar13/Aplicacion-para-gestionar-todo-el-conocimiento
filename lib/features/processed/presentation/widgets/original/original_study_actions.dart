import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_study_text.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_keywords_fill_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El original de un documento procesado, para marcar en él (F43, paso 15,
/// M5): el documento y el texto de su copia, con la clave de la copia
/// (`processedOriginalStudyKeyFor`). Lo marcado ahí es lo estudiado del
/// procesado mismo —el resumen, la síntesis y las palabras clave de su texto
/// propio, con la clave `procesado:…`—, en las posiciones del original: ver
/// `ProcessedOriginalStudyRepository`.
@immutable
class OriginalStudy {
  const OriginalStudy({required this.documentId, required this.original});

  final String documentId;

  /// El texto de la copia, el de la fuente con que se corresponde.
  final StudyText original;

  /// La clave con que se estudia el texto propio del procesado: la del
  /// análisis con la IA y su avance.
  String get ownKey => processedStudyKeyFor(documentId);

  @override
  bool operator ==(Object other) =>
      other is OriginalStudy &&
      other.documentId == documentId &&
      other.original == original;

  @override
  int get hashCode => Object.hash(documentId, original);
}

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
/// documento: lo oculto sigue oculto la próxima vez que se abre (M5).
///
/// Ocultar lo que se está eligiendo a mano deja de elegirlo: se elige lo que
/// se ve. Mostrar las palabras clave completa, sin IA, las oraciones de [own]
/// —el texto propio— que quedaron sin las suyas (decisión 85).
Future<void> setOriginalShown(
  WidgetRef ref,
  OriginalStudy study,
  StudyMarkKind kind, {
  required bool shown,
  ProcessedStudyText? own,
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
      .read(processedOriginalHiddenProvider(study.documentId).notifier)
      .setHidden(kind, hidden: !shown);
  if (shown && kind == StudyMarkKind.keyword && own != null) {
    unawaited(ensureStudyKeywords(ref, own.asStudyText));
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
  required ProcessedStudyText? own,
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
  final notifier = ref.read(studyAnalysisProvider(own.key).notifier);
  if (notifier.isRunning) return;
  if (complete) {
    await reanalyzeForStudy(
      ref,
      renditionId: own.key,
      content: own.content,
      markdown: own.markdown,
      itemId: study.documentId,
    );
    return;
  }
  unawaited(
    notifier.start(
      content: own.content,
      markdown: own.markdown,
      itemId: study.documentId,
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
  required ProcessedStudyText? own,
}) async {
  if (own == null) return;
  final ready = await ensureStudyModelReady(context, ref);
  if (!ready || !context.mounted) return;
  await setOriginalShown(ref, study, kind, shown: true, own: own);
  await reanalyzeForStudy(
    ref,
    renditionId: own.key,
    content: own.content,
    markdown: own.markdown,
    itemId: study.documentId,
  );
}

/// Pasa a elegir [kind] a mano en el original (M5): lo muestra y un toque en
/// una oración —o en una palabra, en las palabras clave— la suma o la saca.
Future<void> pickOnOriginal(
  WidgetRef ref,
  OriginalStudy study,
  StudyMarkKind kind, {
  ProcessedStudyText? own,
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
Future<void> clearOriginalMarks(
  WidgetRef ref,
  BuildContext context,
  OriginalStudy study,
  StudyMarkKind kind,
) async {
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
