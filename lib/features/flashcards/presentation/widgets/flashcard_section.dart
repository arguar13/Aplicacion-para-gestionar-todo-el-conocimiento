import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_badge.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/source_quote_locator.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_edit_dialog.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/open_flashcard_source.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las tarjetas de repaso de un elemento: la lista, agregar una a mano, y
/// generarlas con el modelo de lenguaje a partir del contenido.
///
/// Desde F27 cada tarjeta se edita, y las que hizo la IA llevan la marca ✨ y
/// se les puede decir que «no era».
class FlashcardSection extends ConsumerStatefulWidget {
  const FlashcardSection({required this.item, super.key});

  final KnowledgeItem item;

  @override
  ConsumerState<FlashcardSection> createState() => _FlashcardSectionState();
}

class _FlashcardSectionState extends ConsumerState<FlashcardSection> {
  var _generating = false;

  Future<void> _addManually() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showFlashcardEditDialog(context);
    if (result == null || !context.mounted) return;

    final (front, back) = result;
    final saved = await ref
        .read(flashcardRepositoryProvider)
        .create(itemId: widget.item.id, front: front, back: back);
    if (!context.mounted) return;

    saved.match(
      (failure) => _showMessage(failure.localizedMessage(l10n)),
      (_) {},
    );
  }

  /// Edita [card]: guardar la adopta si era de la IA (F27). Sin cambios no se
  /// escribe nada.
  Future<void> _edit(Flashcard card) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showFlashcardEditDialog(context, card: card);
    if (result == null || !mounted) return;

    final (front, back) = result;
    if (front.trim() == card.front && back.trim() == card.back) return;
    final saved = await ref
        .read(flashcardRepositoryProvider)
        .update(id: card.id, front: front, back: back);
    if (!mounted) return;

    saved.match(
      (failure) => _showMessage(failure.localizedMessage(l10n)),
      (_) {},
    );
  }

  /// «No era» (F27): la borra, la IA no la vuelve a proponer, y el aviso
  /// ofrece deshacerlo.
  Future<void> _reject(Flashcard card) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(flashcardRepositoryProvider);
    final result = await repository.rejectAiFlashcard(card.id);
    if (!mounted) return;

    result.match((failure) => _showMessage(failure.localizedMessage(l10n)), (
      receipt,
    ) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.flashcardRejected),
            action: SnackBarAction(
              label: l10n.aiRejectionUndo,
              // El aviso puede seguir a la vista después de que esta sección
              // se fue: el repositorio y el mensajero se tomaron antes.
              onPressed: () async {
                final undone = await repository.restoreRejectedFlashcard(
                  receipt,
                );
                undone.match(
                  (failure) => messenger.showSnackBar(
                    SnackBar(content: Text(failure.localizedMessage(l10n))),
                  ),
                  (_) {},
                );
              },
            ),
          ),
        );
    });
  }

  Future<void> _generateWithAi() async {
    final l10n = AppLocalizations.of(context)!;
    // El mismo texto que abre la lectura —la forma principal que no es de
    // bloques—: el rango de una cita tiene que ser de ESE texto para que
    // «Ver en la fuente» caiga en el lugar. Sin él —una nota de bloques—, el
    // texto que se buscó siempre y sin fragmentos.
    final sourceText = extractableRendition(widget.item)?.content;
    final content = (sourceText ?? widget.item.searchableText).trim();
    if (content.isEmpty) {
      _showMessage(l10n.flashcardsNoContentToGenerate);
      return;
    }

    setState(() => _generating = true);

    List<FlashcardDraft> drafts;
    try {
      drafts = await ref
          .read(flashcardGeneratorProvider)
          .generate(content: content);
      // El generador es de terceros (flutter_gemma) y puede fallar de
      // formas sin un tipo propio en Dart —memoria insuficiente, el
      // modelo sin descargar todavía—.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      drafts = const [];
    }

    if (!mounted) return;
    setState(() => _generating = false);
    if (!context.mounted) return;

    if (drafts.isEmpty) {
      _showMessage(l10n.flashcardsGenerationFailed);
      return;
    }

    final accepted = await showDialog<List<FlashcardDraft>>(
      context: context,
      builder: (context) => _FlashcardDraftReviewDialog(drafts: drafts),
    );
    if (accepted == null || accepted.isEmpty || !context.mounted) return;

    final repository = ref.read(flashcardRepositoryProvider);
    for (final draft in accepted) {
      // La cita la escribió el modelo: solo cuenta como el lugar de la fuente
      // si está textual. Si no, la tarjeta se guarda igual, sin fragmento.
      final range = sourceText == null
          ? null
          : locateQuote(sourceText, draft.quote);
      await repository.create(
        itemId: widget.item.id,
        front: draft.front,
        back: draft.back,
        sourceCharStart: range?.start,
        sourceCharEnd: range?.end,
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cards = ref.watch(itemFlashcardsProvider(widget.item.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.flashcardsTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined, size: 20),
              tooltip: l10n.flashcardsGenerateAction,
              onPressed: _generating ? null : _generateWithAi,
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              tooltip: l10n.flashcardsAddAction,
              onPressed: _addManually,
            ),
          ],
        ),
        cards.when(
          loading: () => const SizedBox.shrink(),
          error: (error, stackTrace) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? Text(
                  l10n.flashcardsEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  children: [
                    for (final card in list)
                      _FlashcardTile(
                        card: card,
                        onEdit: () => _edit(card),
                        onReject: () => _reject(card),
                        onDelete: () => ref
                            .read(flashcardRepositoryProvider)
                            .delete(card.id),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Lo que se puede hacer con una tarjeta desde su menú.
enum _CardAction { reject, delete }

class _FlashcardTile extends StatelessWidget {
  const _FlashcardTile({
    required this.card,
    required this.onEdit,
    required this.onReject,
    required this.onDelete,
  });

  final Flashcard card;
  final VoidCallback onEdit;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final front = Text(
      card.front,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: card.isFromAi
          ? Row(
              children: [
                Flexible(child: front),
                const SizedBox(width: 6),
                AiBadge(tooltip: l10n.flashcardMadeByAi),
              ],
            )
          : front,
      subtitle: Text(card.back, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // De dónde salió, si se sabe: abre la fuente en ese fragmento.
          if (card.hasSourceRange)
            IconButton(
              icon: const Icon(Icons.menu_book_outlined, size: 20),
              tooltip: l10n.flashcardsViewSource,
              onPressed: () => openFlashcardSource(context, card),
            ),
          // Una de opción múltiple no se edita acá: su respuesta son las
          // opciones, y este diálogo solo tiene pregunta y respuesta.
          if (card.kind != FlashcardKind.multipleChoice)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: l10n.flashcardsEditAction,
              onPressed: onEdit,
            ),
          // Borrar y «no era» van juntos en un menú: más íconos no entran en
          // la fila de un teléfono junto a la pregunta.
          PopupMenuButton<_CardAction>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (action) => switch (action) {
              _CardAction.reject => onReject(),
              _CardAction.delete => onDelete(),
            },
            itemBuilder: (context) => [
              if (card.isFromAi)
                PopupMenuItem(
                  value: _CardAction.reject,
                  child: _MenuRow(
                    icon: Icons.thumb_down_alt_outlined,
                    label: l10n.aiNotRight,
                  ),
                ),
              PopupMenuItem(
                value: _CardAction.delete,
                child: _MenuRow(
                  icon: Icons.delete_outline,
                  label: l10n.flashcardsDeleteAction,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una opción del menú de una tarjeta: ícono y texto, sin `ListTile` —el
/// detalle cuenta filas por ese widget—.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Flexible(child: Text(label)),
    ],
  );
}

/// Revisar lo que propuso la IA antes de guardar nada: cada borrador se
/// puede aceptar o descartar por separado, nunca se guarda todo el lote a
/// ciegas.
class _FlashcardDraftReviewDialog extends StatefulWidget {
  const _FlashcardDraftReviewDialog({required this.drafts});

  final List<FlashcardDraft> drafts;

  @override
  State<_FlashcardDraftReviewDialog> createState() =>
      _FlashcardDraftReviewDialogState();
}

class _FlashcardDraftReviewDialogState
    extends State<_FlashcardDraftReviewDialog> {
  late final _accepted = List<bool>.filled(widget.drafts.length, true);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.flashcardsReviewTitle),
      content: SizedBox(
        width: 400,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.drafts.length,
          itemBuilder: (context, index) {
            final draft = widget.drafts[index];
            return CheckboxListTile(
              value: _accepted[index],
              onChanged: (value) =>
                  setState(() => _accepted[index] = value ?? false),
              title: Text(draft.front),
              subtitle: Text(draft.back),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop([
            for (var i = 0; i < widget.drafts.length; i++)
              if (_accepted[i]) widget.drafts[i],
          ]),
          child: Text(l10n.flashcardsSaveSelected),
        ),
      ],
    );
  }
}
