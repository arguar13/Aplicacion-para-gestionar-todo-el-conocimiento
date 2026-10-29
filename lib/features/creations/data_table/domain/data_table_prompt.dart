/// Lo que se le pide a la IA para una tabla de datos (F43, punto 6 del
/// plan): la tarea, el esquema y lo de cada parte cuando el material va por
/// partes. Breve a propósito: con Gemma, la instrucción y el esquema entran
/// en `kCreationInstructionTokens`.
library;

/// La forma del JSON, dicha para el modelo: lo que lee `StudyTableJson.read`.
const dataTableSchemaPrompt = '''
{"title": "título breve de la tabla",
 "columns": [{"name": "nombre corto de la columna", "type": "text | number | date"}],
 "rows": [["valor de la 1.ª columna", "valor de la 2.ª", "..."]]}
Reglas: entre 2 y 8 columnas; la primera, lo que identifica a cada fila; cada fila es una lista con un valor por columna, en el mismo orden; los valores siempre como texto, cortos, y "" si el material no lo dice (nunca inventes); los números y las fechas, escritos como se escriben en el idioma pedido.''';

/// La tarea de la tabla entera, con unas [rows] filas como mucho y, si la
/// persona dijo qué columnas quiere ([wantsColumns]), esas.
String dataTableTask(int rows, {required bool wantsColumns}) =>
    'armar una tabla de datos con la información del material: cada fila, un '
    'elemento —una persona, un hecho, un concepto, una etapa, un lugar— y '
    'cada columna, un dato de ese elemento; hasta $rows filas'
    '${wantsColumns ? _columnsAsked : _columnsChosen}';

/// La tarea de una parte, cuando el material va por partes: cada una da sus
/// filas, y un último paso las une ([dataTableMergeTask]).
String dataTablePartTask(int rows, {required bool wantsColumns}) =>
    'armar las filas de una tabla de datos con SOLO esta parte del material, '
    'que después se juntan con las de las otras partes; hasta $rows filas'
    '${wantsColumns ? _columnsAsked : _columnsShared}';

/// La tarea de unir las tablas de cada parte en una.
String dataTableMergeTask(int rows, {required bool wantsColumns}) =>
    'unir en una sola tabla las tablas parciales que se te dan —cada una '
    'salió de una parte del material, en orden—: las mismas columnas para '
    'todas, sin filas repetidas (si dos hablan de lo mismo, una sola fila '
    'con los datos de las dos) y sin perder ninguna fila importante; hasta '
    '$rows filas${wantsColumns ? _columnsAsked : ''}';

const _columnsAsked =
    '. Las columnas son las que pidió la persona, con esos nombres y en ese '
    'orden';

const _columnsChosen =
    '. Elegí las columnas que mejor resumen el material para estudiarlo';

const _columnsShared =
    '. Elegí columnas que sirvan para todo el material, no solo para esta '
    'parte';
