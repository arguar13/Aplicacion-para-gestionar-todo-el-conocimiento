import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Convierte el Markdown crudo de una rendition en algo que se ve con
/// formato de verdad —títulos, **negrita**, *cursiva*, viñetas— sin perder
/// la correspondencia con el contenido guardado.
///
/// Existe porque el resaltado de texto (`HighlightableText`) guarda cada
/// marca como un rango de caracteres **del contenido crudo**: si el texto
/// que se ve en pantalla ocultara los `**` y los `#` sin más, esas
/// posiciones dejarían de coincidir con lo que el usuario ve y seleccionó,
/// y un resaltado viejo terminaría marcando el fragmento equivocado —o
/// reventando por quedar fuera de rango—. [RenderedMarkdown] resuelve esto
/// llevando la cuenta de qué rango del texto renderizado corresponde a qué
/// rango del texto crudo, en las dos direcciones: [renderToRaw] para
/// guardar un resaltado nuevo a partir de una selección sobre lo que se ve,
/// y [rawToRender] para dibujar uno ya guardado en el lugar correcto del
/// texto con formato.
///
/// Deliberadamente no es un parser de Markdown completo — CommonMark tiene
/// tablas, bloques de código, listas anidadas, y esta app no necesita nada
/// de eso: ni el editor de bloques, ni `WebArticleTransformer`, ni los
/// parsers de documentos generan ese tipo de estructura. Lo que sí generan
/// —títulos con `#`, **negrita**, *cursiva*, viñetas con `-`/`*`, citas con
/// `>`, y el separador `---` que `PdfParser` pone entre páginas— es
/// exactamente lo que este renderer entiende.
///
/// También lo que `htmlToMarkdown` escribe al guardar una página web o un
/// EPUB (F30): un enlace `[texto](dirección)` se lee como su texto, una
/// imagen `![alt](dirección)` como su texto alternativo —en cursiva, y nada
/// si no tiene—, el código en línea sin sus comillas invertidas, y el HTML
/// en línea que usa donde Markdown no alcanza (`<a href>`, `<img>`,
/// `<sup>`, `<sub>`) sin sus etiquetas. Antes se veía todo crudo:
/// `[![](//upload.wikimedia.org/…)](/wiki/…)` en medio del artículo. Lo que
/// se ve es siempre un pedazo del texto crudo, así que los resaltados siguen
/// cayendo donde corresponde.
///
/// `[[Título]]` es la excepción: nadie la genera al importar contenido, solo
/// el editor de bloques, cuando alguien enlaza una nota con otra sin salir
/// del texto que está escribiendo —ver `BlockEditorScreen._insertLink`—.
/// Acá se reconoce igual que negrita o cursiva —el marcado desaparece, queda
/// el título tal cual—, pero con un `TapGestureRecognizer` en vez de un
/// estilo fijo: [buildSpans] recibe `onLinkTap` y lo invoca con el título
/// tocado, dejando que quien lo use decida cómo resolverlo a un elemento de
/// verdad.
class RenderedMarkdown {
  RenderedMarkdown._(this._segments, this.displayText);

  factory RenderedMarkdown.parse(String raw) {
    final segments = _parse(raw);
    final buffer = StringBuffer();
    for (final segment in segments) {
      buffer.write(segment.text);
    }
    return RenderedMarkdown._(segments, buffer.toString());
  }

  /// [raw] tal cual, sin interpretar ningún marcado: el texto de un
  /// original que no es Markdown —una transcripción, un PDF, lo reconocido
  /// en una foto— se muestra carácter por carácter (F22). Mismo contrato
  /// que [RenderedMarkdown.parse]: las posiciones son las del contenido.
  factory RenderedMarkdown.plain(String raw) => RenderedMarkdown._([
    if (raw.isNotEmpty)
      _Segment.kept(rawStart: 0, text: raw, style: const _RunStyle()),
  ], raw);

