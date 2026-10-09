import 'package:flutter/material.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcards_by_parts.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_form_cloze_preview.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Revisar las frases con huecos que propuso la IA antes de guardar nada (F31):
/// cada una se puede aceptar o descartar por separado, y se ve cómo queda su
/// primera tarjeta. Devuelve las aceptadas, o `null` si se cancela.
class ClozeDraftReviewDialog extends StatefulWidget {
  const ClozeDraftReviewDialog({required this.drafts, super.key});

  final List<PartDraft> drafts;

  @override
  State<ClozeDraftReviewDialog> createState() => _ClozeDraftReviewDialogState();
}

class _ClozeDraftReviewDialogState extends State<ClozeDraftReviewDialog> {
  late final _accepted = List<bool>.filled(widget.drafts.length, true);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.cardFormAiReviewTitle),
      content: SizedBox(
        width: 420,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.drafts.length,
          itemBuilder: (context, index) {
            final parsed = parseCloze(widget.drafts[index].draft.front);
            return CheckboxListTile(
              value: _accepted[index],
              onChanged: (value) =>
                  setState(() => _accepted[index] = value ?? false),
              title: ClozeQuestionText(
                segments: parsed.questionSegmentsFor(parsed.numbers.first),
              ),
              subtitle: Text(l10n.cardFormClozeCount(parsed.numbers.length)),
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
