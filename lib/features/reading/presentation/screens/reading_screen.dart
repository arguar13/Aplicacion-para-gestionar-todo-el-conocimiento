import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La vista de lectura para destilar: el texto de una fuente para leerlo con
/// calma y sacarle notas.
///
/// "Extraer como nota" es la acción principal y está siempre a la vista, en
/// una barra fija que se activa al seleccionar un fragmento —el menú de
/// selección nativo la deja en segundo lugar y a merced de que el sistema lo
/// muestre bien—. Arriba se cuenta cuántas notas salieron ya de esta fuente, y
/// abajo se listan, cada una con un botón que lleva al fragmento del que salió.
///
/// Puede abrirse ya parada en un fragmento —desde una nota extraída—: [jump] es
/// `[start, end)` del texto, y ahí baja la vista y lo marca un momento.
class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({required this.itemId, this.jump, super.key});

  final String itemId;
  final ({int start, int end})? jump;

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  final _controller = HighlightableTextController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final item = ref.watch(libraryItemProvider(widget.itemId)).valueOrNull;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final rendition = extractableRendition(item);
    final extracted = [
      for (final relation
          in ref.watch(itemRelationsProvider(item.id)).valueOrNull ??
              const <ItemRelation>[])
        if (relation.kind == RelationKind.extractedFrom &&
            relation.direction == RelationDirection.incoming)
          relation,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                l10n.readingExtractedCount(extracted.length),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ),
      body: rendition == null
          ? _NoText(item: item)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HighlightableText(
                        itemId: item.id,
                        renditionId: rendition.id,
                        content: rendition.content,
                        controller: _controller,
                        initialJump: widget.jump,
                        extractFirst: true,
                        markdown: extractedTextIsMarkdown(item.source),
                      ),
                      if (extracted.isNotEmpty)
                        _ExtractedList(
                          relations: extracted,
                          content: rendition.content,
                          onGoTo: (start, end) =>
                              _controller.jumpTo(start: start, end: end),
                        ),
                    ],
                  ),
                ),
              ),
            ),
      // Barra de abajo del Scaffold y no un hijo más del cuerpo: los avisos —
      // "Nota creada" con su "Ver"— se apoyan encima de ella en vez de tapar
      // el botón, y extraer varios fragmentos seguidos no se traba.
      bottomNavigationBar: rendition == null
          ? null
          : _SelectionBar(controller: _controller),
    );
  }
}

/// La barra fija de abajo: con un fragmento seleccionado, las acciones; sin
/// selección, cómo empezar.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.controller});

  final HighlightableTextController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              if (!controller.hasSelection) {
                return Text(
                  l10n.readingSelectHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: controller.extractSelection,
                      icon: const Icon(Icons.content_cut),
                      label: Text(l10n.detailExtractSelection),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: controller.highlightSelection,
                    icon: const Icon(Icons.highlight),
                    label: Text(l10n.detailHighlightSelection),
                  ),
                  const SizedBox(width: 8),
                  // Solo el ícono: con tres acciones con texto la barra no
                  // entra en un teléfono. El menú de selección la dice con
                  // palabras.
                  IconButton.outlined(
                    onPressed: controller.createFlashcardFromSelection,
                    icon: const Icon(Icons.style_outlined),
                    tooltip: l10n.flashcardsFromSelection,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Las notas que salieron de esta fuente, con el fragmento de cada una y un
/// botón para ir a él.
class _ExtractedList extends StatelessWidget {
  const _ExtractedList({
    required this.relations,
    required this.content,
    required this.onGoTo,
  });

  final List<ItemRelation> relations;
  final String content;
  final void Function(int start, int end) onGoTo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          l10n.readingExtractedTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final relation in relations)
          Builder(
            builder: (context) {
              final start = relation.sourceCharStart;
              final end = relation.sourceCharEnd;
              // Un rango que ya no entra en el texto —la forma se regeneró—
              // no lleva a ningún lado: se lista la nota, sin botón.
              final fits =
                  start != null && end != null && end <= content.length;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.content_cut),
                title: Text(relation.otherItemTitle),
                subtitle: fits
                    ? Text(
                        content.substring(start, end),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: fits
                    ? IconButton(
                        icon: const Icon(Icons.my_location),
                        tooltip: l10n.readingGoToFragment,
                        onPressed: () => onGoTo(start, end),
                      )
                    : null,
                onTap: () =>
                    context.push(RoutePaths.itemDetail(relation.otherItemId)),
              );
            },
          ),
      ],
    );
  }
}

/// Una fuente sin texto —todavía se está procesando, o es un archivo sin
/// extraer— no tiene nada para leer: se dice, y se ofrece su detalle.
class _NoText extends StatelessWidget {
  const _NoText({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.readingNoText, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.push(RoutePaths.itemDetail(item.id)),
              child: Text(l10n.readingOpenDetail),
            ),
          ],
        ),
      ),
    );
  }
}
