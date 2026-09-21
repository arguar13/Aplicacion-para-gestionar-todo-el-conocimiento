import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// De dónde salen las fuentes de una bibliografía (F15): un espacio, una rama
/// del Atlas con sus subtemas, lo que cita una nota, lo que la Biblioteca está
/// mostrando o una selección.
///
/// Lee lo mínimo para citar —título, enlace, autor, fechas y los datos
/// bibliográficos con sus personas—, una fila por fuente y en tandas: no carga
/// el texto, las formas ni los chunks, y nunca trae lo que está en la
/// papelera. Un elemento que no es una fuente —una nota— no entra: no tiene
/// nada que citar.
abstract interface class BibliographyRepository {
  /// Las fuentes de [itemIds], sin repetir y en el orden en que vienen. Las
  /// que no existen, están en la papelera o no son fuentes se dejan afuera.
  Future<List<BibliographySource>> sourcesOf(Iterable<String> itemIds);

  /// Las fuentes que cumplen [query] —lo que la Biblioteca está mostrando—: el
  /// mismo motor de filtros, y por eso la misma respuesta a «qué entra».
  /// Ignora el orden y la paginación: la bibliografía tiene el suyo.
  Future<List<BibliographySource>> sourcesMatching(LibraryQuery query);

  /// Las fuentes de un espacio.
  Future<List<BibliographySource>> sourcesOfSpace(String spaceId);

  /// Las fuentes de una rama del Atlas: las asignadas a [valueId] y a todo lo
  /// que cuelga de él.
  Future<List<BibliographySource>> sourcesOfBranch(String valueId);

  /// Las fuentes que cita la nota [noteId]: aquellas de las que extrajo un
  /// fragmento, las que dice citar y las que enlaza con `[[ ]]`. Un vínculo
  /// «relacionado con» no es una cita.
  Future<List<BibliographySource>> sourcesCitedBy(String noteId);
}
