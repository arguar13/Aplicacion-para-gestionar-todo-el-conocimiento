/// Qué elementos son documentos procesados (F41), para las consultas escritas a
/// mano.
///
/// Un documento procesado es un elemento de la bóveda —con su papelera, su
/// copia y su unión de bóvedas—, pero **no es de la Biblioteca**: vive en
/// «Procesado». La Biblioteca es la base de consulta, con las fuentes enteras y
/// las notas de la persona; lo procesado es lo trabajado. Este archivo es el
/// único lugar que dice cómo se reconoce uno: tener su fila en
/// `processed_documents`, buscada por su clave.
library;

/// La condición SQL de que el elemento [itemId] —una columna o expresión, como
/// `item.id`— sea un documento procesado.
String isProcessedSql(String itemId) =>
    'EXISTS (SELECT 1 FROM processed_documents processed '
    'WHERE processed.item_id = $itemId)';

/// La condición SQL de que el elemento [itemId] NO sea un documento procesado:
/// lo que deja afuera la Biblioteca.
String notProcessedSql(String itemId) => 'NOT ${isProcessedSql(itemId)}';
