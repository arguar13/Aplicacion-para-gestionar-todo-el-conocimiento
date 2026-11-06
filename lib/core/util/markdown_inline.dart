/// Las construcciones en línea del Markdown de la app, y dónde se puede
/// cortar un texto sin partir ninguna (F46, paso 5b).
///
/// **Un solo lugar dice qué es una construcción.** El mismo patrón lo usa el
/// lector para darles formato (`RenderedMarkdown`, de `markdown_display.dart`)
/// y lo usan los que cortan el texto en páginas o en bloques
/// (`readerPageRanges`, `processedTextPages`) para no cortar adentro de una.
/// Si fueran dos reglas, alcanzaría con que difirieran en un caso para que un
/// corte «seguro» dejara a la vista, otra vez, un `[bacterias` crudo en un
/// bloque y un `purpúreas](https://…)` en el siguiente —que es lo que se vio
/// en el emulador, en Fotosíntesis—.
library;

/// Lo de adentro de los paréntesis de un enlace o de una imagen: la
/// dirección —entre `<…>` si lleva espacios o paréntesis sueltos, o con
/// paréntesis balanceados de un nivel, como `Hip%C3%B3tesis_(m%C3%A9todo)`—
/// y, si lo tiene, su título entre comillas.
const _destination =
    r'(?:<[^<>\n]*>|(?:[^\s()<>]|\([^\s()<>]*\))*)'
    r'(?:[ \t]+"[^"\n]*")?';

/// Las construcciones en línea que entiende el lector, en el orden en que se
/// prueban: cada posición del texto encaja con la primera alternativa que
/// pueda, de izquierda a derecha.
///
/// - El código en línea va primero: lo de adentro es literal, ni un `*` ni un
///   `[` se interpretan.
/// - La imagen y el enlace de Markdown (F30) antes que `[[Título]]`: un
///   `[[1]](…)` —la nota al pie de Wikipedia— es un enlace cuyo texto es
///   "[1]", y `[[Título]]` nunca va seguido de `(`.
/// - `[[Título]]` antes que el énfasis: nunca termina interpretado como dos
///   pares de corchetes sueltos ni con un `*` colado adentro. Un título no
///   lleva corchetes: un "[" suelto del texto seguido de un enlace —"César
///   [[Tito](…), hijo…]"— no puede abrir un `[[…]]` que se cierre en la nota
///   al pie de más adelante y se lleve el párrafo entero.
/// - El HTML en línea que escribe `htmlToMarkdown` donde Markdown no
///   alcanza: `<a href>`, `<img>`, `<sup>` y `<sub>`.
///
/// Las reglas de CommonMark que importan para no comerse texto (F22): el
/// énfasis no empieza ni termina con un espacio —"2 * 3 * 4" no es cursiva—,
/// y el guion bajo no marca nada adentro de una palabra —"var_uno_dos" de
/// una página web o un EPUB se ve tal cual—.
///
/// **Ninguna cruza un salto de renglón.** El lector lo aplica renglón por
/// renglón; acá ninguna alternativa deja pasar un `\n` (donde haría falta un
/// espacio cualquiera, es «un espacio que no sea `\n`»), así que sobre un
/// texto entero encuentra exactamente lo mismo que el lector en cada uno de
/// sus renglones. Es lo que deja buscar desde cualquier punto de un texto
/// largo sin copiar el renglón.
final markdownInlinePattern = RegExp(
  r'(?<code>(?<fence>`+)(?!`)(?<codeText>.+?)(?<!`)\k<fence>(?!`))'
  r'|(?<image>!\[(?<alt>[^\[\]\n]*)\]\('
  '$_destination'
  r'\))'
  r'|(?<mdLink>\[(?<linkText>(?:[^\[\]\n]|\[[^\[\]\n]*\])+)\]\('
  '$_destination'
  r'\))'
  r'|\[\[(?<wiki>[^\[\]\n]+)\]\]'
  r'|(?<htmlLink><a[^\S\n][^>\n]*>)(?<htmlLinkText>.*?)</a[^\S\n]*>'
  r'|(?<htmlImage><img[^\S\n][^>\n]*?/?>)'
  r'|<(?<script>sup|sub)>(?<scriptText>.*?)</\k<script>>'
  r'|\*\*(?<bold>\S(?:.*?\S)?)\*\*'
  r'|\*(?<star>\S(?:.*?\S)?)\*'
  r'|(?<![\p{L}\p{N}])_(?<under>\S(?:.*?\S)?)_(?![\p{L}\p{N}])',
  unicode: true,
);

/// Un tramo `[start, end)` de un texto.
typedef MarkdownSpan = ({int start, int end});

/// La construcción en línea de [text] que [at] parte —que empieza antes de
/// [at] y termina después—, o `null` si cortar en [at] no parte ninguna.
/// Cortar en el borde de una (justo antes o justo después) no la parte.
///
/// Se busca desde [from], que tiene que ser un lugar donde nada está abierto:
/// el comienzo del texto, el de un renglón o un corte anterior que ya pasó
/// por acá. Lee de [from] a [at] y, si [at] cae adentro de una, hasta su
/// final: un corte cuesta lo que mide el tramo, no el texto entero.
MarkdownSpan? markdownInlineAt(String text, int at, {int from = 0}) {
  if (at <= from || at >= text.length) return null;
  for (final match in markdownInlinePattern.allMatches(text, from)) {
    if (match.start >= at) return null;
    if (match.end > at) return (start: match.start, end: match.end);
  }
  return null;
}

/// [at], o el corte más cercano que no parte ninguna construcción en línea
/// de [text] (ver [markdownInlineAt], de donde sale también [from]).
///
/// Si [at] cae adentro de una, se corta justo antes de ella: lo que la
/// precede queda en este tramo y ella entera en el siguiente. Si empieza en
/// [from] —una construcción más larga que el tramo, como un enlace con una
/// dirección de miles de letras—, no hay antes: se corta justo después, y el
/// tramo se pasa del largo pedido lo que haga falta para llevarla entera.
int markdownSafeCut(String text, int at, {int from = 0}) {
  final span = markdownInlineAt(text, at, from: from);
  if (span == null) return at;
  return span.start > from ? span.start : span.end;
}
