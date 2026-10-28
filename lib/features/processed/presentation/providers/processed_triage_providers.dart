import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_triage.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';

/// Lo que se va eligiendo en la hoja «¿Qué va a Procesado?» (F41) de una
/// fuente: la hoja, la pantalla de cortar y los visores que marcan los cortes
/// miran el mismo.
class ProcessedTriageController extends StateNotifier<ProcessedTriage> {
  ProcessedTriageController(super.state);

  /// Empieza de nuevo con [triage]: lo que abre la hoja —vacía al triar algo
  /// nuevo; con lo que trae el documento, al volver a triar (paso 4)—.
  set triage(ProcessedTriage triage) => state = triage;

  /// Lo elegido hasta ahora.
  ProcessedTriage get triage => state;

  /// Prende o apaga [section], con [change].
  void setSection(
    ProcessedSection section, {
    required bool on,
    ProcessedChange change = ProcessedChange.add,
  }) => state = state.withSection(section, on: on, change: change);

  /// Prende o apaga la copia del original (decisión H), con [change].
  void setOriginal({
    required bool on,
    ProcessedChange change = ProcessedChange.add,
  }) => state = state.withOriginal(on: on, change: change);

  /// «A Procesado»: el pasaje [anchor] del original, a los fragmentos.
  /// Devuelve si entró —el mismo tramo no entra dos veces—.
  bool cut(ProcessedAnchor anchor, {required String excerpt}) =>
      _add(ProcessedSection.fragments, ProcessedDraft.cut(anchor), excerpt);

  /// «Extraer como nota» mientras se corta (decisión C): el pasaje [anchor],
  /// tal cual, a las notas del documento procesado —no a una nota suelta de
  /// la Biblioteca—.
  bool extractNote(ProcessedAnchor anchor, {required String excerpt}) =>
      _add(ProcessedSection.notes, ProcessedDraft.cut(anchor), excerpt);

  /// Una nota escrita a mano.
  bool writeNote(String content) {
    final text = content.trim();
    if (text.isEmpty) return false;
    return _add(ProcessedSection.notes, ProcessedDraft.written(text), text);
  }

  /// Saca el pasaje [clipId].
  void remove(String clipId) => state = state.withoutClip(clipId);

  /// Elige —o suelta— la imagen [path] de la grilla (decisión L).
  void toggleImage(String path) =>
      state = state.withImages(state.images.toggled(path));

  /// «Todas» las imágenes de la fuente.
  void chooseAllImages() => state = state.withImages(const ImageChoice.all());

  /// «Ninguna».
  void chooseNoImages() => state = state.withImages(ImageChoice.none);

  bool _add(ProcessedSection section, ProcessedDraft draft, String excerpt) {
    final next = state.withClip(section, draft, excerpt: excerpt);
    if (identical(next, state)) return false;
    state = next;
    return true;
  }
}

/// La hoja de cada fuente, mientras alguien la mira: la hoja abierta, la
/// pantalla de cortar encima de ella. Al cerrarse las dos, se suelta.
final processedTriageProvider = StateNotifierProvider.autoDispose
    .family<ProcessedTriageController, ProcessedTriage, String>(
      (ref, sourceItemId) => ProcessedTriageController(
        ProcessedTriage(sourceItemId: sourceItemId),
      ),
    );

/// De qué fuente se está cortando para Procesado, o `null` si de ninguna: lo
/// que la pantalla de cortar declara para todo lo que tiene adentro
/// (`ProviderScope`), y nada más. Fuera de ella —el detalle, «Leer como
/// libro»— la barrita es la de siempre, sin «A Procesado», y no se marca
/// ningún corte.
final processedCutSourceProvider = Provider<String?>((ref) => null);

