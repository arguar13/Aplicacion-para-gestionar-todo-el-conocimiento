import 'package:flutter/material.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcards_by_parts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Revisar lo que propuso la IA antes de guardar nada: cada borrador se
/// puede aceptar o descartar por separado, nunca se guarda todo el lote a
/// ciegas. Devuelve los aceptados, o `null` si se cancela.
class FlashcardDraftReviewDialog extends StatefulWidget {
  const FlashcardDraftReviewDialog({required this.drafts, super.key});

  final List<PartDraft> drafts;

  @override
  State<FlashcardDraftReviewDialog> createState() =>
      _FlashcardDraftReviewDialogState();
}

class _FlashcardDraftReviewDialogState
    extends State<FlashcardDraftReviewDialog> {
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
