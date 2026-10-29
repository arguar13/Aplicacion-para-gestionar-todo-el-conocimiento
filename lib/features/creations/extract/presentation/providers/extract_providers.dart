import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_text.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_text_provider.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_study_text.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_readable_providers.dart';

/// El texto propio de un documento procesado (decisión I de F41), **vivo**
/// (F43, paso 7, decisión E): se vuelve a leer cada vez que el documento
/// cambia —se editó una página, se volvió a procesar, se marcó algo—, y si
/// el texto quedó igual devuelve el mismo objeto de antes, así lo que se
/// arma con él —los bloques de un libro, lo que se lee en voz alta— no se
/// vuelve a armar. `null` adentro si no tiene texto que estudiar.
final extractOwnTextProvider = AsyncNotifierProvider.autoDispose
    .family<ExtractOwnText, ProcessedStudyText?, String>(ExtractOwnText.new);

/// Ver [extractOwnTextProvider].
class ExtractOwnText
    extends AutoDisposeFamilyAsyncNotifier<ProcessedStudyText?, String> {
  @override
  Future<ProcessedStudyText?> build(String documentId) async {
    // Cuándo se tocó por última vez su contenido: cambia con cada página
    // editada y con cada marca guardada (`markContentChanged`).
    ref.watch(
      processedDocumentProvider(
        documentId,
      ).select((document) => document.valueOrNull?.summary.updatedAt),
    );
    final previous = state.valueOrNull;
    final read = await ref
        .read(processedRepositoryProvider)
        .studyTextOf(documentId);
    // Una lectura que falla se ve como error: el apartado lo dice.
    final own = read.getOrElse((failure) => throw StateError('$failure'));
    if (own != null &&
        previous != null &&
        previous.key == own.key &&
        previous.markdown == own.markdown &&
        previous.content == own.content) {
      return previous;
    }
    return own;
  }
}

/// El texto propio de [documentId] ya leído, o `null` mientras no —o si no
/// tiene—: lo que miran los demás, para no reconstruirse con cada lectura
/// que da lo mismo.
ProcessedStudyText? _ownOf(Ref ref, String documentId) => ref.watch(
  extractOwnTextProvider(documentId).select((text) => text.valueOrNull),
);

/// Los bloques del texto entero de un documento —un libro, en otro hilo—, una
/// vez por texto: los de «Extraer texto completo».
final extractTextBlocksProvider = FutureProvider.autoDispose
    .family<List<ExtractBlock>, String>((ref, documentId) async {
      final own = _ownOf(ref, documentId);
      if (own == null) return const [];
      return extractTextBlocksOff(own.content);
    });

/// En qué está un documento de una extracción.
enum ExtractSectionStatus {
  /// Todavía se lee.
  loading,

  /// Ya no está en Procesado (se borró o está en la papelera): «Fuente
  /// borrada».
  deleted,

  /// Está, pero no tiene texto que estudiar (solo notas, o imágenes).
  noText,

  /// Con su texto y lo estudiado.
  ready,
}

/// Un documento de una extracción, listo para dibujar (F43, paso 7): su
/// título, su texto, lo estudiado de él —las marcas del documento mismo, la
/// única fuente (M8)— y lo que se muestra.
@immutable
class ExtractSection {
  const ExtractSection({
    required this.documentId,
    required this.status,
    this.title = '',
    this.own,
    this.study = DocumentStudy.notStarted,
    this.blocks = const [],
    this.keywordsShown = true,
    this.missing = false,
  });

  final String documentId;
  final ExtractSectionStatus status;
  final String title;

  /// El texto propio, con su clave de estudio (`procesado:…`).
  final ProcessedStudyText? own;

  /// Lo estudiado del texto propio.
  final DocumentStudy study;

  /// Lo que se dibuja: el texto entero o las oraciones.
  final List<ExtractBlock> blocks;

  /// Si sus palabras clave se resaltan: la preferencia del documento (M5).
  final bool keywordsShown;

  /// Si le falta lo que esta extracción muestra —el resumen, la síntesis o,
  /// en el texto completo, las palabras clave—.
  final bool missing;

  /// La clave con que el lector en voz alta y las marcas conocen su texto.
  String? get sourceKey => own?.key;

  /// Las palabras clave que se pintan: ninguna si se ocultaron.
  List<StudyMark> get paintedKeywords =>
      keywordsShown ? study.of(StudyMarkKind.keyword) : const [];

  @override
  bool operator ==(Object other) =>
      other is ExtractSection &&
      other.documentId == documentId &&
      other.status == status &&
      other.title == title &&
      identical(other.own, own) &&
      other.study == study &&
      listEquals(other.blocks, blocks) &&
      other.keywordsShown == keywordsShown &&
      other.missing == missing;

