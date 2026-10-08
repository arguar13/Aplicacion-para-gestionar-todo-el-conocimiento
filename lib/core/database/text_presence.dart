/// Si un elemento ya tiene texto: lo que decide si una fuente entra a la
/// Bandeja (F30, decisión 68).
///
/// La Bandeja trabaja con texto, no con audios ni videos: lo que se tría es lo
/// que se puede leer. Una fuente entra cuando tiene algún texto que no esté
/// vacío —un audio, cuando ya está su transcripción; una foto, cuando ya se
/// leyó su texto—, y mientras tanto sigue en la Biblioteca, sin aparecer en
/// la Bandeja ni en lo que la cuenta.
///
/// **Cuenta también el texto de su «Contenido»** (F30, decisión 66): una
/// publicación de Instagram sin pie de foto cuyas fotos traen texto, o una
/// página que solo enlaza un PDF, tienen texto que leer y triar aunque el del
/// elemento en sí esté vacío. Lo que se baja de una página es parte de ella
/// —está adentro del mismo elemento—, y dejarla afuera de la Bandeja por no
/// tener cuerpo la escondería justo cuando lo que trae es lo valioso. La
/// tarjeta muestra entonces el texto de ese archivo, y dice de cuál es.
///
/// Un texto en blanco —solo espacios, tabulaciones o saltos de línea— no
/// cuenta: «se intentó y no tenía» (una foto sin letras, un audio en
/// silencio) no es algo que leer. Tampoco una nota de bloques, que es de las
/// notas, no de las fuentes.
///
/// Un único lugar, para que el mazo, la lista de «N pendientes», la insignia
/// de la navegación, el panel de salud y la sección «Bandeja» de los filtros
/// cuenten lo mismo. [itemAlias] es el nombre de la tabla `item` en la
/// consulta.
String hasTextSql(String itemAlias) =>
    '''
EXISTS (SELECT 1 FROM renditions txt
         WHERE txt.item_id = $itemAlias.id
           AND txt.content IS NOT NULL
           AND txt.kind <> 'blocks'
           AND txt.content GLOB '*[^' || char(32, 9, 10, 13) || ']*')''';
