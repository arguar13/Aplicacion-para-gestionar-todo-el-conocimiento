import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';

/// Muestra una nota de bloques ya guardada, de solo lectura.
///
/// Aparte del editor a propósito: leer no necesita controladores de texto,
/// selección de tipo ni reordenamiento — es una lista de widgets simples,
/// cada uno resuelto según el tipo del bloque que le tocó.
class BlockView extends StatelessWidget {
  const BlockView({required this.blocks, super.key});

  final List<ContentBlock> blocks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks) ...[
          _BlockLine(block: block),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _BlockLine extends StatelessWidget {
  const _BlockLine({required this.block});

  final ContentBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return switch (block) {
      ParagraphBlock(:final text) => Text(
        text,
        style: theme.textTheme.bodyLarge,
      ),
      HeadingBlock(:final text, :final level) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          style: level <= 1
              ? theme.textTheme.headlineSmall
              : theme.textTheme.titleLarge,
        ),
      ),
      BulletItemBlock(:final text) => _ListLine(bullet: '•', text: text),
      NumberedItemBlock(:final text) => _ListLine(bullet: '—', text: text),
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
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
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
        child: Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    };
  }
}

class _ListLine extends StatelessWidget {
  const _ListLine({required this.bullet, required this.text});

  final String bullet;
  final String text;

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
        Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
      ],
    );
  }
}