  /// El comienzo de [raw] como se lee, para una vista previa (F30): con
  /// [markdown], sin enlaces ni imágenes con su dirección, sin `**` ni `#`;
  /// sin él, tal cual. Se corta en [maxChars] con "…".
  ///
  /// Solo se lee el principio: un libro entero no hace falta para mostrar
  /// sus primeras líneas. El corte cae en un fin de línea —una marca de
  /// Markdown no cruza líneas—, así que no queda ninguna partida a la mitad.
  static String excerpt(
    String raw, {
    required bool markdown,
    int maxChars = 280,
  }) {
    var text = raw;
    if (markdown) {
      final lineEnd = raw.length > maxChars * 4
          ? raw.indexOf('\n', maxChars * 4)
          : -1;
      final head = lineEnd == -1 ? raw : raw.substring(0, lineEnd);
      text = RenderedMarkdown.parse(head).displayText;
    }
    text = text
        .split('\n')
        .map((line) => line.trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return text.length > maxChars ? '${text.substring(0, maxChars)}…' : text;
  }

  final List<_Segment> _segments;

  /// El texto tal como se ve, sin ningún `#`, `**` ni `*` de marcado. Sirve
  /// para calcular selecciones y para las pruebas: es lo que un
  /// `SelectableText` arma concatenando los `TextSpan` de [buildSpans].
  final String displayText;

  /// A qué posición del texto renderizado corresponde [rawOffset] del
  /// contenido crudo.
  ///
  /// Si [rawOffset] cae dentro de una marca que no se muestra —un `#`, un
  /// `**`— se redondea a la posición visible más cercana: no hay un lugar
  /// exacto al que apuntar porque ese carácter no está en pantalla.
  int rawToRender(int rawOffset) {
    for (final segment in _segments) {
      if (rawOffset < segment.rawStart) return segment.renderStart;
      if (rawOffset <= segment.rawEnd) {
        if (!segment.kept) return segment.renderStart;
        return segment.renderStart + (rawOffset - segment.rawStart);
      }
    }
    return displayText.length;
  }

  /// A qué posición del contenido crudo corresponde [renderOffset] del
  /// texto que se ve en pantalla.
  ///
  /// Siempre cae dentro de un tramo que sí se muestra: una selección real
  /// del usuario solo puede pararse sobre texto visible.
  ///
  /// Justo en el borde entre dos tramos visibles —por ejemplo, el límite
  /// entre "mundo" y lo que sigue después de una palabra en negrita— el
  /// mismo número de [renderOffset] es a la vez el final de uno y el
  /// principio del otro, y los dos tramos pueden venir de partes bien
  /// distintas del contenido crudo si entre medio hubo marcado que se quitó
  /// —los `**` alrededor de "mundo"—. [isEnd] desempata: al principio de
  /// una selección conviene el tramo que arranca ahí, y al final el que
  /// termina ahí, así la selección no se corre para agarrar de más.
  int renderToRaw(int renderOffset, {bool isEnd = false}) {
    for (final segment in _segments) {
      if (!segment.kept) continue;
      final segRenderStart = segment.renderStart;
      final segRenderEnd = segRenderStart + segment.text.length;

      final matches = isEnd
          ? renderOffset > segRenderStart && renderOffset <= segRenderEnd
          : renderOffset >= segRenderStart && renderOffset < segRenderEnd;
      if (matches) {
        return segment.rawStart + (renderOffset - segRenderStart);
      }
    }
    return _segments.isEmpty ? 0 : _segments.last.rawEnd;
  }

  /// Arma los `TextSpan` para un `SelectableText.rich`, con los resaltados
  /// —en rangos del contenido **crudo**, como los guarda el repositorio—
  /// pintados sobre el texto ya renderizado.
  ///
  /// [baseStyle] es el estilo de partida sobre el que se aplican negrita,
  /// cursiva y compañía. `bodyLarge` por defecto, pero un bloque que ya es
  /// un título o una cita —ver `BlockView`— necesita partir del suyo propio
  /// en vez de perderlo.
  ///
  /// [activeRange] es lo que se está diciendo mientras suena el audio (F23):
  /// se pinta en amarillo, por encima de cualquier resaltado.
  TextSpan buildSpans(
    ThemeData theme,
    List<(int startOffset, int endOffset)> highlightRanges, {
    TextStyle? baseStyle,
    ValueChanged<String>? onLinkTap,
    (int startOffset, int endOffset)? activeRange,
  }) {
    final resolvedBaseStyle =
        baseStyle ??
        theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface);
    final highlightColor = theme.colorScheme.tertiaryContainer;

    // Los resaltados llegan en offsets del contenido crudo: se traducen una
    // sola vez acá, no en cada segmento. Lo que suena (F23) va encima: los
    // resaltados que lo pisan se recortan alrededor.
    final active = activeRange == null
        ? null
        : (rawToRender(activeRange.$1), rawToRender(activeRange.$2));
    final ranges = <(int, int, bool)>[
      for (final r in highlightRanges)
        ..._without((
          rawToRender(r.$1),
          rawToRender(r.$2),
        ), active).map((r) => (r.$1, r.$2, false)),
      if (active != null && active.$2 > active.$1) (active.$1, active.$2, true),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    // Un `[[Título]]` puede quedar partido en dos o tres `TextSpan` si un
    // resaltado cae encima de él —ver el bucle de abajo—; cada trozo
    // necesita su propio `TapGestureRecognizer`, pero los tres tienen que
    // llevar a lo mismo: el título completo del segmento, no el trozo
    // parcial que le tocó a ese `TextSpan`.
    TapGestureRecognizer? recognizerFor(_Segment segment) {
      if (!segment.style.link || onLinkTap == null) return null;
      return TapGestureRecognizer()..onTap = () => onLinkTap(segment.text);
    }

    TextStyle? styleFor(
      _Segment segment, {
      bool highlighted = false,
      bool playing = false,
    }) {
      var style = segment.style.toTextStyle(theme, resolvedBaseStyle);
      if (highlighted) style = style?.copyWith(backgroundColor: highlightColor);
      // Amarillo, con el texto oscuro también en modo oscuro: tiene que
      // leerse de un vistazo mientras se escucha.
      if (playing) {
        style = style?.copyWith(
          backgroundColor: playingColor,
          color: Colors.black87,
        );
      }
      if (segment.style.link) {
        style = style?.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        );
      }
      return style;
    }

    final spans = <TextSpan>[];
    for (final segment in _segments) {
      if (!segment.kept || segment.text.isEmpty) continue;

      final segStart = segment.renderStart;
      final segEnd = segStart + segment.text.length;
      var cursor = segStart;

      for (final (hlStart, hlEnd, isPlaying) in ranges) {
        final start = hlStart.clamp(segStart, segEnd);
        final end = hlEnd.clamp(segStart, segEnd);
        if (end <= start || start < cursor) continue;

        if (start > cursor) {
          spans.add(
            TextSpan(
              text: segment.text.substring(cursor - segStart, start - segStart),
              style: styleFor(segment),
              recognizer: recognizerFor(segment),
            ),
          );
        }
        spans.add(
          TextSpan(
            text: segment.text.substring(start - segStart, end - segStart),
            style: styleFor(
              segment,
              highlighted: !isPlaying,
              playing: isPlaying,
            ),
            recognizer: recognizerFor(segment),
          ),
        );
        cursor = end;
      }

      if (cursor < segEnd) {
        spans.add(
          TextSpan(
            text: segment.text.substring(cursor - segStart),
            style: styleFor(segment),
            recognizer: recognizerFor(segment),
          ),
        );
      }
    }

    return TextSpan(style: resolvedBaseStyle, children: spans);
  }

