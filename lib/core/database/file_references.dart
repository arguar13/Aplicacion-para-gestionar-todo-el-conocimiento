import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';

/// Si algo de la base todavía usa el archivo guardado en [relativePath]: la
/// fuente de un elemento (su original), un archivo del «Contenido» (F30) o
/// algo que espera en la papelera del contenido (F30, decisión 68).
///
/// El disco no tiene cascadas. El mismo archivo puede estar en dos lugares
/// —el mismo PDF capturado dos veces, un original soltado que la fuente de
/// otro elemento sigue usando— y borrarlo del disco porque UNO dejó de usarlo
/// dejaría al otro apuntando a la nada. Se pregunta acá, y no en cada lugar
/// que borra, para que ninguno se olvide de mirar una de las tres tablas.
///
/// Cuenta también lo de los elementos que están en la papelera: algo que se
/// puede restaurar todavía lo usa.
Future<bool> isFileReferenced(AppDatabase db, String relativePath) async {
  final row = await db
      .customSelect(
        '''
        SELECT EXISTS (SELECT 1 FROM source WHERE original_blob_path = ?1)
            OR EXISTS (SELECT 1 FROM renditions WHERE relative_path = ?1)
            OR EXISTS (SELECT 1 FROM content_trash WHERE relative_path = ?1)
            AS used''',
        variables: [Variable.withString(relativePath)],
        readsFrom: {db.knowledgeSources, db.renditions, db.trashedContents},
      )
      .getSingle();
  return row.read<bool>('used');
}
