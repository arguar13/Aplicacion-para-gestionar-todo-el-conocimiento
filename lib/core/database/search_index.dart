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

/// Recalcula el cuerpo buscable de un elemento juntando el texto de todas sus
/// formas.
///
/// Se repite dentro de varios triggers en vez de vivir en una función porque
/// SQLite no tiene funciones definidas por el usuario en SQL puro. Es la única
/// duplicación del archivo y está aislada acá para que cambiarla sea cambiar
/// un solo lugar.
const _bodyOf = '''
(SELECT COALESCE(GROUP_CONCAT(content, char(10)), '')
   FROM renditions
  WHERE item_id = %ID% AND content IS NOT NULL)''';

String _body(String idExpression) => _bodyOf.replaceAll('%ID%', idExpression);

/// Triggers que mantienen el índice al día.
///
/// Cubren las dos tablas que aportan texto:
///
/// - `items` da título y subtítulo, y marca el alta y la baja de la fila del
///   índice.
/// - `renditions` da el cuerpo. Cada vez que se agrega, cambia o borra una
///   forma, se recalcula el texto del elemento al que pertenece.
///
/// El caso de borrado de una rendition merece atención: el trigger usa
/// `OLD.item_id`, y si el borrado vino en cascada porque se borró el elemento
/// entero, la fila del índice ya no existe y el `UPDATE` simplemente no
/// afecta a nada. Es correcto y no hace falta ordenarlo de otra manera.
final searchTriggers = <String>[
  '''
CREATE TRIGGER IF NOT EXISTS items_search_ai AFTER INSERT ON items BEGIN
  INSERT INTO item_search (item_id, title, subtitle, body)
  VALUES (NEW.id, NEW.title, COALESCE(NEW.subtitle, ''), ${_body('NEW.id')});
END''',

  '''
CREATE TRIGGER IF NOT EXISTS items_search_au AFTER UPDATE ON items BEGIN
  UPDATE item_search
     SET title = NEW.title,
         subtitle = COALESCE(NEW.subtitle, '')
   WHERE item_id = NEW.id;
END''',

  '''
CREATE TRIGGER IF NOT EXISTS items_search_ad AFTER DELETE ON items BEGIN
  DELETE FROM item_search WHERE item_id = OLD.id;
END''',

  '''
CREATE TRIGGER IF NOT EXISTS renditions_search_ai AFTER INSERT ON renditions BEGIN
  UPDATE item_search SET body = ${_body('NEW.item_id')}
   WHERE item_id = NEW.item_id;
END''',

  '''
CREATE TRIGGER IF NOT EXISTS renditions_search_au AFTER UPDATE ON renditions BEGIN
  UPDATE item_search SET body = ${_body('NEW.item_id')}
   WHERE item_id = NEW.item_id;
END''',

  '''
CREATE TRIGGER IF NOT EXISTS renditions_search_ad AFTER DELETE ON renditions BEGIN
  UPDATE item_search SET body = ${_body('OLD.item_id')}
   WHERE item_id = OLD.item_id;
END''',
];

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
String buildSearchQuery(String rawInput) {
  final terms = rawInput
      .split(RegExp(r'\s+'))
      .map((term) => term.trim())
      // Las comillas dobles son lo único que puede romper un literal entre
      // comillas; en FTS5 se escapan duplicándolas.
      .map((term) => term.replaceAll('"', '""'))
      .where((term) => term.isNotEmpty)
      .toList();

  if (terms.isEmpty) return '';

  // Se unen con AND implícito (el comportamiento por defecto de FTS5): quien
  // escribe dos palabras espera lo que tenga las dos, no lo que tenga
  // cualquiera de ellas.
  return terms.map((term) => '"$term"*').join(' ');
}
