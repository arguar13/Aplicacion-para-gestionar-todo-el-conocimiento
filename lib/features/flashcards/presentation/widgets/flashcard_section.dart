import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las tarjetas de repaso de un elemento: la lista, agregar una a mano, y
/// generarlas con el modelo de lenguaje a partir del contenido.
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
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const _FlashcardEditDialog(),
    );
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

  Future<void> _generateWithAi() async {
    final l10n = AppLocalizations.of(context)!;
    final content = widget.item.searchableText.trim();
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
      await repository.create(
        itemId: widget.item.id,
        front: draft.front,
        back: draft.back,
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

class _FlashcardTile extends StatelessWidget {
  const _FlashcardTile({required this.card, required this.onDelete});

  final Flashcard card;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(card.front, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(card.back, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: onDelete,
      ),
    );
  }
}

class _FlashcardEditDialog extends StatefulWidget {
  const _FlashcardEditDialog();

  @override
  State<_FlashcardEditDialog> createState() => _FlashcardEditDialogState();
}

class _FlashcardEditDialogState extends State<_FlashcardEditDialog> {
  final _frontController = TextEditingController();
  final _backController = TextEditingController();

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.flashcardsAddAction),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _frontController,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.flashcardsFrontHint),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _backController,
            decoration: InputDecoration(hintText: l10n.flashcardsBackHint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop((_frontController.text, _backController.text)),
          child: Text(l10n.detailSave),
        ),
      ],
    );
  }
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