  /// El amarillo de lo que suena (F23).
  static const playingColor = Color(0xFFFFE066);

  /// [range] sin lo que cae dentro de [cut]: cero, uno o dos pedazos.
  static List<(int, int)> _without((int, int) range, (int, int)? cut) {
    if (cut == null || cut.$2 <= range.$1 || cut.$1 >= range.$2) {
      return range.$2 > range.$1 ? [range] : const [];
    }
    return [
      if (cut.$1 > range.$1) (range.$1, cut.$1),
      if (cut.$2 < range.$2) (cut.$2, range.$2),
    ];
  }

  static List<_Segment> _parse(String raw) {
    final segments = <_Segment>[];
    var lineStart = 0;

    while (lineStart <= raw.length) {
      var lineEnd = raw.indexOf('\n', lineStart);
      final hasNewline = lineEnd != -1;
      if (!hasNewline) lineEnd = raw.length;

      _parseLine(raw, lineStart, lineEnd, segments);

      if (!hasNewline) break;
      segments.add(
        _Segment.kept(rawStart: lineEnd, text: '\n', style: const _RunStyle()),
      );
      lineStart = lineEnd + 1;
    }

    _assignRenderOffsets(segments);
    return segments;
  }

  static void _assignRenderOffsets(List<_Segment> segments) {
    var offset = 0;
    for (final segment in segments) {
      segment.renderStart = offset;
      if (segment.kept) offset += segment.text.length;
    }
  }

