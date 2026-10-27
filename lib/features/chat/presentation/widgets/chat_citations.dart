import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre [source] en su lugar (F42): la lectura del elemento parada en el
/// pasaje que se le dio al modelo —el mismo salto que usan las tarjetas y las
/// notas extraídas, que baja hasta el tramo y lo marca un momento—. Una
/// fuente sin pasaje al que anclar (una nota que nunca se fragmentó) abre el
/// detalle del elemento.
void openChatSource(BuildContext context, ChatSource source) {
  final start = source.sourceCharStart;
  final end = source.sourceCharEnd;
  context.push(
    start != null && end != null
        ? RoutePaths.reading(source.itemId, start: start, end: end)
        : RoutePaths.itemDetail(source.itemId),
  );
}

/// Una cita de la bóveda dentro del texto de una respuesta (F42): el «[1]»
/// que escribe el modelo, como un chip con su número. Tocarlo abre la fuente
/// en su lugar.
class ChatCitationChip extends StatelessWidget {
  const ChatCitationChip({
    required this.number,
    required this.source,
    super.key,
  });

  /// El número que escribió el modelo: [source] es la fuente `number - 1`.
  final int number;
  final ChatSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelSmall;

    // Un nodo propio: si no, el párrafo entero se volvería «botón» (F42).
    return Semantics(
      container: true,
      button: true,
      label: l10n.chatCitationSemantics(number, source.itemTitle),
      excludeSemantics: true,
      child: Tooltip(
        message: source.itemTitle,
        excludeFromSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Material(
            color: scheme.secondaryContainer,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key('chat-citation-$number'),
              onTap: () => openChatSource(context, source),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                child: Text(
                  '$number',
                  style: label?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Fuentes», debajo de una respuesta (F42): plegado dice cuántas son; al
/// abrirlo, sus tarjetas, numeradas como los chips del texto.
///
/// Con [alwaysOpen] no se pliega: cuando las fuentes son toda la respuesta
/// —sin el modelo, el chat es un buscador—, esconderlas sería esconder la
/// respuesta.
class ChatSourcesSection extends StatefulWidget {
  const ChatSourcesSection({
    required this.sources,
    this.alwaysOpen = false,
    super.key,
  });

  final List<ChatSource> sources;
  final bool alwaysOpen;

  @override
  State<ChatSourcesSection> createState() => _ChatSourcesSectionState();
}

class _ChatSourcesSectionState extends State<ChatSourcesSection> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (var i = 0; i < widget.sources.length; i++)
        ChatSourceCard(number: i + 1, source: widget.sources[i]),
    ];
    if (widget.alwaysOpen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cards,
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final still = MediaQuery.disableAnimationsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            button: true,
            onTapHint: _open ? l10n.chatSourcesHide : l10n.chatSourcesShow,
            child: InkWell(
              key: const Key('chat-sources-toggle'),
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l10n.chatSourcesHeader(widget.sources.length),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: still
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: still ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: cards,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// La tarjeta de una fuente: su número, el título del elemento y el pasaje.
/// Tocarla abre la fuente en su lugar.
class ChatSourceCard extends StatelessWidget {
  const ChatSourceCard({required this.number, required this.source, super.key});

  final int number;
  final ChatSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openChatSource(context, source),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: ShapeDecoration(
                      color: scheme.secondaryContainer,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      '$number',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.itemTitle, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        source.excerpt,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
