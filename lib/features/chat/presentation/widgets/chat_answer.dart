import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_citations.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_markdown_blocks.dart';
import 'package:sinapsis/features/chat/presentation/widgets/markdown_blocks_view.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';

/// Cuánto tarda en verse entero lo que el modelo acaba de escribir (F42).
const kChatWordFade = Duration(milliseconds: 320);

/// Un «[1]», un «[2, 3]» o un «[1; 4]» del texto: las fuentes que citó el
/// modelo, numeradas como se las dio el chat (ver `_buildVaultPrompt`).
final _citation = RegExp(r'\[(\d{1,2}(?:[ \t]*[,;][ \t]*\d{1,2})*)\]');

/// El texto de una respuesta del chat, con formato (F42): títulos, párrafos,
/// listas, citas, código, tablas y separadores, sin burbuja y a todo lo
/// ancho.
///
/// - Las citas de la bóveda («[1]») son chips con su número, si [sources]
///   tiene esa fuente; tocarlos la abre en su lugar.
/// - Lo que está leyendo el lector en voz alta se pinta en amarillo, en el
///   mismo lugar que en el texto crudo (F25): las posiciones de [sourceKey]
///   son las de [text] tal cual.
/// - Con [growing], [text] es la respuesta mientras se escribe: se lee de a
///   pedazos ([ChatBlockStream]) y lo que llega entra con un fundido suave,
///   salvo con «sin animaciones».
///
/// **Rendimiento.** Cada bloque se arma una vez y se guarda: mientras la
/// respuesta crece, solo se vuelven a armar los bloques que todavía pueden
/// cambiar y los que se están fundiendo —el último o los dos últimos—, no la
/// respuesta entera con cada palabra. El amarillo del lector rearma solo el
/// bloque que toca.
class ChatAnswerBody extends ConsumerStatefulWidget {
  const ChatAnswerBody({
    required this.text,
    required this.sourceKey,
    this.sources = const [],
    this.growing = false,
    super.key,
  });

  final String text;
  final String sourceKey;
  final List<ChatSource> sources;
  final bool growing;

  @override
  ConsumerState<ChatAnswerBody> createState() => _ChatAnswerBodyState();
}

/// Un tramo del texto que acaba de llegar, en posiciones de
/// [ChatAnswerBody.text], y cuándo llegó.
class _Fade {
  _Fade(this.from, this.to, this.born);

  final int from;
  int to;
  final Duration born;
}

