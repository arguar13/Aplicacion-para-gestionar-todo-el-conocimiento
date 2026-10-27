import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_citations.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_markdown_blocks.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_message_menu.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

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
    final style = _AnswerStyle.of(context);

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

  /// El espacio arriba de [block], según lo que tiene arriba.
  double _gap(ChatBlock? previous, ChatBlock block) {
    if (previous == null) return 0;
    if (block.kind == ChatBlockKind.heading) return 20;
    if (previous.kind == ChatBlockKind.heading) return 8;
    if (block.kind == ChatBlockKind.listItem &&
        previous.kind == ChatBlockKind.listItem) {
      return 6;
    }
    if (block.kind == ChatBlockKind.quote &&
        previous.kind == ChatBlockKind.quote) {
      return 0;
    }
    return 12;
  }

  Widget _block(
    _AnswerStyle style,
    ChatBlock block,
    ChatBlock? previous,
    (int, int)? reading,
  ) {
    InlineSpan inline(
      ChatTextRange range,
      TextStyle base, {
      bool plain = false,
    }) => _inline(style, range, base, reading: reading, plain: plain);

    final child = switch (block.kind) {
      ChatBlockKind.paragraph => Text.rich(inline(block.content, style.body)),
      ChatBlockKind.heading => Semantics(
        header: true,
        child: Text.rich(inline(block.content, style.heading(block.level))),
      ),
      ChatBlockKind.listItem => _ListItem(
        block: block,
        style: style,
        content: Text.rich(inline(block.content, style.body)),
      ),
      ChatBlockKind.quote => DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(color: style.scheme.outlineVariant, width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 12,
            top: 2,
            bottom: 2,
          ),
          child: Text.rich(inline(block.content, style.quote)),
        ),
      ),
      ChatBlockKind.code => _CodeBlock(
        language: block.language,
        code: widget.text.substring(block.content.start, block.content.end),
        style: style,
        body: Text.rich(
          inline(block.content, style.code, plain: true),
          softWrap: false,
        ),
      ),
      ChatBlockKind.rule => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 1, color: style.scheme.outlineVariant),
      ),
      ChatBlockKind.table => _TableBlock(
        style: style,
        rows: [
          for (var r = 0; r < block.rows.length; r++)
            [
              for (final cell in block.rows[r])
                inline(cell, r == 0 ? style.tableHeader : style.body),
            ],
        ],
      ),
    };
    final gap = _gap(previous, block);
    return gap == 0
        ? child
        : Padding(
            padding: EdgeInsets.only(top: style.scaler.scale(gap)),
            child: child,
          );
  }

  /// El texto de [range] con formato, el amarillo del lector, el fundido de
  /// lo que acaba de llegar y las citas como chips.
  InlineSpan _inline(
    _AnswerStyle style,
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

/// La tipografía de una respuesta, armada una vez por dibujo.
class _AnswerStyle {
  _AnswerStyle._(this.theme, this.scaler)
    : scheme = theme.colorScheme,
      body = theme.textTheme.bodyLarge!.copyWith(
        color: theme.colorScheme.onSurface,
        height: 1.55,
      );

  factory _AnswerStyle.of(BuildContext context) =>
      _AnswerStyle._(Theme.of(context), MediaQuery.textScalerOf(context));

  final ThemeData theme;
  final ColorScheme scheme;
  final TextScaler scaler;

  /// La letra de todo lo que no es título ni código: un poco más de aire
  /// entre renglones que el resto de la app, para leer de corrido.
  final TextStyle body;

  TextStyle heading(int level) {
    final size = body.fontSize ?? 16;
    return switch (level) {
      1 => theme.textTheme.titleLarge!,
      2 => theme.textTheme.titleMedium!.copyWith(fontSize: size * 1.15),
      _ => theme.textTheme.titleMedium!.copyWith(fontSize: size),
    }.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w700,
      height: 1.3,
    );
  }

  TextStyle get quote => body.copyWith(
    color: scheme.onSurfaceVariant,
    fontStyle: FontStyle.italic,
  );

  TextStyle get code => body.copyWith(
    fontFamily: 'monospace',
    fontSize: (body.fontSize ?? 16) * 0.88,
    height: 1.45,
  );

  /// Lo que se suma al código en línea: un fondo apenas marcado.
  TextStyle get inlineCode => TextStyle(
    backgroundColor: scheme.surfaceContainerHighest,
    fontSize: (body.fontSize ?? 16) * 0.92,
  );

  TextStyle get tableHeader => body.copyWith(fontWeight: FontWeight.w700);
}

/// Un renglón de lista: la viñeta o el número, y el texto con su sangría.
class _ListItem extends StatelessWidget {
  const _ListItem({
    required this.block,
    required this.style,
    required this.content,
  });

  final ChatBlock block;
  final _AnswerStyle style;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final marker = block.ordinal ?? const ['•', '◦', '▪', '▪'][block.depth];
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: style.scaler.scale(4 + 18.0 * block.depth),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: style.scaler.scale(18)),
            child: ExcludeSemantics(
              excluding: block.ordinal == null,
              child: Text(
                marker,
                style: style.body.copyWith(
                  color: style.scheme.onSurfaceVariant,
                  fontWeight: block.ordinal == null ? null : FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// Un bloque de código: el lenguaje y «Copiar el código» arriba, y el código
/// sin cortar los renglones, deslizable de costado.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.language,
    required this.code,
    required this.style,
    required this.body,
  });

  final String? language;
  final String code;
  final _AnswerStyle style;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = style.scheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, end: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language ?? l10n.chatCodeLabel,
                    style: style.theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  tooltip: l10n.chatCodeCopy,
                  color: scheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => copyChatText(context, code),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: body,
          ),
        ],
      ),
    );
  }
}

/// Una tabla: la fila de los títulos marcada, bordes suaves, deslizable de
/// costado si no entra.
class _TableBlock extends StatelessWidget {
  const _TableBlock({required this.style, required this.rows});

  final _AnswerStyle style;

  /// Las celdas de cada fila, la primera la de los títulos.
  final List<List<InlineSpan>> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = style.scheme;
    // Todas las filas con las mismas columnas que la de los títulos.
    final columns = rows.first.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.symmetric(
              inside: BorderSide(color: scheme.outlineVariant),
            ),
            children: [
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  decoration: r == 0
                      ? BoxDecoration(color: scheme.surfaceContainerHigh)
                      : null,
                  children: [
                    for (var c = 0; c < columns; c++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: style.scaler.scale(240),
                          ),
                          child: c < rows[r].length
                              ? Text.rich(rows[r][c])
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
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
