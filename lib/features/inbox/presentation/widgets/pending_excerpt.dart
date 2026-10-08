import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/core/util/transcript_timestamps.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El principio del texto de lo que espera en la Bandeja, como se lee (F30,
/// decisión 68): sin marcas de Markdown ni, en una transcripción, los
/// minutos de cada línea. Nunca un reproductor ni el archivo: la Bandeja
/// trabaja con el texto.
///
/// Es el del elemento; si el elemento no tiene —una publicación sin pie de
/// foto, una página que solo enlaza un PDF— es el de un archivo de su
/// «Contenido», y lo dice. `null` si no hay ninguno que mostrar.
({String text, String? from})? pendingExcerptOf(
  KnowledgeItem item, {
  ({String name, String text})? content,
}) {
  final rendition = extractableRendition(item);
  if (rendition != null) {
    // Solo el principio: una transcripción de horas no hace falta entera
    // para mostrar sus primeras líneas.
    final stored = rendition.content;
    final raw = isTranscriptSource(item.source)
        ? stripTimestamps(
            stored.length > 4000 ? stored.substring(0, 4000) : stored,
          )
        : stored;
    final text = RenderedMarkdown.excerpt(
      raw,
      markdown: extractedTextIsMarkdown(item.source),
    );
    if (text.isNotEmpty) return (text: text, from: null);
  }
  if (content == null) return null;
  final text = RenderedMarkdown.excerpt(content.text, markdown: false);
  return text.isEmpty ? null : (text: text, from: content.name);
}

/// El fragmento de texto de la tarjeta de la Bandeja; ver [pendingExcerptOf].
class PendingExcerpt extends ConsumerWidget {
  const PendingExcerpt({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // El «Contenido» solo se mira si el elemento no tiene texto propio.
    final needsContent = pendingExcerptOf(item) == null;
    final content = needsContent
        ? ref.watch(inboxContentTextProvider(item.id)).valueOrNull
        : null;
    final excerpt = pendingExcerptOf(item, content: content);
    if (excerpt == null) return const SizedBox.shrink();

    final from = excerpt.from;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (from != null) ...[
          Text(
            AppLocalizations.of(context)!.inboxTextFromAttachment(from),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
        ],
        Text(
          excerpt.text,
          key: const Key('pending-excerpt'),
          style: theme.textTheme.bodyMedium,
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
