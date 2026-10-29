/// Qué archivos son de una creación de «Lo creado» (F43, decisión H): una
/// sola regla para quien los borra (`CreationIllustrationStore`), quien barre
/// lo que ya no se usa y la unión de bóvedas, que copia los que el contenido
/// nombra. Están juntas, en Dart y en SQL, para que no puedan discrepar
/// (`creation_files_test.dart` las corre con los mismos casos).
library;

import 'package:sinapsis/features/vault/data/services/backup_layout.dart';

/// La subcarpeta de las ilustraciones con IA, dentro de la de su creación:
/// `originales/<creación>/ilustraciones/`.
const kCreationIllustrationsFolder = 'ilustraciones';

/// Si [path] es un archivo de la creación [creationId]: de su carpeta
/// (`originales/<su id>/…`, comparando el tramo entero con su `/`: la de `c1`
/// no acepta `originales/c10/…`), sin `..` ni `\`.
///
/// El contenido de una creación puede llegar de otra bóveda y es un JSON
/// cualquiera: por lo que diga, nunca se borra ni se copia el archivo de otra
/// creación ni el original de un documento. Un id que no es un solo tramo
/// (vacío, «.», con `/`) no es dueño de nada.
bool isCreationFile(String creationId, String path) {
  if (creationId.isEmpty || creationId == '.' || creationId.contains('/')) {
    return false;
  }
  final own = '$kBackupOriginalsFolder/$creationId/';
  return path.startsWith(own) &&
      path.length > own.length &&
      !path.contains('..') &&
      !path.contains(r'\');
}

/// Los archivos que usan las creaciones de [schema] (`main` o la copia): las
/// ilustraciones con IA, que se guardan como cualquier original —en
/// `originales/<creación>/…`— y se nombran en el contenido con
/// `illustration_ref`, a cualquier profundidad (los bloques de una
/// infografía, las diapositivas de un mazo, las tarjetas). `json_tree` abre
/// el JSON sin traerlo a Dart; uno roto no se abre.
///
/// **Solo cuentan los de la propia creación**, con la regla de
/// [isCreationFile]: una ruta que nombre el archivo de otra creación o el
/// original de un documento no hace copiar nada —esos viajan, si
/// corresponde, con quien de verdad los usa— ni lo salva del barrido.
///
/// Es una consulta con una sola columna, `path`: la unión de bóvedas la junta
/// con las de los originales de los elementos al copiar y al contar en la
/// vista previa. Con [oneCreation], la de una sola, cuyo id va en la única
/// variable (`?`): lo que el barrido no borra.
String studyCreationFilesSql(String schema, {bool oneCreation = false}) {
  const own = "'$kBackupOriginalsFolder/' || c.id || '/'";
  return 'SELECT t.value AS path FROM $schema.study_creations c, '
      'json_tree(CASE WHEN json_valid(c.content_json) '
      "THEN c.content_json ELSE '{}' END) t "
      "WHERE t.key = 'illustration_ref' AND t.type = 'text' "
      "AND c.id NOT IN ('', '.') AND instr(c.id, '/') = 0 "
      'AND substr(t.value, 1, length($own)) = $own '
      'AND length(t.value) > length($own) '
      "AND instr(t.value, '..') = 0 "
      'AND instr(t.value, char(92)) = 0'
      '${oneCreation ? ' AND c.id = ?' : ''}';
}
