import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter_registry.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';

/// Mete algo en la bóveda.
///
/// Es el único camino de entrada de contenido, y hace tres cosas en orden:
/// comprueba que haya algo que guardar, elige quién sabe reconocerlo y
/// guarda el resultado.
///
/// Que sea el único camino importa: si cada pantalla armara su propio
/// elemento, cada una podría olvidarse de poner la procedencia, o el estado
/// de procesamiento, o de pasar por el guardado atómico. Con un solo paso
/// obligatorio, esas garantías valen para todo lo que entre, venga de donde
/// venga — de un formulario, de contenido compartido desde otra app o de una
/// importación futura.
class CaptureItemUseCase implements UseCase<KnowledgeItem, CaptureRequest> {
  const CaptureItemUseCase({
    required SourceAdapterRegistry registry,
    required LibraryRepository repository,
  }) : _registry = registry,
       _repository = repository;

  final SourceAdapterRegistry _registry;
  final LibraryRepository _repository;

  @override
  Future<Either<Failure, KnowledgeItem>> call(CaptureRequest params) async {
    if (params.trimmedInput.isEmpty) {
      return left(
        const Failure.validation(message: 'No hay nada que guardar.'),
      );
    }

    final adapter = _registry.resolve(params);
    final item = await adapter.adapt(params);

    return _repository.save(item);
  }
}
