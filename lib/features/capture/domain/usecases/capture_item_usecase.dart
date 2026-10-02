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
    Future<int?> Function()? freeBytes,
  }) : _registry = registry,
       _repository = repository,
       _freeBytes = freeBytes;

  final SourceAdapterRegistry _registry;
  final LibraryRepository _repository;

  /// Cuánto espacio libre queda donde se guardan los archivos, o `null` si
  /// no se sabe. Guardar un archivo ya no tiene un tope fijo —se copia por
  /// partes—: el límite real es este (F21).
  final Future<int?> Function()? _freeBytes;

  /// Lo que se deja libre además del archivo: la base, el índice y los
  /// chunks que genera procesarlo también ocupan lugar, y un dispositivo
  /// lleno hasta el último byte deja de funcionar bien.
  static const _spaceMargin = 64 * 1024 * 1024;

  @override
  Future<Either<Failure, KnowledgeItem>> call(CaptureRequest params) async {
    final rejected = _reasonToReject(params) ?? await _lackOfSpace(params);
    if (rejected != null) return left(rejected);

    final adapter = _registry.resolve(params);
    final adapted = await adapter.adapt(params);
    // El tema lo elige quien guarda, no lo deduce ningún adaptador: se pone
    // acá, una sola vez para todos, y va en el mismo `save`.
    final spaceId = params.spaceId;
    final item = spaceId == null ? adapted : adapted.copyWith(spaceId: spaceId);

    return _repository.save(item);
  }

  /// Qué cuenta como "no hay nada que guardar", que depende de qué entró.
  ///
  /// Para un texto es que esté en blanco; para un archivo, que venga vacío
  /// —pasa cuando el sistema entrega una ruta que ya caducó—. Meter las dos
  /// en una sola comprobación sobre el texto haría que **todo** archivo se
  /// rechazara, ya que una captura de archivo no trae texto ninguno.
  Failure? _reasonToReject(CaptureRequest request) => switch (request) {
    TextCapture() when request.trimmedInput.isEmpty => const Failure.validation(
      message: 'No hay nada que guardar.',
    ),
    FileCapture(:final file) when file.sizeInBytes == 0 =>
      const Failure.validation(message: 'El archivo llegó vacío.'),
    _ => null,
  };

  /// Si el archivo no entra en el espacio libre del dispositivo. Se avisa
  /// antes de empezar a copiar: descubrirlo a mitad de copiar un video de
  /// varios GB sería hacer esperar para nada.
  Future<Failure?> _lackOfSpace(CaptureRequest request) async {
    final file = request.asFile;
    final probe = _freeBytes;
    if (file == null || probe == null) return null;

    final free = await probe();
    if (free == null || file.sizeInBytes + _spaceMargin <= free) return null;
    return Failure.notEnoughSpace(
      message:
          'El archivo pesa ${file.sizeInBytes} bytes y quedan $free libres.',
      neededBytes: file.sizeInBytes,
      freeBytes: free,
    );
  }
}
