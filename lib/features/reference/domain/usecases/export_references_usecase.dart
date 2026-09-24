import 'package:sinapsis/features/citations/domain/repositories/bibliography_repository.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_file_format.dart';
import 'package:sinapsis/features/reference/domain/services/bibtex/bibtex_writer.dart';
import 'package:sinapsis/features/reference/domain/services/citation_source_import_mapping.dart';
import 'package:sinapsis/features/reference/domain/services/ris/ris_writer.dart';

/// Arma un `.bib` o un `.ris` entero con los datos bibliográficos de la
/// tanda de ids que se le pida (F15, D15 —«importar y exportar desde la
/// app»—): las mismas fuentes que una bibliografía citada —
/// `BibliographyRepository.sourcesOf`—, enteras en vez de formateadas en un
/// estilo.
///
/// Sin fuentes que exportar, no hay archivo que armar: `null`, que la
/// pantalla trata igual que «nada que citar» en `exportBibliography`.
class ExportReferencesUseCase {
  ExportReferencesUseCase(this._bibliography);

  final BibliographyRepository _bibliography;

  Future<String?> call(
    Iterable<String> itemIds,
    ReferenceFileFormat format,
  ) async {
    final sources = await _bibliography.sourcesOf(itemIds);
    if (sources.isEmpty) return null;

    final entries = [
      for (final bibliographySource in sources)
        importedReferenceOf(bibliographySource.source),
    ];
    return switch (format) {
      ReferenceFileFormat.bibtex => writeBibtex(entries),
      ReferenceFileFormat.ris => writeRis(entries),
    };
  }
}
