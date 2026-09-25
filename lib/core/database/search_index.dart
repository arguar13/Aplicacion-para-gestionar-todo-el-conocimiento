/// El índice de búsqueda de texto completo, en SQL.
///
/// ## Por qué FTS5 y no un `LIKE '%...%'`
///
/// Buscar con `LIKE` obliga a recorrer cada fila y comparar carácter por
/// carácter: con doscientos elementos no se nota, pero con veinte mil
/// transcripciones de una hora cada una, sí. FTS5 mantiene un índice
/// invertido, así que el costo de una búsqueda depende de cuántos resultados
/// hay y no del tamaño de la biblioteca. Además viene incluido en el SQLite
/// de Android y iOS: no cuesta ninguna dependencia extra.
///
/// ## Por qué se sincroniza con triggers y no desde Dart
///
/// Un índice que se actualiza desde el código se desincroniza el día que
/// alguien agrega una forma nueva de escribir en la tabla y se olvida de
/// tocarlo — y el síntoma es el peor posible: la búsqueda no encuentra algo
/// que sí está guardado, en silencio y sin error. Con triggers, cualquier
/// escritura queda cubierta, venga de donde venga; incluso de una consulta
/// hecha a mano.
library;

/// La tabla virtual.
///
/// `item_id` va sin indexar (`UNINDEXED`) porque nadie busca *por* el
/// identificador: solo hace falta para poder volver a la fila real desde un
/// resultado. Indexarlo agrandaría el índice sin que ninguna consulta lo
/// aproveche.
///
/// El tokenizador `unicode61` con `remove_diacritics 2` es lo que hace que
/// buscar "filosofia" encuentre "filosofía" — imprescindible con contenido en
/// español, donde nadie escribe los acentos al buscar.
const createSearchTable = '''
CREATE VIRTUAL TABLE IF NOT EXISTS item_search USING fts5(
  item_id UNINDEXED,
  title,
  subtitle,
  body,
  tokenize = "unicode61 remove_diacritics 2"
)
''';

/// Recalcula el cuerpo buscable de un elemento juntando el texto de sus formas
/// —solo si es una NOTA: una fuente devuelve el texto vacío—.
///
/// Solo las notas, desde F10: el texto de una fuente lo indexa `chunk_search`
/// por chunks —con su minuto o su página—, y guardarlo además acá era el texto
/// entero de cada fuente repetido en el índice. Una nota, en cambio, no se
/// fragmenta ni tiene posición que citar, y su texto es corto. Es nota lo que
/// `kind = 'note'` en `item`: una fuente de tipo `manualNote`, escrita con
/// bloques o como texto.
///
/// Se repite dentro de varios triggers en vez de vivir en una función porque
/// SQLite no tiene funciones definidas por el usuario en SQL puro. Es la única
/// duplicación del archivo y está aislada acá para que cambiarla sea cambiar
/// un solo lugar.
///
/// El alias de adentro (`ni`) NO es `i` a propósito: se usa desde
/// `INSERT ... SELECT ... FROM item i`, y un `i` repetido adentro taparía al de
/// afuera y haría que la condición fuera verdad para cualquier elemento.
const _bodyOf = '''
(SELECT COALESCE(GROUP_CONCAT(r.content, char(10)), '')
   FROM renditions r
  WHERE r.item_id = %ID% AND r.content IS NOT NULL
    AND EXISTS (SELECT 1 FROM item ni
                 WHERE ni.id = %ID% AND ni.kind = 'note'))''';

/// Si el elemento [idExpression] es una nota: la condición de los triggers de
/// las formas, para no reescribir la fila de una fuente por cada forma que se
/// guarda.
String _isNote(String idExpression) => '''
EXISTS (SELECT 1 FROM item ni
         WHERE ni.id = $idExpression AND ni.kind = 'note')''';

String _body(String idExpression) => _bodyOf.replaceAll('%ID%', idExpression);

