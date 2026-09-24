import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/repositories/bibliography_repository.dart';
import 'package:sinapsis/features/citations/domain/services/bibliography_builder.dart';
import 'package:sinapsis/features/citations/domain/services/reference_style.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter_registry.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';

/// Los formatos que saben mostrar una bibliografía al pie (F15, D13): un
/// `.bib` YA ES una referencia, y el texto plano no tiene con qué separar
/// una sección de otra —ver cada `Exporter.export`—.
const _formatsWithBibliography = {
  ExportFormat.markdown,
  ExportFormat.pdf,
  ExportFormat.docx,
};

/// Exporta un elemento en el formato elegido y deja guardarlo donde el
/// usuario quiera.
///
/// No distingue "el usuario canceló el diálogo de guardado" de "se
/// completó": en la web esa distinción ni siquiera existe —ver
/// [FileSaver]—, así que tratar las dos cosas igual, como un éxito sin
/// nada más que informar, es lo único que se comporta igual en todas las
/// plataformas.
///
/// Al exportar una nota, agrega al pie la bibliografía de lo que cita —F15,
/// D13—: las fuentes de las que extrajo un fragmento, las que dice citar y
/// las que enlaza con `[[ ]]` (D10), en el estilo y el idioma por defecto de
/// Ajustes. Una fuente no "cita" nada —no lleva bibliografía propia— y una
/// nota que no cita nada tampoco agrega una sección vacía.
class ExportItemUseCase implements UseCase<Unit, ExportItemParams> {
  const ExportItemUseCase({
    required ExporterRegistry registry,
    required FileSaver saver,
    required BibliographyRepository bibliography,
    required ReferenceStyle citationStyle,
    required CitationLanguage citationLanguage,
  }) : _registry = registry,
       _saver = saver,
       _bibliography = bibliography,
       _citationStyle = citationStyle,
       _citationLanguage = citationLanguage;

  final ExporterRegistry _registry;
  final FileSaver _saver;
  final BibliographyRepository _bibliography;
  final ReferenceStyle _citationStyle;
  final CitationLanguage _citationLanguage;

  @override
  Future<Either<Failure, Unit>> call(ExportItemParams params) async {
    final exporter = _registry.resolve(params.format);

    try {
      final bibliography = await _bibliographyFor(params.item, params.format);
      final bytes = await exporter.export(
        params.item,
        bibliography: bibliography,
      );
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

  Future<Bibliography?> _bibliographyFor(
    KnowledgeItem item,
    ExportFormat format,
  ) async {
    if (item.source.kind != SourceKind.manualNote) return null;
    if (!_formatsWithBibliography.contains(format)) return null;

    final sources = await _bibliography.sourcesCitedBy(item.id);
    if (sources.isEmpty) return null;

    return buildBibliography(
      sources,
      style: _citationStyle,
      language: _citationLanguage,
    );
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
