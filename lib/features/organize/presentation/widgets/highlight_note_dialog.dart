import 'package:flutter/material.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Ver o poner la nota de un resaltado: en blanco al crear uno, con lo que
/// ya tenía al editarlo.
class HighlightNoteDialog extends StatefulWidget {
  const HighlightNoteDialog({
    required this.initialNote,
    required this.excerpt,
    super.key,
  });

  final String? initialNote;
  final String excerpt;

  @override
  State<HighlightNoteDialog> createState() => _HighlightNoteDialogState();
}

class _HighlightNoteDialogState extends State<HighlightNoteDialog> {
  late final _controller = TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.detailHighlightNoteDialogTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.excerpt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: l10n.detailHighlightNoteHint,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.detailSave),
        ),
      ],
    );
  }
}
