import 'package:flutter/material.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_markdown_blocks.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_message_menu.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El texto de [range] con formato, armado por quien muestra los bloques: el
/// chat le suma las citas, el fundido y el amarillo del lector; la Ayuda, lo
/// que se busca. Con [plain], sin interpretar ningún marcado (el código).
typedef MarkdownInlineBuilder =
    InlineSpan Function(ChatTextRange range, TextStyle base, {bool plain});

/// Cómo se ve un texto en Markdown partido en bloques (F42): títulos,
/// párrafos, listas, citas, código, tablas y separadores.
///
/// Nació con el chat y lo comparte la Ayuda de Ajustes (F47, paso 7): la
/// guía de uso y las novedades se leen con la misma letra y el mismo aire
/// que una respuesta, en vez de con un segundo lector de Markdown.
class MarkdownBlockStyle {
  MarkdownBlockStyle._(this.theme, this.scaler)
    : scheme = theme.colorScheme,
      body = theme.textTheme.bodyLarge!.copyWith(
        color: theme.colorScheme.onSurface,
        height: 1.55,
      );

  factory MarkdownBlockStyle.of(BuildContext context) =>
      MarkdownBlockStyle._(Theme.of(context), MediaQuery.textScalerOf(context));

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

/// El espacio arriba de [block], según lo que tiene arriba ([previous]):
/// más antes de un título, poco entre renglones de una misma lista y nada
/// entre renglones de una misma cita.
double markdownBlockGap(ChatBlock? previous, ChatBlock block) {
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

/// Un bloque de [raw] con formato, y su espacio arriba según [previous].
///
/// Lo de adentro de cada bloque lo arma [inline], así que quien lo usa
/// decide qué se pinta encima del texto. Un título es un encabezado para el
/// lector de pantalla.
class MarkdownBlockView extends StatelessWidget {
  const MarkdownBlockView({
    required this.raw,
    required this.block,
    required this.previous,
    required this.style,
    required this.inline,
    super.key,
  });

  /// El texto entero del que salen las posiciones de [block].
  final String raw;
  final ChatBlock block;
  final ChatBlock? previous;
  final MarkdownBlockStyle style;
  final MarkdownInlineBuilder inline;

  @override
  Widget build(BuildContext context) {
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
        code: raw.substring(block.content.start, block.content.end),
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
    final gap = markdownBlockGap(previous, block);
    return gap == 0
        ? child
        : Padding(
            padding: EdgeInsets.only(top: style.scaler.scale(gap)),
            child: child,
          );
  }
}

/// Un renglón de lista: la viñeta o el número, y el texto con su sangría.
class _ListItem extends StatelessWidget {
  const _ListItem({
    required this.block,
    required this.style,
    required this.content,
  });

  final ChatBlock block;
  final MarkdownBlockStyle style;
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
  final MarkdownBlockStyle style;
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

  final MarkdownBlockStyle style;

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
