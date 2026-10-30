import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_badge.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_form.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer_alternatives.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/card_form_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_form_dialog.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/open_flashcard_source.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las tarjetas de repaso de un elemento, para verlas y repasarlas: la lista,
/// y cada una se edita, se rechaza o se borra.
///
/// Desde F27 cada tarjeta se edita, y las que hizo la IA llevan la marca ✨ y
/// se les puede decir que «no era».
///
/// **Se crean desde «Crear»** (F45, paso 7b, mejora 14): las de la IA y las
/// hechas a mano salieron de acá —su ruedita y su «+»— a la hoja del ✨ de
/// arriba, el único lugar donde se crea algo del documento
/// (`createFlashcardsWithAi`, `addFlashcardByHand`).
///
/// En un documento procesado son las suyas, y con [fromSourceItemId], debajo,
/// plegadas, las que la fuente ya tenía: no se mueven ni se copian —siguen en
/// Repasar con su historial, y su «Abrir en el original» lleva al pasaje de
/// la fuente—, solo se ven acá.
class FlashcardSection extends ConsumerStatefulWidget {
  const FlashcardSection({
    required this.item,
    this.fromSourceItemId,
    super.key,
  });

  final KnowledgeItem item;

  /// La fuente de la que salió el documento procesado [item], para mostrar sus
  /// tarjetas en el grupo «De la fuente»; `null` en todo lo demás.
  final String? fromSourceItemId;

  @override
  ConsumerState<FlashcardSection> createState() => _FlashcardSectionState();
}

class _FlashcardSectionState extends ConsumerState<FlashcardSection> {
  /// Edita [card] en su forma (F31): una de huecos se edita como huecos, una de
  /// «escribí la respuesta» como tal. Guardar la adopta si era de la IA (F27).
  /// Sin cambios no se escribe nada.
  Future<void> _edit(Flashcard card) async {
    final l10n = AppLocalizations.of(context)!;
    // Las del mismo elemento que [card]: una de «De la fuente» es de la fuente.
    final siblings =
        ref.read(itemFlashcardsProvider(card.itemId)).valueOrNull ??
        const <Flashcard>[];
    final result = await showCardFormDialog(
      context,
      card: card,
      siblingNumbers: [
        for (final other in siblings)
          if (card.kind == FlashcardKind.cloze &&
              other.kind == FlashcardKind.cloze &&
              (other.id == card.id ||
                  (card.groupId != null && other.groupId == card.groupId)) &&
              other.clozeIndex != null)
            other.clozeIndex!,
      ],
    );
    if (result is! CardFormSubmitted || !mounted) return;

    final repository = ref.read(flashcardRepositoryProvider);
    switch (result.form) {
      case QaCardForm(:final front, :final back):
        if (front.trim() == card.front && back.trim() == card.back) return;
        final saved = await repository.update(
          id: card.id,
          front: front,
          back: back,
        );
        if (!mounted) return;
        saved.match(
          (failure) => _showMessage(failure.localizedMessage(l10n)),
          (_) {},
        );
      case final TypedCardForm typed:
        if (typed.front.trim() == card.front && typed.back == card.back) {
          return;
        }
        final saved = await repository.update(
          id: card.id,
          front: typed.front,
          back: typed.back,
        );
        if (!mounted) return;
        saved.match(
          (failure) => _showMessage(failure.localizedMessage(l10n)),
          (_) {},
        );
      case ClozeCardForm(:final text, :final extra):
        if (text.trim() == card.front && extra.trim() == card.back) return;
        final saved = await ref
            .read(clozeCardEditorProvider)
            .edit(cardId: card.id, text: text, extra: extra);
        if (!mounted) return;
        saved.match((failure) => _showMessage(failure.localizedMessage(l10n)), (
          outcome,
        ) {
          if (outcome.created > 0 || outcome.removed > 0) {
            _showMessage(
              l10n.cardFormClozeEdited(outcome.created, outcome.removed),
            );
          }
        });
      // Estas dos formas no se editan: una es dos tarjetas ya hechas y la otra
      // no tiene botón de editar.
      case BothDirectionsCardForm():
      case MultipleChoiceCardForm():
        return;
    }
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
          AppSnackBar(
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
        Text(
          l10n.flashcardsTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        cards.when(
          loading: () => const SizedBox.shrink(),
          error: (error, stackTrace) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? Text(
                  l10n.f45S7bFlashcardsEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(children: [for (final card in list) _tile(card)]),
        ),
        if (widget.fromSourceItemId case final sourceId?)
          _FromSourceCards(sourceItemId: sourceId, tile: _tile),
      ],
    );
  }

  Widget _tile(Flashcard card) => _FlashcardTile(
    card: card,
    onEdit: () => _edit(card),
    onReject: () => _reject(card),
    onDelete: () => ref.read(flashcardRepositoryProvider).delete(card.id),
  );
}

/// «De la fuente» (F41, decisión K): las tarjetas que ya tenía la fuente de un
/// documento procesado, plegadas, con cuántas son. Se editan, se rechazan y se
/// borran como las demás —son las mismas tarjetas, que siguen en Repasar con
/// su historial—. Sin ninguna, no ocupa lugar.
class _FromSourceCards extends ConsumerWidget {
  const _FromSourceCards({required this.sourceItemId, required this.tile});

  final String sourceItemId;
  final Widget Function(Flashcard card) tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cards =
        ref.watch(itemFlashcardsProvider(sourceItemId)).valueOrNull ??
        const <Flashcard>[];
    if (cards.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      key: const Key('flashcards-from-source'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: const Icon(Icons.local_library_outlined),
      title: Text(l10n.flashcardsFromSource),
      subtitle: Text(
        l10n.flashcardsFromSourceCount(cards.length),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [for (final card in cards) tile(card)],
    );
  }
}

/// Qué se ve de una tarjeta en la lista, según su forma (F31): una de huecos
/// muestra el frente con su hueco tapado y debajo lo que esconde, no el texto
/// con las marcas `{{c1::…}}`; una de «escribí la respuesta», la respuesta sin
/// sus alternativas.
({String title, String subtitle}) _shownText(Flashcard card) {
  switch (card.kind) {
    case FlashcardKind.cloze:
      final index = card.clozeIndex;
      final parsed = parseCloze(card.front);
      if (index == null || !parsed.numbers.contains(index)) {
        return (title: card.front, subtitle: card.back);
      }
      return (
        title: parsed.questionFor(index),
        subtitle: [
          for (final deletion in parsed.deletions)
            if (deletion.number == index) deletion.answer,
        ].join(', '),
      );
    case FlashcardKind.typedAnswer:
      return (
        title: card.front,
        subtitle: TypedAnswerSpec.parse(card.back).answer,
      );
    case FlashcardKind.freeRecall:
    case FlashcardKind.multipleChoice:
    case FlashcardKind.trueFalse:
      return (title: card.front, subtitle: card.back);
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
    final shown = _shownText(card);
    final front = Text(
      shown.title,
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
      subtitle: shown.subtitle.isEmpty
          ? null
          : Text(shown.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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
