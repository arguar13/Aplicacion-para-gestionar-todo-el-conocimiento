import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';

/// Lo que el visor necesita de la copia: dónde está su archivo, si sigue ahí,
/// y —si lo elegido se puede marcar— su texto, con la clave de la copia.
typedef ProcessedOriginalView = ({String path, bool exists, StudyText? text});

/// Qué pedirle a [processedOriginalViewProvider]: el documento y con qué texto
/// de la fuente se corresponde ahora la copia (`null` si con ninguno).
typedef ProcessedOriginalViewKey = ({String documentId, String? sourceKey});

/// El archivo de la copia y su texto —el de la fuente con que se corresponde,
/// mientras sea el mismo—. Se rehace solo si cambia con qué texto se
/// corresponde o la copia misma, no con cada parte que se toca: un libro no se
/// vuelve a leer por una oración editada.
///
/// Lo usan el original entero (`ProcessedOriginalScreen`) y el que se ve en el
/// documento (`ProcessedOriginalSection`, F43 paso 15): los dos miran la
/// misma copia, con la misma clave, y lo marcado en uno se ve en el otro.
final processedOriginalViewProvider = FutureProvider.autoDispose
    .family<ProcessedOriginalView, ProcessedOriginalViewKey>((ref, key) async {
      final original = await ref.watch(
        processedOriginalProvider(key.documentId).future,
      );
      if (original == null) {
        throw StateError('El documento ya no tiene la copia del original.');
      }
      final files = ref.watch(fileStoreProvider);
      final exists = await files.exists(original.relativePath);
      final path = await files.resolve(original.relativePath);
      final sourceKey = key.sourceKey;
      final sourceItemId = await ref.watch(
        processedDocumentProvider(
          key.documentId,
        ).selectAsync((document) => document?.summary.sourceItemId),
      );
      if (sourceKey == null || sourceItemId == null) {
        return (path: path, exists: exists, text: null);
      }
      final source = await ref
          .read(processedRepositoryProvider)
          .sourceText(sourceItemId, renditionId: sourceKey);
      final text = source.toNullable();
      return (
        path: path,
        exists: exists,
        text: text == null
            ? null
            : (
                itemId: key.documentId,
                renditionId: processedOriginalStudyKeyFor(key.documentId),
                content: text.text,
                markdown: _isMarkdown(original),
              ),
      );
    });

/// La copia del original de [documentId] lista para mostrar, y cada cambio:
/// primero lo marcado —que dice con qué texto de la fuente se corresponde— y
/// con eso el archivo y su texto. Cargando mientras falte cualquiera de los
/// dos.
AsyncValue<ProcessedOriginalView> watchProcessedOriginalView(
  WidgetRef ref,
  String documentId,
) {
  final marks = ref.watch(processedOriginalMarksProvider(documentId));
  if (!marks.hasValue) {
    return marks.hasError
        ? AsyncError(marks.error!, marks.stackTrace ?? StackTrace.current)
        : const AsyncLoading();
  }
  return ref.watch(
    processedOriginalViewProvider((
      documentId: documentId,
      sourceKey: marks.value?.sourceKey,
    )),
  );
}

/// Si el texto de la copia es Markdown, como lo arma la app al extraerlo: el
/// de una página y el de un Word o un EPUB sí; el de un PDF o un `.txt`, tal
/// cual (ver `extractedTextIsMarkdown`).
bool _isMarkdown(ProcessedOriginal original) => switch (original.kind) {
  RenditionKind.pdf => false,
  RenditionKind.html => true,
  _ => original.mimeType != 'text/plain',
};
