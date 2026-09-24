import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';

/// Vincula un archivo a una fuente que ya existe —una `SourceKind.reference`
/// creada al importar, D14— y la promueve: pasa a ser `document` (o lo que
/// corresponda según [CapturedFile.format]) y sigue el camino de siempre,
/// sin perder lo que ya tenía, tal como dice el propio doc comment de
/// `SourceKind.reference`.
///
/// No encola el procesamiento del archivo: eso es de la capa de
/// presentación —`ProcessingQueueNotifier`, el mismo camino que usa
/// `CaptureNotifier` al capturar un archivo de cero—, y esta clase vive en
/// el dominio, sin depender de un provider.
class AttachReferenceFileUseCase {
  AttachReferenceFileUseCase({
    required LibraryRepository library,
    required FileStore files,
  }) : _library = library,
       _files = files;

  final LibraryRepository _library;
  final FileStore _files;

  Future<Either<Failure, KnowledgeItem>> call(
    String itemId,
    CapturedFile file,
  ) async {
    final found = await _library.findById(itemId);
    final failure = found.getLeft().toNullable();
    if (failure != null) return left(failure);

    final current = found.getRight().toNullable();
    if (current == null) {
      return left(
        const Failure.unexpected(
          message: 'El elemento ya no existe: no hay a qué adjuntarle nada.',
        ),
      );
    }

    // Se copia primero y se guarda después —mismo orden que `FileAdapter`—:
    // si la copia falla, el elemento sigue como estaba, en vez de quedar
    // apuntando a un archivo que no está.
    final storedPath = await _files.save(
      bytes: file.bytes,
      suggestedName: file.name,
      id: current.id,
    );

    final promoted = current.copyWith(
      source: current.source.copyWith(
        kind: file.format.sourceKind,
        originalFilePath: storedPath,
      ),
      processingState: ProcessingState.pending,
    );

    return _library.save(promoted);
  }
}
