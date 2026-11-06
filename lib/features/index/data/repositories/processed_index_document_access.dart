import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/index/domain/repositories/index_document_access.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';

/// [IndexDocumentAccess] sobre Procesado: el documento, su copia del original
/// y su texto propio, por los mismos caminos que el resto de la app —el texto,
/// como lo arma `studyTextOf`, el único lugar que dice cómo se pegan sus
/// páginas—.
class ProcessedIndexDocumentAccess implements IndexDocumentAccess {
  const ProcessedIndexDocumentAccess(this._processed);

  final ProcessedRepository _processed;

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
    );
  }

  @override
  Future<String?> textOf(String documentId) async =>
      (await _processed.studyTextOf(
        documentId,
      )).match((_) => null, (text) => text?.content);
}