/// Los fragmentos de un documento procesado sobre la copia de su original
/// (decisión H), por la clave de la copia (`processedOriginalStudyKeyFor`):
/// los visores los marcan con el color de los cortes, como mientras se corta.
/// Sin nada que marcar —el texto de la fuente ya no es el de la copia—,
/// ninguno.
final processedOriginalCutsProvider = Provider.autoDispose
    .family<List<ProcessedAnchor>, String>((ref, key) {
      final documentId = processedDocumentOfOriginalStudyKey(key);
      if (documentId == null) return const [];
      final marks = ref
          .watch(processedOriginalMarksProvider(documentId))
          .valueOrNull;
      if (marks == null) return const [];
      return [
        for (final fragment in marks.fragments)
          ProcessedAnchor(
            renditionId: key,
            start: fragment.start,
            end: fragment.end,
          ),
      ];
    });

/// Si se está cortando de [itemId], quien recibe los cortes; si no, `null`.
ProcessedTriageController? processedCutterFor(WidgetRef ref, String itemId) {
  if (ref.read(processedCutSourceProvider) != itemId) return null;
  return ref.read(processedTriageProvider(itemId).notifier);
}

/// Los tonos de los cortes para Procesado: un durazno que no es ninguno de los
/// nueve de resaltar ni los tres de estudiar, con la letra oscura encima en los
/// dos modos, como un resaltador.
abstract final class ProcessedCutPalette {
  static const light = Color(0xFFFFD9BF);
  static const dark = Color(0xFFFFC199);
  static const ink = Colors.black87;

  static Color of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Los cortes del texto [renditionId] mientras se corta de su fuente, como
/// capas de color —encima de todo lo demás: es lo que se está eligiendo— y
/// cada cambio. Fuera de la pantalla de cortar, ninguna.
List<PaintedRange> watchProcessedCutPaints(
  WidgetRef ref,
  String renditionId, {
  required Brightness brightness,
}) {
  final cuts = watchProcessedCuts(ref, renditionId);
  if (cuts.isEmpty) return const [];
  final color = ProcessedCutPalette.of(brightness);
  return [
    for (final cut in cuts)
      PaintedRange(
        cut.start,
        cut.end,
        background: color,
        foreground: ProcessedCutPalette.ink,
        aboveHighlights: true,
      ),
  ];
}

/// Las anclas de los cortes del texto [renditionId] mientras se corta de su
/// fuente, y cada cambio; fuera de la pantalla de cortar, ninguna.
List<ProcessedAnchor> watchProcessedCuts(WidgetRef ref, String renditionId) {
  if (processedDocumentOfOriginalStudyKey(renditionId) != null) {
    return ref.watch(processedOriginalCutsProvider(renditionId));
  }
  final source = ref.watch(processedCutSourceProvider);
  if (source == null) return const [];
  return ref.watch(processedTriageProvider(source)).cutsIn(renditionId);
}

/// Qué preguntar para la vista previa de una sección: la fuente, la sección,
/// lo pedido y una marca de lo que cambió en la fuente desde la última vez —por
/// ejemplo, cuántas oraciones lleva el resumen mientras la IA lo arma—.
typedef TriagePreviewKey = ({
  String sourceItemId,
  ProcessedSection section,
  SectionEdit edit,
  int revision,
});

/// Cómo va a quedar una sección, sin guardar nada (F41): la vista previa en
/// vivo de la hoja, con cuántas partes y palabras tiene.
///
/// Una sección por vez: prender el resumen no vuelve a paginar el texto de un
/// libro, que ya está calculado mientras siga prendido.
final processedTriagePreviewProvider = FutureProvider.autoDispose
    .family<Either<Failure, SectionPreview>, TriagePreviewKey>((
      ref,
      key,
    ) async {
      final previews = await ref.watch(processSourceUseCaseProvider).preview(
        key.sourceItemId,
        {key.section: key.edit},
      );
      return previews.flatMap(
        (previews) => switch (previews[key.section]) {
          final preview? => right(preview),
          null => left(
            const Failure.validation(message: 'La sección no se previó.'),
          ),
        },
      );
    });
