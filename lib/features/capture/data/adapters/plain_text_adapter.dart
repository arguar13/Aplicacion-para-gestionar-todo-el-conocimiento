import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/capture/data/adapters/provisional_titles.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';

/// Texto escrito o pegado por el usuario.
///
/// Es el último de la lista y acepta cualquier cosa: lo que ningún otro
/// adaptador reconozca termina acá, guardado tal cual. Alguien que pega algo
/// inesperado prefiere tenerlo guardado a perderlo porque el programa no supo
/// clasificarlo.
///
/// Queda [ProcessingState.ready] de entrada: no hay nada que traer ni que
/// convertir, el contenido ya está completo en el momento de guardarlo.
class PlainTextAdapter implements SourceAdapter {
  const PlainTextAdapter({required IdGenerator ids, required Clock clock})
    : _ids = ids,
      _clock = clock;

  final IdGenerator _ids;
  final Clock _clock;

  @override
  SourceKind get producesKind => SourceKind.manualNote;

  @override
  bool canHandle(CaptureRequest request) => true;

  @override
  Future<KnowledgeItem> adapt(CaptureRequest request) async {
    final now = _clock();
    final itemId = _ids.next();
    final content = request.trimmedInput;

    return KnowledgeItem(
      id: itemId,
      title: request.title?.trim().isNotEmpty ?? false
          ? request.title!.trim()
          : titleFromText(content),
      notes: request.note,
      source: Source(
        id: _ids.next(),
        kind: SourceKind.manualNote,
        capturedAt: now,
        // Sin enlace de origen, y no es un dato faltante: el origen es la
        // persona que lo escribió.
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        Rendition.text(
          id: _ids.next(),
          itemId: itemId,
          kind: RenditionKind.plainText,
          content: content,
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
  }
}