class _ChatAnswerBodyState extends ConsumerState<ChatAnswerBody>
    with SingleTickerProviderStateMixin {
  final _stream = ChatBlockStream();
  late List<ChatBlock> _blocks;

  /// Los bloques ya armados, sin amarillo ni fundido: se rearman solo si
  /// cambia el tema, la letra o las fuentes.
  var _built = Expando<Widget>('bloque armado');

  final _fades = <_Fade>[];
  late final Ticker _ticker = createTicker(_onTick);
  var _now = Duration.zero;

  @override
  void initState() {
    super.initState();
    _blocks = _read(widget.text);
  }

  List<ChatBlock> _read(String text) =>
      widget.growing ? _stream.update(text) : parseChatBlocks(text);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = Expando<Widget>('bloque armado');
  }

  @override
  void didUpdateWidget(ChatAnswerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Las mismas fuentes llegan en otra lista cada vez que la base avisa
    // algo: solo si cambian de verdad hay que rearmar los chips.
    if (!listEquals(oldWidget.sources, widget.sources)) {
      _built = Expando<Widget>('bloque armado');
    }
    if (oldWidget.text == widget.text) return;
    _blocks = _read(widget.text);
    if (widget.growing &&
        widget.text.length > oldWidget.text.length &&
        !MediaQuery.disableAnimationsOf(context)) {
      _fadeIn(oldWidget.text.length, widget.text.length);
    }
  }

  void _fadeIn(int from, int to) {
    if (!_ticker.isActive) {
      _fades.clear();
      _now = Duration.zero;
      unawaited(_ticker.start());
    }
    final last = _fades.lastOrNull;
    if (last != null && last.born == _now && last.to == from) {
      last.to = to;
      return;
    }
    _fades.add(_Fade(from, to, _now));
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    _fades.removeWhere((fade) => elapsed - fade.born >= kChatWordFade);
    if (_fades.isEmpty) _ticker.stop();
    setState(() {});
  }

  double _alpha(_Fade fade) => Curves.easeOut.transform(
    ((_now - fade.born).inMicroseconds / kChatWordFade.inMicroseconds).clamp(
      0.0,
      1.0,
    ),
  );

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reading = ref.watch(readAloudHighlightProvider(widget.sourceKey));
    final style = MarkdownBlockStyle.of(context);

    final children = <Widget>[];
    ChatBlock? previous;
    for (final block in _blocks) {
      final live = _touches(block, reading) || _fading(block);
      children.add(
        live
            ? _block(style, block, previous, reading)
            : (_built[block] ??= _block(style, block, previous, null)),
      );
      previous = block;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  bool _touches(ChatBlock block, (int, int)? reading) =>
      reading != null && reading.$1 < block.end && reading.$2 > block.start;

  bool _fading(ChatBlock block) =>
      _fades.any((fade) => fade.from < block.end && fade.to > block.start);

  Widget _block(
    MarkdownBlockStyle style,
    ChatBlock block,
    ChatBlock? previous,
    (int, int)? reading,
  ) => MarkdownBlockView(
    raw: widget.text,
    block: block,
    previous: previous,
    style: style,
    inline: (range, base, {plain = false}) =>
        _inline(style, range, base, reading: reading, plain: plain),
  );

  /// El texto de [range] con formato, el amarillo del lector, el fundido de
  /// lo que acaba de llegar y las citas como chips.
  InlineSpan _inline(
    MarkdownBlockStyle style,
    ChatTextRange range,
    TextStyle base, {
    required (int, int)? reading,
    bool plain = false,
  }) {
    final raw = widget.text.substring(range.start, range.end);
    final rendered = plain
        ? RenderedMarkdown.plain(raw)
        : RenderedMarkdown.parse(raw);

    (int, int)? active;
    if (reading != null) {
      final start = math.max(reading.$1, range.start);
      final end = math.min(reading.$2, range.end);
      if (end > start) active = (start - range.start, end - range.start);
    }
    final root = rendered.buildSpans(
      style.theme,
      const [],
      baseStyle: base,
      activeRange: active,
      codeStyle: plain ? null : style.inlineCode,
    );

    final fades = [
      for (final fade in _fades)
        if (fade.from < range.end && fade.to > range.start)
          (
            start: rendered.rawToRender(
              math.max(fade.from, range.start) - range.start,
            ),
            end: rendered.rawToRender(
              math.min(fade.to, range.end) - range.start,
            ),
            alpha: _alpha(fade),
          ),
    ];
    final citations = plain || widget.sources.isEmpty
        ? const <_Citation>[]
        : _citationsIn(rendered.displayText);
    if (fades.isEmpty && citations.isEmpty) return root;

    return TextSpan(
      style: root.style,
      children: _decorate(
        root.children ?? const [],
        fades: fades,
        citations: citations,
        base: base,
      ),
    );
  }

  /// Las citas de [display] que nombran fuentes que existen: «[7]» con dos
  /// fuentes queda como texto, tal cual lo escribió el modelo.
  List<_Citation> _citationsIn(String display) => [
    for (final match in _citation.allMatches(display))
      if (match
              .group(1)!
              .split(RegExp('[,;]'))
              .map((n) => int.parse(n.trim()))
              .toList()
          case final numbers
          when numbers.every((n) => n >= 1 && n <= widget.sources.length))
        _Citation(match.start, match.end, numbers),
  ];

  /// [spans] —los tramos planos que arma `RenderedMarkdown.buildSpans`— con
  /// las citas como chips y lo que acaba de llegar más transparente.
  List<InlineSpan> _decorate(
    List<InlineSpan> spans, {
    required List<({int start, int end, double alpha})> fades,
    required List<_Citation> citations,
    required TextStyle base,
  }) {
    double alphaAt(int at) {
      for (final fade in fades) {
        if (at >= fade.start && at < fade.end) return fade.alpha;
      }
      return 1;
    }

    final out = <InlineSpan>[];
    var offset = 0;
    var next = 0;
    for (final span in spans) {
      final text = span is TextSpan ? span.text : null;
      if (span is! TextSpan || text == null) {
        out.add(span);
        continue;
      }
      final spanEnd = offset + text.length;
      var cursor = offset;
      while (cursor < spanEnd) {
        while (next < citations.length && citations[next].end <= cursor) {
          next++;
        }
        final citation = next < citations.length ? citations[next] : null;
        if (citation != null && citation.start <= cursor) {
          // Una cita se dibuja una sola vez, donde empieza, aunque su texto
          // quede repartido en dos tramos.
          if (citation.start == cursor) {
            final alpha = alphaAt(cursor);
            for (final number in citation.numbers) {
              final chip = ChatCitationChip(
                number: number,
                source: widget.sources[number - 1],
              );
              out.add(
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: alpha < 1
                      ? Opacity(opacity: alpha, child: chip)
                      : chip,
                ),
              );
            }
          }
          cursor = math.min(citation.end, spanEnd);
          continue;
        }

        var cut = spanEnd;
        if (citation != null && citation.start < cut) cut = citation.start;
        for (final fade in fades) {
          if (fade.start > cursor && fade.start < cut) cut = fade.start;
          if (fade.end > cursor && fade.end < cut) cut = fade.end;
        }
        final alpha = alphaAt(cursor);
        var style = span.style;
        if (alpha < 1) {
          final color = style?.color ?? base.color ?? Colors.black;
          style = (style ?? base).copyWith(
            color: color.withValues(alpha: color.a * alpha),
          );
        }
        out.add(
          TextSpan(
            text: text.substring(cursor - offset, cut - offset),
            style: style,
            recognizer: span.recognizer,
          ),
        );
        cursor = cut;
      }
      offset = spanEnd;
    }
    return out;
  }
}

