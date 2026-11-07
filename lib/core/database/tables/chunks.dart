import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';

/// Un fragmento del texto íntegro de una fuente —indexado, no reducción—.
///
/// Concatenar [content] de todos los chunks de un `itemId`, en orden de
/// [seq], reproduce el texto de la forma principal del elemento carácter a
/// carácter. Ver `ChunkingService`/`chunkingInvariantHolds` en
/// `lib/core/domain/services/chunking_service.dart`.
@DataClassName('ChunkRow')
@TableIndex(name: 'idx_chunks_item_seq', columns: {#itemId, #seq})
@TableIndex(name: 'idx_chunks_item_start_ms', columns: {#itemId, #startMs})
class Chunks extends Table {
  /// La clave de la fila: un entero que SQLite numera y que el índice de texto
  /// (`chunk_search`, FTS5 de contenido externo) usa para volver a la fila.
  ///
  /// Hace falta aparte de [id] por el `rowid` implícito: una tabla con clave
  /// primaria de texto tiene uno, pero SQLite puede renumerarlo en un `VACUUM`
  /// —y `VACUUM INTO`, que usan los respaldos, es un `VACUUM`—, y el índice
  /// quedaría apuntando a filas equivocadas sin que nada lo avise. Un entero
  /// declarado como clave primaria es el propio rowid y nunca se renumera.
  IntColumn get rowKey => integer().autoIncrement()();

  /// La identidad de siempre: la que referencian los embeddings y la que ven
  /// el resto de la app. Única, para que las claves foráneas puedan apuntarle.
  TextColumn get id => text().unique()();
  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();
  IntColumn get seq => integer()();
  TextColumn get content => text()();
  IntColumn get charStart => integer()();
  IntColumn get charEnd => integer()();
  IntColumn get startMs => integer().nullable()();
  IntColumn get endMs => integer().nullable()();
  IntColumn get pageNumber => integer().nullable()();
  TextColumn get headingPath => text().nullable()();

  /// Lo que se BUSCA de [content], cuando no es [content] mismo (F46, paso
  /// 5i): el texto de un chunk en Markdown como se lee, sin sus marcas ni sus
  /// direcciones —un enlace es su texto, una imagen su texto alternativo—;
  /// `null` si es el texto tal cual —un PDF, una transcripción, o un Markdown
  /// sin nada que no se lea—. Ver `chunkSearchSource`.
  ///
  /// Lo indexa `chunk_search` en lugar de [content], y de acá sale el
  /// fragmento de un resultado: buscar «fotosíntesis» no encuentra la palabra
  /// adentro de la dirección de una foto, y el fragmento no muestra
  /// `[](https://…)`. Se calcula en Dart al guardar el chunk —SQLite no sabe
  /// leer Markdown— y se guarda, en vez de calcularse en cada búsqueda: el
  /// índice de contenido externo necesita, para dar de baja una fila, el
  /// mismo texto que indexó, y guardado no depende de que la regla de lectura
  /// siga igual. Quien cambie [content] tiene que recalcularlo; el único que
  /// escribe chunks, `chunkAndPersistSource`, los reemplaza enteros.
  TextColumn get searchText => text().nullable()();

  /// Con qué versión de la regla de lectura se calculó [searchText]
  /// (`kChunkSearchTextRule`), o `null` si nunca se calculó: un chunk de antes
  /// de v52. Lo que tiene una versión vieja o ninguna lo pone al día
  /// `ChunkSearchTextBackfill`, en segundo plano; si la regla cambia, se sube
  /// el número y el relleno rehace lo viejo, sin otra migración.
  IntColumn get searchTextRule => integer().nullable()();

  @override
  List<String> get customConstraints => ['UNIQUE (item_id, seq)'];
}
