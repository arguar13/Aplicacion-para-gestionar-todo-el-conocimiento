import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/index/domain/repositories/index_document_access.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/domain/services/file_viewer_resolver.dart';

/// [IndexDocumentAccess] sobre Procesado: el documento, su copia del original
/// y su texto propio, por los mismos caminos que el resto de la app —el texto,
/// como lo arma `studyTextOf`, el único lugar que dice cómo se pegan sus
/// páginas—.
///
/// **La fuente en la Biblioteca** (F46, paso 5c). Qué original tiene se sabe
/// como lo sabe el detalle de la Biblioteca: con el mismo [FileViewerResolver]
/// que elige su visor. Así «Abrir en el original» ofrece abrir en un lugar
/// exactamente lo que el visor de la Biblioteca sabe abrir en un lugar.
class ProcessedIndexDocumentAccess implements IndexDocumentAccess {
  const ProcessedIndexDocumentAccess(
    this._processed, {
    required LibraryRepository library,
    required FileViewerResolver viewers,
  }) : _library = library,
       _viewers = viewers;

  final ProcessedRepository _processed;
  final LibraryRepository _library;
  final FileViewerResolver _viewers;

  @override
  Future<IndexDocumentFacts?> factsOf(String documentId) async {
    final document = await _processed.watchDocument(documentId).first;
    if (document == null) return null;
    final original = await _processed.watchOriginal(documentId).first;
    return (
      title: document.title,
      original: switch (original?.kind) {
        null => null,
        RenditionKind.pdf => IndexOriginalKind.pdf,
        RenditionKind.html => IndexOriginalKind.webPage,
        _ => IndexOriginalKind.other,
      },
      source: await _sourceOf(document.source),
    );
  }

  /// La fuente [link] en la Biblioteca y qué original tiene, o `null` si ya
  /// no está. En la papelera no se resuelve su visor: no se abre.
  Future<IndexLibrarySource?> _sourceOf(ProcessedSourceLink? link) async {
    if (link == null) return null;
    if (link.inTrash) {
      return (itemId: link.itemId, original: null, inTrash: true);
    }
    final item = await _library.watchById(link.itemId).first;
    if (item == null) return null;
    final original = switch (await _viewers.resolve(item)) {
      PdfResolvedViewer() => IndexOriginalKind.pdf,
      WebPageResolvedViewer() => IndexOriginalKind.webPage,
      // Un Word, un EPUB o un texto con su texto para estudiar: el mismo
      // lector del original, desde el comienzo.
      TextResolvedViewer(study: _?) => IndexOriginalKind.other,
      // Un audio, un video, una foto, un YouTube, un texto suelto: su ficha.
      _ => null,
    };
    return (itemId: item.id, original: original, inTrash: false);
  }

  @override
  Future<IndexDocumentText?> textOf(String documentId) async =>
      (await _processed.studyTextOf(documentId)).match(
        (_) => null,
        (text) => text == null
            ? null
            : (content: text.content, markdown: text.markdown),
      );
}
