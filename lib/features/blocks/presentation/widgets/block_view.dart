import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';

/// Muestra una nota de bloques ya guardada, de solo lectura.
///
/// Aparte del editor a propósito: leer no necesita controladores de texto,
/// selección de tipo ni reordenamiento — es una lista de widgets simples,
/// cada uno resuelto según el tipo del bloque que le tocó.
///
/// La usan el detalle de la nota y su lectura (F46, paso 5j): en la lectura,
/// con la letra de «Apariencia» ([baseStyle]) y el color de «Resaltado de
/// lectura» ([playingColor]).
class BlockView extends StatelessWidget {
  const BlockView({
    required this.blocks,
    this.onLinkTap,
    this.renditionId,
    this.baseStyle,
    this.playingColor,
    super.key,
  });

  final List<ContentBlock> blocks;

  /// La forma de contenido de donde salen [blocks]: con ella, lo que lee el
  /// lector flotante se ve en amarillo (F25). `null` en una vista previa,
  /// que no se lee.
  final String? renditionId;

  /// La letra del texto. Sin ella, la del tema (`bodyLarge`). Los títulos
  /// salen de ella, más grandes y en negrita: así siguen el tamaño que se
  /// eligió para leer.
  final TextStyle? baseStyle;

  /// El color de lo que lee el lector flotante; sin él, el amarillo de
  /// siempre.
  final Color? playingColor;

  /// Con qué nombre conoce el lector flotante al bloque [index] de la forma
  /// [renditionId] (F25): cada bloque es un texto aparte, con sus posiciones
  /// contadas sobre su propio texto, tal cual se guarda.
  static String readAloudKey(String renditionId, int index) =>
      'blocks:$renditionId:$index';

  /// Lo que lee el lector flotante de [blocks], la forma [renditionId]: un
  /// texto por bloque, con su nombre ([readAloudKey]) y en Markdown —la
  /// negrita, la cursiva y los `[[Título]]` se leen sin sus marcas—. Lo
  /// ofrecen el detalle de la nota y su lectura, y por eso lo de una suena
  /// igual que lo de la otra.
  static List<ReadablePart> readAloudParts(
    String renditionId,
    List<ContentBlock> blocks,
  ) => [
    for (final (index, block) in blocks.indexed)
      (
        sourceKey: readAloudKey(renditionId, index),
        text: block.text,
        markdown: true,
        transcript: false,
      ),
  ];

  /// Qué hacer al tocar un `[[Título]]` dentro de cualquier bloque, con el
  /// título tal cual quedó escrito. `null` deja los enlaces sin ninguna
  /// acción —se ven distinguibles del resto del texto, pero no responden
  /// al toque—, para donde mostrar una nota de bloques no tiene sentido de
  /// navegación, como una vista previa.
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final style = _BlockStyle.of(context, baseStyle, playingColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, block) in blocks.indexed) ...[
          _BlockLine(
            block: block,
            style: style,
            onLinkTap: onLinkTap,
            sourceKey: switch (renditionId) {
              final id? => readAloudKey(id, index),
              null => null,
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Las letras de una nota de bloques: la del texto, la de los dos niveles de
/// título y el color de lo que se lee.
class _BlockStyle {
  const _BlockStyle({
    required this.body,
    required this.title,
    required this.subtitle,
    required this.playing,
  });

  factory _BlockStyle.of(
    BuildContext context,
    TextStyle? base,
    Color? playing,
  ) {
    final theme = Theme.of(context);
    final playingColor = playing ?? RenderedMarkdown.playingColor;
    if (base == null) {
      return _BlockStyle(
        body: theme.textTheme.bodyLarge,
        title: theme.textTheme.headlineSmall,
        subtitle: theme.textTheme.titleLarge,
        playing: playingColor,
      );
    }
    final size = base.fontSize ?? 16;
    TextStyle heading(double factor) => base.copyWith(
      fontSize: size * factor,
      fontWeight: FontWeight.w700,
      height: 1.3,
    );
    return _BlockStyle(
      body: base,
      title: heading(_titleFactor),
      subtitle: heading(_subtitleFactor),
      playing: playingColor,
    );
  }

  /// Cuánto más grande que el texto va un título de cada nivel, como los de
  /// Material sobre `bodyLarge` (24 y 22 sobre 16).
  static const _titleFactor = 1.5;
  static const _subtitleFactor = 1.375;

  final TextStyle? body;
  final TextStyle? title;
  final TextStyle? subtitle;
  final Color playing;
}

class _BlockLine extends StatelessWidget {
  const _BlockLine({
    required this.block,
    required this.style,
    required this.onLinkTap,
    required this.sourceKey,
  });

  final ContentBlock block;
  final _BlockStyle style;
  final ValueChanged<String>? onLinkTap;
  final String? sourceKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = style.body;

    Widget formatted(String text, TextStyle? textStyle) => _FormattedText(
      text: text,
      style: textStyle,
      playing: style.playing,
      onLinkTap: onLinkTap,
      sourceKey: sourceKey,
    );

    return switch (block) {
      ParagraphBlock(:final text) => formatted(text, body),
      HeadingBlock(:final text, :final level) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: formatted(text, level <= 1 ? style.title : style.subtitle),
      ),
      BulletItemBlock(:final text) => _ListLine(
        bullet: '•',
        style: body,
        child: formatted(text, body),
      ),
      NumberedItemBlock(:final text) => _ListLine(
        bullet: '—',
        style: body,
        child: formatted(text, body),
      ),
      ChecklistItemBlock(:final text, :final checked) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: formatted(
              text,
              body?.copyWith(
                decoration: checked ? TextDecoration.lineThrough : null,
                color: checked ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
        ],
      ),
      QuoteBlock(:final text) => Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outline, width: 3),
          ),
        ),
        child: formatted(
          text,
          body?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    };
  }
}

class _ListLine extends StatelessWidget {
  const _ListLine({
    required this.bullet,
    required this.style,
    required this.child,
  });

  final String bullet;
  final TextStyle? style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 20, child: Text(bullet, style: style)),
        Expanded(child: child),
      ],
    );
  }
}

/// El texto de un bloque, con **negrita** y *cursiva* renderizadas de
/// verdad en vez de mostrar los asteriscos sueltos, y `[[Título]]` como un
/// enlace tocable —ver `RenderedMarkdown`—.
///
/// A diferencia de `HighlightableText`, acá no hace falta traducir
/// posiciones entre lo crudo y lo renderizado: una nota de bloques no
/// tiene resaltados propios —los subrayados son sobre el contenido
/// importado, no sobre lo que se escribe a mano en el editor—, así que
/// alcanza con un `Text.rich` de solo lectura. Lo único que se pinta encima
/// es lo que lee el lector flotante (F25), en posiciones de [text].
class _FormattedText extends ConsumerWidget {
  const _FormattedText({
    required this.text,
    required this.style,
    required this.playing,
    required this.onLinkTap,
    required this.sourceKey,
  });

  final String text;
  final TextStyle? style;
  final Color playing;
  final ValueChanged<String>? onLinkTap;

  /// Ver [BlockView.readAloudKey]; `null` si no se lee.
  final String? sourceKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = sourceKey;
    final rendered = RenderedMarkdown.parse(text);
    return Text.rich(
      rendered.buildSpans(
        Theme.of(context),
        const [],
        baseStyle: style,
        onLinkTap: onLinkTap,
        playing: playing,
        activeRange: key == null
            ? null
            : ref.watch(readAloudHighlightProvider(key)),
      ),
    );
  }
}
