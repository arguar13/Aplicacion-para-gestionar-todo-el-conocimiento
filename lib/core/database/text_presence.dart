/// Si un elemento ya tiene texto: lo que separa, en la Bandeja, lo que ya se
/// puede triar de lo que todavía lo espera (F41, ver `PendingText`).
///
/// Hasta F41 decidía si una fuente entraba a la Bandeja (F30, decisión 68).
/// Ya no: todo lo nuevo de la Biblioteca entra apenas se guarda, y lo que
/// todavía no tiene texto —un audio sin transcribir, una foto sin leer— espera
/// con su tarjeta, con «Descartar» a mano y lo demás apagado hasta que el
/// texto llega. Esto dice cuándo llegó.
///
/// Una fuente tiene texto cuando tiene alguno que no esté vacío —un audio,
/// cuando ya está su transcripción; una foto, cuando ya se leyó su texto—.
///
/// **Cuenta también el texto de su «Contenido»** (F30, decisión 66): una
/// publicación de Instagram sin pie de foto cuyas fotos traen texto, o una
/// página que solo enlaza un PDF, tienen texto que leer y triar aunque el del
/// elemento en sí esté vacío. Lo que se baja de una página es parte de ella
/// —está adentro del mismo elemento—. La tarjeta muestra entonces el texto de
/// ese archivo, y dice de cuál es.
///
/// Un texto en blanco —solo espacios, tabulaciones o saltos de línea— no
/// cuenta: «se intentó y no tenía» (una foto sin letras, un audio en
/// silencio) no es algo que leer. Tampoco una nota de bloques, que es de las
/// notas, no de las fuentes.
///
/// Un único lugar, para que la lista de «N pendientes» y la tarjeta del mazo
/// digan lo mismo. [itemAlias] es el nombre de la tabla `item` en la consulta.
String hasTextSql(String itemAlias) =>
    '''
EXISTS (SELECT 1 FROM renditions txt
         WHERE txt.item_id = $itemAlias.id
           AND txt.content IS NOT NULL
           AND txt.kind <> 'blocks'
           AND txt.content GLOB '*[^' || char(32, 9, 10, 13) || ']*')''';
