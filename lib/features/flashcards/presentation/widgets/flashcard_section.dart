import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_target.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_badge.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcards_by_parts.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_edit_dialog.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/open_flashcard_source.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántas propone el ✨ como mínimo, aunque el texto sea corto: la persona
/// las revisa antes de guardar, y elegir entre algunas más cuesta poco.
const kManualFlashcardsWanted = 5;

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

  /// Cuántas partes del texto lleva leídas el ✨, de cuántas.
  ({int read, int total})? _progress;

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

  /// Propone tarjetas con el modelo de lenguaje y deja que la persona elija
  /// cuáles guardar.
  ///
  /// El texto se lee **por partes** (`generateFlashcardsByParts`, F30): el
  /// modelo acepta unas 2.000 palabras entre todo, y un libro o un video
  /// largo mandado entero fallaba. Cada parte que se lee se ve debajo del
  /// título. Si el modelo falla en el medio, se ofrece lo que alcanzó a
  /// proponer y se dice qué pasó: que falta bajarlo, o que falló.
  Future<void> _generateWithAi() async {
    final l10n = AppLocalizations.of(context)!;
    // El mismo texto que abre la lectura —la forma principal que no es de
    // bloques—: el rango de una cita tiene que ser de ESE texto para que
    // «Ver en la fuente» caiga en el lugar. Sin él —una nota de bloques—, el
    // texto que se buscó siempre y sin fragmentos.
    final sourceText = extractableRendition(widget.item)?.content;
    final content = sourceText ?? widget.item.searchableText;
    if (content.trim().isEmpty) {
      _showMessage(l10n.flashcardsNoContentToGenerate);
      return;
    }

    setState(() {
      _generating = true;
      _progress = null;
    });

    // Lo que el elemento ya tiene no se vuelve a proponer.
    final existing =
        ref.read(itemFlashcardsProvider(widget.item.id)).valueOrNull ??
        const <Flashcard>[];
    final known = {
      for (final card in existing) flashcardRejectionFingerprint(card.front),
    };
    final proposed = <PartDraft>[];
    Object? failure;
    try {
      await generateFlashcardsByParts(
        generator: ref.read(flashcardGeneratorProvider),
        text: content,
        wanted: math.max(kManualFlashcardsWanted, flashcardTargetFor(content)),
        onDraft: (candidate) async {
          if (!known.add(
            flashcardRejectionFingerprint(candidate.draft.front),
          )) {
            return PartDraftOutcome.skipped;
          }
          proposed.add(candidate);
          return PartDraftOutcome.kept;
        },
        onProgress: (read, total) {
          if (mounted) setState(() => _progress = (read: read, total: total));
        },
      );
      // El generador es de terceros (flutter_gemma) y falla de formas sin un
      // tipo propio en Dart —memoria insuficiente, una sesión que se cerró—.
      // Se registra y se le cuenta a la persona; lo que ya propuso, queda.
    } on Object catch (e, stackTrace) {
      failure = e;
      if (e is! ChatModelNotReadyException) {
        ref
            .read(telemetryServiceProvider)
            .recordError(e, stackTrace, hint: 'FlashcardSection: tarjetas IA');
      }
    }

    if (!mounted) return;
    setState(() {
      _generating = false;
      _progress = null;
    });

    if (proposed.isEmpty) {
      _showFailure(failure, l10n, nothing: true);
      return;
    }
    if (failure != null) _showFailure(failure, l10n, nothing: false);

    final accepted = await showDialog<List<PartDraft>>(
      context: context,
      builder: (context) => _FlashcardDraftReviewDialog(drafts: proposed),
    );
    if (accepted == null || accepted.isEmpty || !mounted) return;

    final repository = ref.read(flashcardRepositoryProvider);
    for (final candidate in accepted) {
      // El pasaje del que sale, si la cita se ubicó —aunque el modelo la haya
      // parafraseado—. Si no, la tarjeta se guarda igual, sin fragmento: la
      // persona la leyó y la eligió.
      final anchor = sourceText == null ? null : candidate.anchor;
      final saved = await repository.create(
        itemId: widget.item.id,
        front: candidate.draft.front,
        back: candidate.draft.back,
        sourceCharStart: anchor?.start,
        sourceCharEnd: anchor?.end,
      );
      if (!mounted) return;
      final error = saved.getLeft().toNullable();
      if (error != null) {
        _showMessage(error.localizedMessage(l10n));
        return;
      }
    }
  }

  /// Por qué no hubo tarjetas —o no todas—: falta bajar el modelo, el modelo
  /// falló, o no propuso nada que sirviera.
  void _showFailure(
    Object? failure,
    AppLocalizations l10n, {
    required bool nothing,
  }) {
    if (failure is ChatModelNotReadyException) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.flashcardsModelMissing),
            action: SnackBarAction(
              label: l10n.flashcardsDownloadModel,
              onPressed: () => context.push(RoutePaths.chatModel),
            ),
          ),
        );
      return;
    }
    _showMessage(switch ((failure, nothing)) {
      (null, _) => l10n.flashcardsGenerationEmpty,
      (_, true) => l10n.flashcardsGenerationFailed,
      (_, false) => l10n.flashcardsGenerationPartial,
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
        // Un texto largo se lee por partes: cuál va, para que la espera se
        // entienda.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _generating && (_progress?.total ?? 0) > 1
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.flashcardsReadingPart(
                          math.min(_progress!.read + 1, _progress!.total),
                          _progress!.total,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: _progress!.read / _progress!.total,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
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

  final List<PartDraft> drafts;

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
            final draft = widget.drafts[index].draft;
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