  @override
  int get hashCode => Object.hash(
    documentId,
    status,
    title,
    own,
    study,
    Object.hashAll(blocks),
    keywordsShown,
    missing,
  );
}

/// Qué documento de qué extracción.
typedef ExtractSectionKey = ({StudyCreationKind kind, String documentId});

/// Un documento de una extracción, y cada cambio: si se marca algo en el
/// original, si se edita el texto, si se ocultan las palabras clave —acá o
/// en el original—, se vuelve a armar solo (decisión E).
final extractSectionProvider = Provider.autoDispose
    .family<ExtractSection, ExtractSectionKey>((ref, key) {
      final id = key.documentId;
      final document = ref.watch(processedDocumentProvider(id));
      final found = document.valueOrNull;
      if (found == null || found.inTrash) {
        return ExtractSection(
          documentId: id,
          status: document.isLoading && found == null
              ? ExtractSectionStatus.loading
              : ExtractSectionStatus.deleted,
        );
      }
      final text = ref.watch(extractOwnTextProvider(id));
      final own = text.valueOrNull;
      if (own == null) {
        return ExtractSection(
          documentId: id,
          title: found.title,
          status: text.isLoading || text.hasError
              ? (text.hasError
                    ? ExtractSectionStatus.noText
                    : ExtractSectionStatus.loading)
              : ExtractSectionStatus.noText,
        );
      }
      final study = ref.watch(documentStudyProvider(own.key)).valueOrNull;
      final blocks = key.kind == StudyCreationKind.fullText
          ? ref.watch(extractTextBlocksProvider(id)).valueOrNull
          : study == null
          ? null
          : extractSentenceBlocks(
              own.content,
              study,
              extractNeeds(key.kind),
              markdown: own.markdown,
            );
      if (study == null || blocks == null) {
        return ExtractSection(
          documentId: id,
          title: found.title,
          status: ExtractSectionStatus.loading,
          own: own,
        );
      }
      return ExtractSection(
        documentId: id,
        title: found.title,
        status: ExtractSectionStatus.ready,
        own: own,
        study: study,
        blocks: blocks,
        keywordsShown: ref.watch(processedKeywordsShownProvider(id)),
        missing: study.of(extractNeeds(key.kind)).isEmpty,
      );
    });

/// Con qué id conoce el lector en voz alta a la extracción [creationId]: su
/// propio documento, con lo que este visor muestra y en su orden.
String extractReadableId(String creationId) => 'extract:$creationId';

/// Con qué clave se resalta el título de un documento mientras se lo dice:
/// con varios documentos, cada apartado empieza diciendo de cuál es.
String extractTitleKey(String documentId) => 'extract-title:$documentId';

/// Lo que se escucha de una extracción (F43, paso 7, M8): lo mismo que se ve,
/// en el mismo orden, con las posiciones del texto propio de cada documento
/// —el amarillo cae en su lugar—. El texto completo, entero; el resumen y la
/// síntesis, sus oraciones (`studyReadScopesProvider`, la misma cuenta que
/// la tarjeta de estudiar). Con varios documentos, antes de cada uno se dice
/// su título.
///
/// `null` mientras falta algo por leer —un libro se parte en otro hilo—;
/// vacía si no hay nada que escuchar.
final extractSegmentsProvider = Provider.autoDispose
    .family<List<ReadableSegment>?, String>((ref, creationId) {
      final creation = ref.watch(studyCreationProvider(creationId)).valueOrNull;
      if (creation == null || !creation.kind.isLiveView) return null;
      final several = creation.sourceIds.length > 1;
      final segments = <ReadableSegment>[];
      for (final id in creation.sourceIds) {
        final section = ref.watch(
          extractSectionProvider((kind: creation.kind, documentId: id)),
        );
        if (section.status == ExtractSectionStatus.loading) return null;
        final own = section.own;
        if (section.status != ExtractSectionStatus.ready || own == null) {
          continue;
        }
        final List<ReadableSegment> read;
        if (creation.kind == StudyCreationKind.fullText) {
          final whole = ref.watch(
            readableTextProvider((
              id: extractReadableId(creation.id),
              title: section.title,
              sourceKey: own.key,
              content: own.content,
              markdown: own.markdown,
            )),
          );
          if (whole == null) return null;
          read = whole.segments;
        } else {
          final scopes = ref.watch(studyReadScopesProvider(own.asStudyText));
          read =
              scopes[creation.kind == StudyCreationKind.summary
                  ? ReadScope.summary
                  : ReadScope.synthesis] ??
              const [];
        }
        if (read.isEmpty) continue;
        if (several && section.title.trim().isNotEmpty) {
          segments.add(
            ReadableSegment(
              sourceKey: extractTitleKey(id),
              start: 0,
              end: section.title.length,
              spoken: section.title.trim(),
            ),
          );
        }
        segments.addAll(read);
      }
      return List.unmodifiable(segments);
    });
