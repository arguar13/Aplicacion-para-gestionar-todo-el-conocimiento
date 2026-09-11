import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/capture/data/adapters/provisional_titles.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';

/// Cualquier dirección web que no haya reconocido un adaptador más
/// específico.
///
/// Guarda el enlace y un título deducido de la propia dirección, y deja el
/// elemento en [ProcessingState.pending]: traer el artículo y archivar la
/// página es trabajo de la etapa de transformación, que puede tardar y puede
/// fallar.
///
/// Esa separación es lo que hace que capturar sea instantáneo y funcione sin
/// conexión. Pegar un enlace en el subte tiene que guardar algo; lo que falta
/// llega cuando haya red.
class WebLinkAdapter implements SourceAdapter {
  const WebLinkAdapter({required IdGenerator ids, required Clock clock})
    : _ids = ids,
      _clock = clock;

  final IdGenerator _ids;
  final Clock _clock;

  @override
  SourceKind get producesKind => SourceKind.webPage;

  @override
  bool canHandle(CaptureRequest request) => request.asUrl != null;

  @override
  Future<KnowledgeItem> adapt(CaptureRequest request) async {
    final now = _clock();
    final url = request.asUrl!;

    return KnowledgeItem(
      id: _ids.next(),
      title: request.title?.trim().isNotEmpty ?? false
          ? request.title!.trim()
          : titleFromUrl(url),
      subtitle: url.host,
      notes: request.note,
      source: Source(
        id: _ids.next(),
        kind: SourceKind.webPage,
        capturedAt: now,
        url: url.toString(),
      ),
      processingState: ProcessingState.pending,
      createdAt: now,
      updatedAt: now,
      // Sin contenido todavía: lo trae la etapa de transformación.
    );
  }
}