  static final _headingPattern = RegExp(r'^(#{1,3})[ \t]+');
  static final _bulletPattern = RegExp(r'^[-*][ \t]+');
  static final _quotePattern = RegExp(r'^>[ \t]?');
  static final _rulePattern = RegExp(
    r'^(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$',
  );

  static void _parseLine(
    String raw,
    int lineStart,
    int lineEnd,
    List<_Segment> segments,
  ) {
    final line = raw.substring(lineStart, lineEnd);
    if (line.isEmpty) return;

    if (_rulePattern.hasMatch(line)) {
      segments.add(
        _Segment.kept(
          rawStart: lineStart,
          rawEnd: lineEnd,
          text: line,
          style: const _RunStyle(rule: true),
        ),
      );
      return;
    }

    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      final prefixEnd = lineStart + heading.end;
      segments.add(_Segment.removed(rawStart: lineStart, rawEnd: prefixEnd));
      _parseInline(
        raw,
        prefixEnd,
        lineEnd,
        _RunStyle(heading: heading.group(1)!.length, bold: true),
        segments,
      );
      return;
    }

    final bullet = _bulletPattern.firstMatch(line);
    if (bullet != null) {
      final markerEnd = lineStart + bullet.end;
      // "• " reemplaza a "- "/"* ": mismo largo, así que no hace falta
      // ningún ajuste especial de offsets para este tramo.
      segments.add(
        _Segment.kept(
          rawStart: lineStart,
          rawEnd: markerEnd,
          text: '• ',
          style: const _RunStyle(),
        ),
      );
      _parseInline(raw, markerEnd, lineEnd, const _RunStyle(), segments);
      return;
    }

    final quote = _quotePattern.firstMatch(line);
    if (quote != null) {
      final prefixEnd = lineStart + quote.end;
      segments.add(_Segment.removed(rawStart: lineStart, rawEnd: prefixEnd));
      _parseInline(
        raw,
        prefixEnd,
        lineEnd,
        const _RunStyle(quote: true, italic: true),
        segments,
      );
      return;
    }