/// Triggers que mantienen el índice al día.
///
/// Cubren las dos tablas que aportan texto:
///
/// - `item` da título y subtítulo, y marca el alta y la baja de la fila del
///   índice.
/// - `renditions` da el cuerpo. Cada vez que se agrega, cambia o borra una
///   forma de una NOTA, se recalcula el texto del elemento al que pertenece;
///   las de una fuente no lo tocan, así que guardar una fuente no reescribe su
///   fila del índice por cada forma.
///
/// El caso de borrado de una rendition merece atención: el trigger usa
/// `OLD.item_id`, y si el borrado vino en cascada porque se borró el elemento
/// entero, la fila del índice ya no existe y el `UPDATE` simplemente no
/// afecta a nada. Es correcto y no hace falta ordenarlo de otra manera.
final searchTriggers = <String>[
  '''
CREATE TRIGGER IF NOT EXISTS entry_search_ai AFTER INSERT ON item BEGIN
  INSERT INTO item_search (item_id, title, subtitle, body)
  VALUES (NEW.id, NEW.title, COALESCE(NEW.subtitle, ''), ${_body('NEW.id')});
END''',

  '''
CREATE TRIGGER IF NOT EXISTS entry_search_au
AFTER UPDATE OF title, subtitle ON item BEGIN
  UPDATE item_search
     SET title = NEW.title,
         subtitle = COALESCE(NEW.subtitle, '')
   WHERE item_id = NEW.id;
END''',

  '''
CREATE TRIGGER IF NOT EXISTS entry_search_ad AFTER DELETE ON item BEGIN
  DELETE FROM item_search WHERE item_id = OLD.id;
END''',

  '''
CREATE TRIGGER IF NOT EXISTS renditions_search_ai AFTER INSERT ON renditions
WHEN ${_isNote('NEW.item_id')} BEGIN
  UPDATE item_search SET body = ${_body('NEW.item_id')}
   WHERE item_id = NEW.item_id;
END''',

  '''
CREATE TRIGGER IF NOT EXISTS renditions_search_au AFTER UPDATE ON renditions
WHEN ${_isNote('NEW.item_id')} BEGIN
  UPDATE item_search SET body = ${_body('NEW.item_id')}
   WHERE item_id = NEW.item_id;
END''',

  '''
CREATE TRIGGER IF NOT EXISTS renditions_search_ad AFTER DELETE ON renditions
WHEN ${_isNote('OLD.item_id')} BEGIN
  UPDATE item_search SET body = ${_body('OLD.item_id')}
   WHERE item_id = OLD.item_id;
END''',
];

/// Los triggers de [searchTriggers], por nombre: las migraciones los quitan
/// antes de rehacer el índice.
const searchTriggerNames = <String>[
  'entry_search_ai',
  'entry_search_au',
  'entry_search_ad',
  'renditions_search_ai',
  'renditions_search_au',
  'renditions_search_ad',
];

/// Los triggers de `item_search` de antes de v18, colgados de `items`: el
/// paso v18 los quita —`items` deja de escribirse— junto con los de arriba.
const legacySearchTriggerNames = <String>[
  'items_search_ai',
  'items_search_au',
  'items_search_ad',
];

/// Puebla `item_search` desde cero, como lo habrían hecho los triggers fila por
/// fila: título, subtítulo y el texto de las notas de cada elemento.
final populateItemSearch =
    '''
INSERT INTO item_search (item_id, title, subtitle, body)
SELECT i.id, i.title, COALESCE(i.subtitle, ''), ${_body('i.id')}
  FROM item i''';

/// Como [populateItemSearch], pero solo para los elementos cuyo id está en
/// [placeholders] —una lista de `?` ya armada por quien llama, del mismo
/// largo que los valores que le pase como variables ligadas—, en vez de la
/// bóveda entera: lo que usa `withSuspendedSearchIndexes` (F19, 19.4) para
/// repoblar un lote chico sin rehacer la tabla completa.
String populateItemSearchScoped(String placeholders) =>
    '''
INSERT INTO item_search (item_id, title, subtitle, body)
SELECT i.id, i.title, COALESCE(i.subtitle, ''), ${_body('i.id')}
  FROM item i WHERE i.id IN ($placeholders)''';

/// El índice de texto de los CHUNKS de las fuentes (F10).
///
/// Es un FTS5 de contenido externo: guarda solo el índice invertido y vuelve a
/// `chunks` por su clave entera para leer el texto cuando hace falta —para
/// mostrar un fragmento, por ejemplo—. No es una segunda copia del texto: la
/// que ocupaba `item_search.body`, con el texto entero de cada elemento, era
/// exactamente lo que F10 tenía que quitar.
///
/// Buscar por chunks y no por elemento entero es lo que permite decir DÓNDE
/// está lo que se encontró: el minuto de una transcripción, la página de un
/// documento.
///
/// `content_rowid` es `row_key`, el entero que la propia tabla declara como
/// clave primaria: ver `Chunks.rowKey` para por qué no puede ser el `rowid`
/// implícito.
const createChunkSearchTable = '''
CREATE VIRTUAL TABLE IF NOT EXISTS chunk_search USING fts5(
  content,
  content = 'chunks',
  content_rowid = 'row_key',
  tokenize = "unicode61 remove_diacritics 2"
)''';

