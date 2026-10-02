import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';

/// Muestra una nota de bloques ya guardada, de solo lectura.
///
/// Aparte del editor a propósito: leer no necesita controladores de texto,
/// selección de tipo ni reordenamiento — es una lista de widgets simples,
/// cada uno resuelto según el tipo del bloque que le tocó.
class BlockView extends StatelessWidget {
  const BlockView({
    required this.blocks,
    this.onLinkTap,
    this.renditionId,
    super.key,
  });

  final List<ContentBlock> blocks;

  /// La forma de contenido de donde salen [blocks]: con ella, lo que lee el
  /// lector flotante se ve en amarillo (F25). `null` en una vista previa,
  /// que no se lee.
  final String? renditionId;

  /// Con qué nombre conoce el lector flotante al bloque [index] de la forma
  /// [renditionId] (F25): cada bloque es un texto aparte, con sus posiciones
  /// contadas sobre su propio texto, tal cual se guarda.
  static String readAloudKey(String renditionId, int index) =>
      'blocks:$renditionId:$index';

  /// Qué hacer al tocar un `[[Título]]` dentro de cualquier bloque, con el
  /// título tal cual quedó escrito. `null` deja los enlaces sin ninguna
  /// acción —se ven distinguibles del resto del texto, pero no responden
  /// al toque—, para donde mostrar una nota de bloques no tiene sentido de
  /// navegación, como una vista previa.
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, block) in blocks.indexed) ...[
          _BlockLine(
            block: block,
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

class _BlockLine extends StatelessWidget {
  const _BlockLine({
    required this.block,
    required this.onLinkTap,
    required this.sourceKey,
  });

  final ContentBlock block;
  final ValueChanged<String>? onLinkTap;
  final String? sourceKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return switch (block) {
      ParagraphBlock(:final text) => _FormattedText(
        text: text,
        style: theme.textTheme.bodyLarge,
        onLinkTap: onLinkTap,
        sourceKey: sourceKey,
      ),
      HeadingBlock(:final text, :final level) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _FormattedText(
          text: text,
          style: level <= 1
              ? theme.textTheme.headlineSmall
              : theme.textTheme.titleLarge,
          onLinkTap: onLinkTap,
          sourceKey: sourceKey,
        ),
      ),
      BulletItemBlock(:final text) => _ListLine(
        bullet: '•',
        text: text,
        onLinkTap: onLinkTap,
        sourceKey: sourceKey,
      ),
      NumberedItemBlock(:final text) => _ListLine(
        bullet: '—',
        text: text,
        onLinkTap: onLinkTap,
        sourceKey: sourceKey,
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
            child: _FormattedText(
              text: text,
              style: theme.textTheme.bodyLarge?.copyWith(
                decoration: checked ? TextDecoration.lineThrough : null,
                color: checked ? theme.colorScheme.onSurfaceVariant : null,
              ),
              onLinkTap: onLinkTap,
              sourceKey: sourceKey,
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
        child: _FormattedText(
          text: text,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          onLinkTap: onLinkTap,
          sourceKey: sourceKey,
        ),
      ),
    };
  }
}

class _ListLine extends StatelessWidget {
  const _ListLine({
    required this.bullet,
    required this.text,
    required this.onLinkTap,
    required this.sourceKey,
  });

  final String bullet;
  final String text;
  final ValueChanged<String>? onLinkTap;
  final String? sourceKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          child: Text(bullet, style: theme.textTheme.bodyLarge),
        ),
        Expanded(
          child: _FormattedText(
            text: text,
            style: theme.textTheme.bodyLarge,
            onLinkTap: onLinkTap,
            sourceKey: sourceKey,
          ),
        ),
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
    required this.onLinkTap,
    required this.sourceKey,
  });

  final String text;
  final TextStyle? style;
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
        activeRange: key == null
            ? null
            : ref.watch(readAloudHighlightProvider(key)),
      ),
    );
  }
}
