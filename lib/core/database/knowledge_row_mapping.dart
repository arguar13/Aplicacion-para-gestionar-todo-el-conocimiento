import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// De las filas del modelo nuevo (`item`/`source`) a las entidades del
/// dominio: el único lugar que decide cómo se lee una procedencia, para que
/// quien la necesite —la Biblioteca al armar un elemento, la fusión de
/// duplicados al guardar de dónde vino el que se descarta— no repita la regla.

/// La procedencia de un elemento: la de su fila de `source` o, si es una nota,
/// la de una nota escrita a mano —que no tiene fila, ni URL, ni autor—.
///
/// Su id es el del propio elemento: hay una fuente por elemento. Antes de F10
/// la fuente tenía identidad propia y podía compartirla con otros elementos;
/// nada la usaba como tal.
Source sourceFor(KnowledgeEntryRow item, KnowledgeSourceRow? source) {
  if (source == null) {
    return Source(
      id: item.id,
      kind: SourceKind.manualNote,
      capturedAt: item.createdAt,
    );
  }
  return Source(
    id: item.id,
    kind: source.sourceType,
    capturedAt: source.capturedAt,
    url: source.originUrl,
    authorName: source.authorName,
    authorUrl: source.authorUrl,
    publishedAt: source.publishedAt,
    originalFilePath: source.originalBlobPath,
  );
}