    _parseInline(raw, lineStart, lineEnd, const _RunStyle(), segments);
  }

  // Cada posición del texto solo puede matchear una alternativa —la primera
  // que encaje, de izquierda a derecha entre las alternativas—, así que el
  // orden importa:
  //
  // - El código en línea va primero: lo de adentro es literal, ni un `*`
  //   ni un `[` se interpretan.
  // - La imagen y el enlace de Markdown (F30) antes que `[[Título]]`: un
  //   `[[1]](…)` —la nota al pie de Wikipedia— es un enlace cuyo texto es
  //   "[1]", y `[[Título]]` nunca va seguido de `(`.
  // - `[[Título]]` antes que el énfasis: nunca termina interpretado como dos
  //   pares de corchetes sueltos ni con un `*` colado adentro. Un título
  //   no lleva corchetes: un "[" suelto del texto seguido de un enlace
  //   —"César [[Tito](…), hijo…]"— no puede abrir un `[[…]]` que se cierre
  //   en la nota al pie de más adelante y se lleve el párrafo entero.
  // - El HTML en línea que escribe `htmlToMarkdown` donde Markdown no
  //   alcanza: `<a href>`, `<img>`, `<sup>` y `<sub>`.
  //
  // Las reglas de CommonMark que importan para no comerse texto (F22): el
  // énfasis no empieza ni termina con un espacio —"2 * 3 * 4" no es
  // cursiva—, y el guion bajo no marca nada adentro de una palabra
  // —"var_uno_dos" de una página web o un EPUB se ve tal cual—.
  static const _destination =
      r'(?:<[^<>\n]*>|(?:[^\s()<>]|\([^\s()<>]*\))*)'
      r'(?:[ \t]+"[^"\n]*")?';
  static final _inlinePattern = RegExp(
    r'(?<code>(?<fence>`+)(?!`)(?<codeText>.+?)(?<!`)\k<fence>(?!`))'
    r'|(?<image>!\[(?<alt>[^\[\]\n]*)\]\('
    '$_destination'
    r'\))'
    r'|(?<mdLink>\[(?<linkText>(?:[^\[\]\n]|\[[^\[\]\n]*\])+)\]\('
    '$_destination'
    r'\))'
    r'|\[\[(?<wiki>[^\[\]\n]+)\]\]'
    r'|(?<htmlLink><a\s[^>]*>)(?<htmlLinkText>.*?)</a\s*>'
    r'|(?<htmlImage><img\s[^>]*?/?>)'
    r'|<(?<script>sup|sub)>(?<scriptText>.*?)</\k<script>>'
    r'|\*\*(?<bold>\S(?:.*?\S)?)\*\*'
    r'|\*(?<star>\S(?:.*?\S)?)\*'
    r'|(?<![\p{L}\p{N}])_(?<under>\S(?:.*?\S)?)_(?![\p{L}\p{N}])',
    unicode: true,
  );

  static final _altAttribute = RegExp(
    r'''\balt\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
  );

  /// Lee el tramo [start]–[end] de [raw] —una línea, o el texto de una marca
  /// que ya se abrió— y agrega sus segmentos con [baseStyle] como estilo de
  /// partida.
  ///
  /// Es recursivo: lo de adentro de una negrita, de un enlace o de un
  /// `<sup>` se lee igual, así un `**[enlace](…)**` se ve como el texto del
  /// enlace en negrita, y no con su marcado.
  static void _parseInline(
    String raw,
    int start,
    int end,
    _RunStyle baseStyle,
    List<_Segment> segments,
  ) {
    final body = raw.substring(start, end);
    var cursor = 0;

    void keep(int from, int to, _RunStyle style) {
      if (to <= from) return;
      segments.add(
        _Segment.kept(
          rawStart: start + from,
          rawEnd: start + to,
          text: body.substring(from, to),
          style: style,
        ),
      );
    }

    void remove(int from, int to) {
      if (to <= from) return;
      segments.add(
        _Segment.removed(rawStart: start + from, rawEnd: start + to),
      );
    }

    /// Lo de adentro de una marca: se quita lo de los bordes y se lee lo del
    /// medio con [style].
    void inner(
      RegExpMatch match,
      String group,
      _RunStyle style, {
      required int openLength,
    }) {
      final content = match.namedGroup(group)!;
      final contentStart = match.start + openLength;
      remove(match.start, contentStart);
      _parseInline(
        raw,
        start + contentStart,
        start + contentStart + content.length,
        style,
        segments,
      );
      remove(contentStart + content.length, match.end);
    }

    for (final match in _inlinePattern.allMatches(body)) {
      keep(cursor, match.start, baseStyle);

      if (match.namedGroup('code') != null) {
        // La cerca que se agregó para que el código entre con sus comillas
        // invertidas, y el espacio que la separa de ellas, no son texto.
        final fence = match.namedGroup('fence')!.length;
        var from = match.start + fence;
        var to = match.end - fence;
        final text = body.substring(from, to);
        if (text.length > 2 &&
            text.startsWith(' ') &&
            text.endsWith(' ') &&
            text.trim().isNotEmpty) {
          from++;
          to--;
        }
        remove(match.start, from);
        keep(from, to, baseStyle.copyWith(code: true));
        remove(to, match.end);
      } else if (match.namedGroup('image') != null) {
        // Una imagen se lee como su texto alternativo. Una sin texto
        // alternativo es decorativa —eso dice un `alt=""` en HTML—: no se
        // ve nada. La imagen misma está en el «Contenido» del elemento.
        final alt = match.namedGroup('alt')!;
        if (alt.trim().isEmpty) {
          remove(match.start, match.end);
        } else {
          final altStart = match.start + 2;
          remove(match.start, altStart);
          keep(
            altStart,
            altStart + alt.length,
            baseStyle.copyWith(media: true),
          );
          remove(altStart + alt.length, match.end);
        }
      } else if (match.namedGroup('mdLink') != null) {
        // Un enlace a otra página se lee como su texto, sin la dirección.
        final text = match.namedGroup('linkText')!;
        final textStart = match.start + 1;
        remove(match.start, textStart);
        _parseInline(
          raw,
          start + textStart,
          start + textStart + text.length,
          baseStyle,
          segments,
        );
        remove(textStart + text.length, match.end);
      } else if (match.namedGroup('wiki') != null) {
        final title = match.namedGroup('wiki')!;
        final titleStart = match.start + 2;
        remove(match.start, titleStart);
        keep(
          titleStart,
          titleStart + title.length,
          const _RunStyle(link: true),
        );
        remove(titleStart + title.length, match.end);
      } else if (match.namedGroup('htmlLink') != null) {
        final open = match.namedGroup('htmlLink')!;
        final text = match.namedGroup('htmlLinkText')!;
        final textStart = match.start + open.length;
        remove(match.start, textStart);
        _parseInline(
          raw,
          start + textStart,
          start + textStart + text.length,
          baseStyle,
          segments,
        );
        remove(textStart + text.length, match.end);
      } else if (match.namedGroup('htmlImage') != null) {
        // El texto alternativo de un `<img>` está escapado como atributo:
        // no se puede mostrar un pedazo del crudo sin cambiarle caracteres,
        // y lo que se ve tiene que ser un pedazo del crudo para que los
        // resaltados caigan donde corresponde. Se ve el tramo del atributo
        // solo si no tiene nada escapado; si no, la imagen no se ve.
        final tag = match.namedGroup('htmlImage')!;
        final alt = _altAttribute.firstMatch(tag);
        final value = alt == null ? null : alt[1] ?? alt[2] ?? alt[3];
        if (value == null || value.trim().isEmpty || value.contains('&')) {
          remove(match.start, match.end);
        } else {
          final valueStart = match.start + alt!.start + alt[0]!.indexOf(value);
          remove(match.start, valueStart);
          keep(
            valueStart,
            valueStart + value.length,
            baseStyle.copyWith(media: true),
          );
          remove(valueStart + value.length, match.end);
        }
      } else if (match.namedGroup('script') != null) {
        inner(
          match,
          'scriptText',
          baseStyle.copyWith(
            script: match.namedGroup('script') == 'sup' ? 1 : -1,
          ),
          openLength: 5,
        );
      } else if (match.namedGroup('bold') != null) {
        inner(match, 'bold', baseStyle.copyWith(bold: true), openLength: 2);
      } else {
        inner(
          match,
          match.namedGroup('star') != null ? 'star' : 'under',
          baseStyle.copyWith(italic: true),
          openLength: 1,
        );
      }

      cursor = match.end;
    }

    keep(cursor, body.length, baseStyle);
  }
}

/// Un tramo del contenido crudo, con lo que muestra en pantalla —si muestra
/// algo— y el estilo con el que se dibuja.
class _Segment {
  _Segment.kept({
    required this.rawStart,
    required this.text,
    required this.style,
    int? rawEnd,
  }) : rawEnd = rawEnd ?? rawStart + text.length,
       kept = true,
       renderStart = 0;

  _Segment.removed({required this.rawStart, required this.rawEnd})
    : text = '',
      style = const _RunStyle(),
      kept = false,
      renderStart = 0;

  final int rawStart;
  final int rawEnd;
  final String text;
  final _RunStyle style;
  final bool kept;

  /// Se completa después de armar todos los segmentos: hace falta saber el
  /// largo de cada uno antes de poder decir dónde empieza el siguiente.
  int renderStart;
}

/// El formato acumulado de un tramo: título, negrita, cursiva, cita,
/// separador o enlace, combinables salvo [rule] —un separador no lleva nada
/// más— y salvo [link], que tampoco se combina con nada: un `[[Título]]`
/// dentro de una cita o un título no hereda cursiva ni tamaño, se ve
/// siempre igual a sí mismo para que sea reconocible como enlace en
/// cualquier lugar donde aparezca.
class _RunStyle {
  const _RunStyle({
    this.heading = 0,
    this.bold = false,
    this.italic = false,
    this.quote = false,
    this.rule = false,
    this.link = false,
    this.code = false,
    this.media = false,
    this.script = 0,
  });

  /// 0 quiere decir "no es un título"; 1, 2 o 3 es el nivel de `#`.
  final int heading;
  final bool bold;
  final bool italic;
  final bool quote;
  final bool rule;
  final bool link;

  /// Código en línea: letra de ancho fijo.
  final bool code;

  /// El texto alternativo de una imagen (F30): en cursiva y apagado, para
  /// que se lea como la descripción de algo que no está, no como texto.
  final bool media;

  /// 1 es un superíndice, -1 un subíndice, 0 ninguno.
  final int script;

  _RunStyle copyWith({
    bool? bold,
    bool? italic,
    bool? code,
    bool? media,
    int? script,
  }) => _RunStyle(
    heading: heading,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    quote: quote,
    rule: rule,
    link: link,
    code: code ?? this.code,
    media: media ?? this.media,
    script: script ?? this.script,
  );

  TextStyle? toTextStyle(ThemeData theme, TextStyle? base) {
    if (rule) {
      return base?.copyWith(
        color: theme.colorScheme.outlineVariant,
        letterSpacing: 2,
      );
    }
    // El color y el subrayado del enlace se aplican en `buildSpans`, no
    // acá: son los mismos sin importar si el enlace cae dentro de una cita
    // o un título, y `toTextStyle` no sabe nada de `ColorScheme.primary`
    // hasta que `buildSpans` se lo pide con el tema puesto.
    if (link) return base;

    var style = base;
    if (heading > 0) {
      final headingStyle = switch (heading) {
        1 => theme.textTheme.headlineSmall,
        2 => theme.textTheme.titleLarge,
        _ => theme.textTheme.titleMedium,
      };
      style = headingStyle?.copyWith(color: theme.colorScheme.onSurface);
    }
    if (quote || media) {
      style = style?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    }
    if (bold) style = style?.copyWith(fontWeight: FontWeight.bold);
    if (italic || media) style = style?.copyWith(fontStyle: FontStyle.italic);
    if (code) style = style?.copyWith(fontFamily: 'monospace');
    // Un índice se dibuja con los glifos de superíndice o subíndice de la
    // letra, sin cambiar de tamaño ni de renglón: la posición en el texto
    // sigue siendo la misma, que es lo que los resaltados necesitan.
    if (script != 0) {
      style = style?.copyWith(
        fontFeatures: [
          if (script > 0)
            const FontFeature.superscripts()
          else
            const FontFeature.subscripts(),
        ],
      );
    }
    return style;
  }
}
