import 'package:sinapsis/core/domain/entities/imported_reference.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';

/// Lleva lo que hace falta para citar una fuente —F15, `CitationSource`— a lo
/// que un archivo `.bib` o `.ris` necesita para escribirla —F15,
/// `ImportedReference`—: el mismo dato, con otro nombre para otro propósito.
/// `authorName`, `capturedAt` y `kind` se quedan afuera: son para deducir un
/// tipo o un autor en una cita, no campos de un archivo bibliográfico.
ImportedReference importedReferenceOf(CitationSource source) =>
    ImportedReference(
      title: source.title,
      url: source.url,
      publishedAt: source.date.date,
      publicationPrecision: source.date.precision,
      reference: source.reference,
    );
