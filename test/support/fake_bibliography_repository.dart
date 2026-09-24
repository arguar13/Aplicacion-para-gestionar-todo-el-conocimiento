import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/repositories/bibliography_repository.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// Un [BibliographyRepository] de mentira: solo `sourcesCitedBy` devuelve algo
/// configurable —lo único que `ExportItemUseCase` necesita—; los demás
/// métodos lanzan si se llaman por error, para que un test que dependiera de
/// uno de ellos sin querer no pase en silencio.
class FakeBibliographyRepository implements BibliographyRepository {
  FakeBibliographyRepository({this.citedBy = const []});

  /// Lo que devuelve `sourcesCitedBy`, sin importar qué `noteId` se pida.
  List<BibliographySource> citedBy;

  /// Cada `noteId` con el que se llamó a `sourcesCitedBy`, en orden.
  final calls = <String>[];

  @override
  Future<List<BibliographySource>> sourcesCitedBy(String noteId) async {
    calls.add(noteId);
    return citedBy;
  }

  @override
  Future<List<BibliographySource>> sourcesOf(Iterable<String> itemIds) =>
      throw UnimplementedError();

  @override
  Future<List<BibliographySource>> sourcesMatching(LibraryQuery query) =>
      throw UnimplementedError();

  @override
  Future<List<BibliographySource>> sourcesOfSpace(String spaceId) =>
      throw UnimplementedError();

  @override
  Future<List<BibliographySource>> sourcesOfBranch(String valueId) =>
      throw UnimplementedError();
}
