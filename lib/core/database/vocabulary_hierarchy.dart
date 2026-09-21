/// Los triggers que hacen cumplir, EN LA BASE, las reglas de la jerarquía del
/// vocabulario (F13): sin ciclos, el padre en la misma categoría, y solo en
/// las categorías de texto.
///
/// Están en la base y no solo en el repositorio porque no todo lo que escribe
/// `property_values` pasa por él: la fusión de bóvedas copia filas con SQL
/// crudo, y dos dispositivos pueden haber puesto A bajo B y B bajo A. Una
/// regla que solo cumple una parte de los caminos de escritura no es una
/// regla: es una costumbre.
///
/// Van por `customStatement`, como los de la búsqueda, porque drift no modela
/// triggers. Los crea `onCreate` y la migración a v21.
///
/// El tope de profundidad no está acá: es una restricción `CHECK` de la propia
/// columna `depth` —ver `PropertyValues.depth`—.
library;

/// Los nombres de los triggers, para poder comprobar que existen.
const vocabularyHierarchyTriggerNames = [
  'property_values_hierarchy_cycle_bi',
  'property_values_hierarchy_cycle_bu',
  'property_values_hierarchy_scope_bi',
  'property_values_hierarchy_scope_bu',
];

/// Un valor no puede ser su propio padre, ni bajo uno de sus descendientes.
///
/// Recorre hacia ARRIBA desde el padre nuevo: si en su cadena de ancestros
/// aparece el valor que se mueve, el movimiento cierra un ciclo. Son cuatro
/// saltos a lo sumo porque el árbol tiene cinco niveles
/// (`kVocabularyMaxDepth`): se resuelve con uniones y no con una consulta
/// recursiva, que SQLite no deja usar adentro de un trigger.
const _cycleOnInsert = '''
CREATE TRIGGER IF NOT EXISTS property_values_hierarchy_cycle_bi
BEFORE INSERT ON property_values
WHEN NEW.parent_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'property_values: la jerarquía no admite ciclos')
  WHERE NEW.parent_id = NEW.id;
END''';

const _cycleOnUpdate = '''
CREATE TRIGGER IF NOT EXISTS property_values_hierarchy_cycle_bu
BEFORE UPDATE OF parent_id ON property_values
WHEN NEW.parent_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'property_values: la jerarquía no admite ciclos')
  WHERE NEW.parent_id = NEW.id
     OR EXISTS (
       SELECT 1 FROM property_values a1
       LEFT JOIN property_values a2 ON a2.id = a1.parent_id
       LEFT JOIN property_values a3 ON a3.id = a2.parent_id
       LEFT JOIN property_values a4 ON a4.id = a3.parent_id
       WHERE a1.id = NEW.parent_id
         AND (a1.parent_id = NEW.id OR a2.parent_id = NEW.id
              OR a3.parent_id = NEW.id OR a4.parent_id = NEW.id));
END''';

/// El padre es de la MISMA categoría, y la categoría es de texto: «Fecha del
/// hecho» y las de número ya tienen su propio orden.
///
/// Un padre que no existe no es asunto de este trigger —lo dice la clave
/// foránea— y tampoco lo es el que un valor sea su propio padre —lo dice el
/// trigger de ciclos—: cada uno responde por lo suyo.
const _scopeOnInsert = '''
CREATE TRIGGER IF NOT EXISTS property_values_hierarchy_scope_bi
BEFORE INSERT ON property_values
WHEN NEW.parent_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'property_values: el padre es de otra categoría')
  WHERE COALESCE(
          (SELECT definition_id FROM property_values WHERE id = NEW.parent_id),
          NEW.definition_id) IS NOT NEW.definition_id;
  SELECT RAISE(ABORT,
    'property_values: solo las categorías de texto tienen jerarquía')
  WHERE (SELECT type FROM property_definitions WHERE id = NEW.definition_id)
        IS NOT 'text';
END''';

const _scopeOnUpdate = '''
CREATE TRIGGER IF NOT EXISTS property_values_hierarchy_scope_bu
BEFORE UPDATE OF parent_id, definition_id ON property_values
WHEN NEW.parent_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'property_values: el padre es de otra categoría')
  WHERE COALESCE(
          (SELECT definition_id FROM property_values WHERE id = NEW.parent_id),
          NEW.definition_id) IS NOT NEW.definition_id;
  SELECT RAISE(ABORT,
    'property_values: solo las categorías de texto tienen jerarquía')
  WHERE (SELECT type FROM property_definitions WHERE id = NEW.definition_id)
        IS NOT 'text';
END''';

/// Todos, en el orden en que se crean.
const vocabularyHierarchyTriggers = [
  _cycleOnInsert,
  _cycleOnUpdate,
  _scopeOnInsert,
  _scopeOnUpdate,
];
