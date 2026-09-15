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
  TextSpan buildSpans(
    ThemeData theme,
    List<(int startOffset, int endOffset)> highlightRanges, {
    TextStyle? baseStyle,
  }) {
    final resolvedBaseStyle =
        baseStyle ??
        theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface);
    final highlightColor = theme.colorScheme.tertiaryContainer;

    // Los resaltados llegan en offsets del contenido crudo: se traducen una
    // sola vez acá, no en cada segmento.
    final ranges =
        highlightRanges
            .map((r) => (rawToRender(r.$1), rawToRender(r.$2)))
            .where((r) => r.$2 > r.$1)
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));

    final spans = <TextSpan>[];
    for (final segment in _segments) {
      if (!segment.kept || segment.text.isEmpty) continue;

      final segStart = segment.renderStart;
      final segEnd = segStart + segment.text.length;
      var cursor = segStart;

      for (final (hlStart, hlEnd) in ranges) {
        final start = hlStart.clamp(segStart, segEnd);
        final end = hlEnd.clamp(segStart, segEnd);
        if (end <= start || start < cursor) continue;

        if (start > cursor) {
          spans.add(
            TextSpan(
              text: segment.text.substring(cursor - segStart, start - segStart),
              style: segment.style.toTextStyle(theme, resolvedBaseStyle),
            ),
          );
        }
        spans.add(
          TextSpan(
            text: segment.text.substring(start - segStart, end - segStart),
            style: segment.style
                .toTextStyle(theme, resolvedBaseStyle)
                ?.copyWith(backgroundColor: highlightColor),
          ),
        );
        cursor = end;
      }

      if (cursor < segEnd) {
        spans.add(
          TextSpan(
            text: segment.text.substring(cursor - segStart),
            style: segment.style.toTextStyle(theme, resolvedBaseStyle),
          ),
        );
      }
    }

    return TextSpan(style: resolvedBaseStyle, children: spans);
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
  static final _rulePattern = RegExp(r'^(-{3,}|\*{3,})\s*$');

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

  static final _emphasisPattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|_(.+?)_');

  static void _parseInline(
    String raw,
    int start,
    int end,
    _RunStyle baseStyle,
    List<_Segment> segments,
  ) {
    final body = raw.substring(start, end);
    var cursor = 0;

    for (final match in _emphasisPattern.allMatches(body)) {
      if (match.start > cursor) {
        segments.add(
          _Segment.kept(
            rawStart: start + cursor,
            rawEnd: start + match.start,
            text: body.substring(cursor, match.start),
            style: baseStyle,
          ),
        );
      }

      final isBold = match.group(1) != null;
      final content = match.group(1) ?? match.group(2) ?? match.group(3)!;
      final markerLength = isBold ? 2 : 1;
      final contentStart = start + match.start + markerLength;

      segments
        ..add(
          _Segment.removed(rawStart: start + match.start, rawEnd: contentStart),
        )
        ..add(
          _Segment.kept(
            rawStart: contentStart,
            rawEnd: contentStart + content.length,
            text: content,
            style: baseStyle.copyWith(
              bold: isBold || baseStyle.bold,
              italic: !isBold || baseStyle.italic,
            ),
          ),
        )
        ..add(
          _Segment.removed(
            rawStart: contentStart + content.length,
            rawEnd: start + match.end,
          ),
        );

      cursor = match.end;
    }

    if (cursor < body.length) {
      segments.add(
        _Segment.kept(
          rawStart: start + cursor,
          rawEnd: end,
          text: body.substring(cursor),
          style: baseStyle,
        ),
      );
    }
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

/// El formato acumulado de un tramo: título, negrita, cursiva, cita o
/// separador, combinables salvo [rule] —un separador no lleva nada más—.
class _RunStyle {
  const _RunStyle({
    this.heading = 0,
    this.bold = false,
    this.italic = false,
    this.quote = false,
    this.rule = false,
  });

  /// 0 quiere decir "no es un título"; 1, 2 o 3 es el nivel de `#`.
  final int heading;
  final bool bold;
  final bool italic;
  final bool quote;
  final bool rule;

  _RunStyle copyWith({bool? bold, bool? italic}) => _RunStyle(
    heading: heading,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    quote: quote,
    rule: rule,
  );

  TextStyle? toTextStyle(ThemeData theme, TextStyle? base) {
    if (rule) {
      return base?.copyWith(
        color: theme.colorScheme.outlineVariant,
        letterSpacing: 2,
      );
    }

    var style = base;
    if (heading > 0) {
      final headingStyle = switch (heading) {
        1 => theme.textTheme.headlineSmall,
        2 => theme.textTheme.titleLarge,
        _ => theme.textTheme.titleMedium,
      };
      style = headingStyle?.copyWith(color: theme.colorScheme.onSurface);
    }
    if (quote) {
      style = style?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    }
    if (bold) style = style?.copyWith(fontWeight: FontWeight.bold);
    if (italic) style = style?.copyWith(fontStyle: FontStyle.italic);
    return style;
  }
}