/// Una cita en el texto que se ve: dónde está y qué fuentes nombra.
class _Citation {
  const _Citation(this.start, this.end, this.numbers);

  final int start;
  final int end;
  final List<int> numbers;
}

/// [raw] —una respuesta en Markdown— como se lee, sin marcas: lo que se
/// ofrece para seleccionar y copiar una parte (F42).
String chatAnswerPlainText(String raw) {
  String inline(ChatTextRange range) =>
      RenderedMarkdown.parse(raw.substring(range.start, range.end)).displayText;

  final out = StringBuffer();
  ChatBlock? previous;
  for (final block in parseChatBlocks(raw)) {
    if (previous != null) {
      out.write(
        block.kind == ChatBlockKind.listItem &&
                previous.kind == ChatBlockKind.listItem
            ? '\n'
            : '\n\n',
      );
    }
    switch (block.kind) {
      case ChatBlockKind.paragraph ||
          ChatBlockKind.heading ||
          ChatBlockKind.quote:
        out.write(inline(block.content));
      case ChatBlockKind.listItem:
        out
          ..write('  ' * block.depth)
          ..write('${block.ordinal ?? '•'} ')
          ..write(inline(block.content));
      case ChatBlockKind.code:
        out.write(raw.substring(block.content.start, block.content.end));
      case ChatBlockKind.rule:
        out.write('———');
      case ChatBlockKind.table:
        out.write(
          block.rows.map((row) => row.map(inline).join(' | ')).join('\n'),
        );
    }
    previous = block;
  }
  return out.toString();
}
