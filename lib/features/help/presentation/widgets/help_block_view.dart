import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_markdown_blocks.dart';
import 'package:sinapsis/features/chat/presentation/widgets/markdown_blocks_view.dart';
import 'package:sinapsis/features/help/presentation/help_document.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';

/// Lo más ancho que se lee un texto de la Ayuda: en una tableta o en la
/// computadora, renglones de punta a punta de la pantalla cansan.
const kHelpReadingWidth = 720.0;

/// Un bloque de un texto de la Ayuda (F47, paso 7), con el formato de las
/// respuestas del chat y lo buscado pintado encima.
///
/// - [matches] son los lugares de lo buscado que caen en este bloque: van
///   con el fondo de los resaltados.
/// - [current] es el resultado en el que se está: en amarillo, por encima,
///   como el «buscar en la página» de un navegador.
///
/// Los renglones partidos a mano del Markdown se leen de corrido: en un
/// archivo escrito para leerse en una pantalla ancha, cada párrafo corta
/// cerca de los cien caracteres, y respetar esos cortes en un teléfono
/// dejaría los párrafos llenos de renglones cortos. (El chat sí los respeta:
/// ahí el modelo los pone a propósito.)
class HelpBlockView extends StatelessWidget {
  const HelpBlockView({
    required this.raw,
    required this.block,
    required this.previous,
    this.matches = const [],
    this.current,
    super.key,
  });

  /// El Markdown entero del que salen las posiciones de [block].
  final String raw;
  final ChatBlock block;
  final ChatBlock? previous;
  final List<HelpMatch> matches;
  final HelpMatch? current;

  @override
  Widget build(BuildContext context) {
    final style = MarkdownBlockStyle.of(context);
    return MarkdownBlockView(
      raw: raw,
      block: block,
      previous: previous,
      style: style,
      inline: (range, base, {plain = false}) =>
          _inline(style, range, base, plain: plain),
    );
  }

  InlineSpan _inline(
    MarkdownBlockStyle style,
    ChatTextRange range,
    TextStyle base, {
    required bool plain,
  }) {
    final text = raw.substring(range.start, range.end);
    final rendered = plain
        ? RenderedMarkdown.plain(text)
        : RenderedMarkdown.parse(text);

    (int, int)? relative(HelpMatch match) {
      final start = math.max(match.start, range.start);
      final end = math.min(match.end, range.end);
      return end > start ? (start - range.start, end - range.start) : null;
    }

    final found = [
      for (final match in matches)
        if (match != current)
          if (relative(match) case final at?) at,
    ];
    final root = rendered.buildSpans(
      style.theme,
      found,
      baseStyle: base,
      activeRange: current == null ? null : relative(current!),
      codeStyle: plain ? null : style.inlineCode,
    );
    return plain ? root : _reflow(root);
  }
}

/// Un salto de renglón con la sangría que le sigue: la continuación de un
/// párrafo o de un renglón de lista partido a mano.
final _softBreak = RegExp(r'\n[ \t]*');
final _leadingIndent = RegExp(r'^[ \t]+');
final _trailingBreak = RegExp(r'\n[ \t]*$');

/// [root] —los tramos que arma `RenderedMarkdown.buildSpans`— con cada salto
/// de renglón y su sangría convertidos en un espacio, aunque el salto quede
/// en un tramo y la sangría en el siguiente (un resaltado que corta justo
/// ahí). Lo pintado ya está puesto: los tramos solo se acortan.
TextSpan _reflow(TextSpan root) {
  final children = root.children;
  if (children == null) return root;
  final out = <InlineSpan>[];
  var afterBreak = false;
  for (final child in children) {
    final text = child is TextSpan ? child.text : null;
    if (child is! TextSpan || text == null) {
      out.add(child);
      afterBreak = false;
      continue;
    }
    var flowing = afterBreak ? text.replaceFirst(_leadingIndent, '') : text;
    if (flowing.isEmpty) continue;
    afterBreak = _trailingBreak.hasMatch(flowing);
    flowing = flowing.replaceAll(_softBreak, ' ');
    out.add(
      TextSpan(text: flowing, style: child.style, recognizer: child.recognizer),
    );
  }
  return TextSpan(style: root.style, children: out);
}
