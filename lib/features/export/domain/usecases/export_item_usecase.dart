import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter_registry.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';

/// Exporta un elemento en el formato elegido y deja guardarlo donde el
/// usuario quiera.
///
/// No distingue "el usuario canceló el diálogo de guardado" de "se
/// completó": en la web esa distinción ni siquiera existe —ver
/// [FileSaver]—, así que tratar las dos cosas igual, como un éxito sin
/// nada más que informar, es lo único que se comporta igual en todas las
/// plataformas.
class ExportItemUseCase implements UseCase<Unit, ExportItemParams> {
  const ExportItemUseCase({
    required ExporterRegistry registry,
    required FileSaver saver,
  }) : _registry = registry,
       _saver = saver;

  final ExporterRegistry _registry;
  final FileSaver _saver;

  @override
  Future<Either<Failure, Unit>> call(ExportItemParams params) async {
    final exporter = _registry.resolve(params.format);

    try {
      final bytes = await exporter.export(params.item);
      await _saver.saveFile(
        fileName: exporter.suggestedFileName(params.item),
        bytes: bytes,
      );

      return right(unit);
      // El exportador y el selector de guardado pueden fallar por motivos
      // que no tienen un tipo propio: un PDF que no se pudo maquetar, un
      // diálogo del sistema que se cae.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.exportFailed(message: '$e'));
    }
  }
}

@immutable
final class ExportItemParams {
  const ExportItemParams({required this.item, required this.format});

  final KnowledgeItem item;
  final ExportFormat format;

  // Igualdad por valor, igual que en el resto de los params de la app: sin
  // esto, dos instancias con los mismos datos son distintas para `==` y se
  // rompe el emparejamiento por valor de mocktail en los tests.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExportItemParams &&
          other.item == item &&
          other.format == format);

  @override
  int get hashCode => Object.hash(item, format);
}
