/// Los triggers que hacen cumplir, EN LA BASE, las reglas de las referencias
/// bibliográficas (F15): solo una fuente tiene referencia y personas, y solo
/// una persona puede ser autor de una obra.
///
/// Están en la base y no solo en el escritor por el mismo motivo que los de la
/// jerarquía del vocabulario (`vocabulary_hierarchy.dart`): no todo lo que
/// escribe estas tablas pasa por él —la fusión de bóvedas copia filas con SQL
/// crudo—, y una regla que solo cumple una parte de los caminos de escritura
/// no es una regla: es una costumbre.
///
/// Cada regla responde por lo suyo. Un elemento o un valor que NO EXISTE no es
/// asunto de estos triggers —lo dice la clave foránea—: por eso lo que no se
/// encuentra se toma como que cumple la regla, y el error que sale es el de la
/// clave y no uno que confunda.
///
/// Van por `customStatement`, como los de la búsqueda y los de la jerarquía,
/// porque drift no modela triggers. Los crea `onCreate` y la migración a v22.
library;

/// Los nombres de los triggers, para poder comprobar que existen.
const referenceTriggerNames = [
  'source_reference_kind_bi',
  'source_reference_kind_bu',
  'source_contributor_rules_bi',
  'source_contributor_rules_bu',
];

/// Una referencia cuelga de una fuente: una nota no tiene editorial ni DOI.
const _referenceKindBody = '''
BEGIN
  SELECT RAISE(ABORT, 'source_reference: solo una fuente tiene referencia')
  WHERE COALESCE((SELECT kind FROM item WHERE id = NEW.item_id), 'source')
        IS NOT 'source';
END''';

const _referenceOnInsert = '''
CREATE TRIGGER IF NOT EXISTS source_reference_kind_bi
BEFORE INSERT ON source_reference
$_referenceKindBody''';

const _referenceOnUpdate = '''
CREATE TRIGGER IF NOT EXISTS source_reference_kind_bu
BEFORE UPDATE OF item_id ON source_reference
$_referenceKindBody''';

/// Las personas de una obra: la obra es una fuente, y el valor es de una
/// categoría de tipo persona. Un valor de «Tema» o de «Región» no es un autor.
const _contributorBody = '''
BEGIN
  SELECT RAISE(ABORT, 'source_contributor: solo una fuente tiene personas')
  WHERE COALESCE((SELECT kind FROM item WHERE id = NEW.item_id), 'source')
        IS NOT 'source';
  SELECT RAISE(ABORT, 'source_contributor: solo las personas son autores')
  WHERE COALESCE(
          (SELECT d.type FROM property_values v
             JOIN property_definitions d ON d.id = v.definition_id
            WHERE v.id = NEW.property_value_id),
          'person') IS NOT 'person';
END''';

const _contributorOnInsert = '''
CREATE TRIGGER IF NOT EXISTS source_contributor_rules_bi
BEFORE INSERT ON source_contributor
$_contributorBody''';

const _contributorOnUpdate = '''
CREATE TRIGGER IF NOT EXISTS source_contributor_rules_bu
BEFORE UPDATE OF item_id, property_value_id ON source_contributor
$_contributorBody''';

/// Todos, en el orden en que se crean.
const referenceTriggers = [
  _referenceOnInsert,
  _referenceOnUpdate,
  _contributorOnInsert,
  _contributorOnUpdate,
];