/// Cuántos chunks contienen cada palabra, según el propio índice.
///
/// Una vista sobre `chunk_search`, sin datos propios. Sirve para saber ANTES
/// de buscar si una palabra está en todas partes: ordenar por relevancia
/// cuesta lo que cuestan las coincidencias, y una palabra que aparece en dos
/// tercios de los chunks no distingue nada.
const createChunkVocabTable = '''
CREATE VIRTUAL TABLE IF NOT EXISTS chunk_vocab USING fts5vocab(chunk_search, row)''';

/// Triggers que mantienen `chunk_search` al día: cualquier escritura sobre
/// `chunks` queda cubierta, venga de donde venga —incluido el borrado en
/// cascada cuando se borra un elemento—, por el mismo motivo que los de
/// `item_search`.
///
/// En una tabla de contenido externo, borrar o cambiar una fila obliga a
/// decirle al índice QUÉ texto tenía: por eso los triggers de baja y de cambio
/// pasan `OLD.content`.
final chunkSearchTriggers = <String>[
  '''
CREATE TRIGGER IF NOT EXISTS chunks_search_ai AFTER INSERT ON chunks BEGIN
  INSERT INTO chunk_search (rowid, content) VALUES (NEW.row_key, NEW.content);
END''',

  '''
CREATE TRIGGER IF NOT EXISTS chunks_search_ad AFTER DELETE ON chunks BEGIN
  INSERT INTO chunk_search (chunk_search, rowid, content)
  VALUES ('delete', OLD.row_key, OLD.content);
END''',

  '''
CREATE TRIGGER IF NOT EXISTS chunks_search_au AFTER UPDATE OF content ON chunks BEGIN
  INSERT INTO chunk_search (chunk_search, rowid, content)
  VALUES ('delete', OLD.row_key, OLD.content);
  INSERT INTO chunk_search (rowid, content) VALUES (NEW.row_key, NEW.content);
END''',
];

/// Reconstruye `chunk_search` desde `chunks`. Para la migración, que primero
/// inserta todos los chunks y recién entonces indexa: hacerlo de una vez es
/// mucho más rápido que indexar chunk por chunk.
const rebuildChunkSearch =
    "INSERT INTO chunk_search (chunk_search) VALUES ('rebuild')";

/// Convierte lo que escribió el usuario en una consulta de FTS5.
///
/// Hace falta porque la sintaxis de FTS5 tiene operadores propios (`AND`,
/// `OR`, `NOT`, `NEAR`, comillas, paréntesis, `*`, `:`) y un texto normal
/// puede contenerlos por accidente. Buscar `C++` o `¿qué?` o una frase con
/// comillas produciría un error de sintaxis en vez de un resultado — y al
/// usuario, que no tiene por qué saber que existe FTS5, le aparecería un
/// error inexplicable por escribir su pregunta.
///
/// La solución es tratar cada palabra como un literal entre comillas —donde
/// ningún carácter tiene significado especial— y agregarle `*` al final para
/// que la búsqueda encuentre resultados mientras se escribe: "filos" ya
/// encuentra "filosofía", sin esperar a terminar la palabra.
String buildSearchQuery(String rawInput) =>
    searchTerms(rawInput).map((t) => t.match).join(' ');

/// Las palabras que escribió el usuario, cada una con la forma en que se le
/// pasa a FTS5 —entre comillas y con prefijo—.
///
/// Se necesitan por separado, no solo unidas por [buildSearchQuery]: la
/// búsqueda por chunks también pregunta por cada palabra sola, para encontrar
/// los elementos que las tienen todas aunque estén en fragmentos distintos.
List<({String term, String match})> searchTerms(String rawInput) {
  final terms = <({String term, String match})>[];
  for (final piece in rawInput.split(RegExp(r'\s+'))) {
    final term = piece.trim();
    if (term.isEmpty) continue;
    // Las comillas dobles son lo único que puede romper un literal entre
    // comillas; en FTS5 se escapan duplicándolas.
    final escaped = term.replaceAll('"', '""');
    terms.add((term: term, match: '"$escaped"*'));
  }
  // Se unen con AND implícito (el comportamiento por defecto de FTS5): quien
  // escribe dos palabras espera lo que tenga las dos, no lo que tenga
  // cualquiera de ellas.
  return terms;
}
