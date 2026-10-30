import 'package:flutter/material.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Escribir una nota para el documento procesado: un campo de varias líneas
/// y «Agregar». Cancelar no suma nada; en blanco, tampoco. Devuelve el texto,
/// o `null`.
///
/// Al triar («¿Qué va a Procesado?») y en «Crear» del documento (F45, paso
/// 7b): la misma nota, escrita a mano, en su sección Notas.
class WriteNoteDialog extends StatefulWidget {
  const WriteNoteDialog({super.key});

  @override
  State<WriteNoteDialog> createState() => _WriteNoteDialogState();
}

class _WriteNoteDialogState extends State<WriteNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    Navigator.of(context).pop(text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.processedTriageNoteDialogTitle),
      content: TextField(
        key: const Key('triage-note-field'),
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: l10n.processedTriageNoteDialogHint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            key: const Key('triage-note-add'),
            onPressed: _controller.text.trim().isEmpty ? null : _add,
            child: Text(l10n.processedTriageNoteDialogAdd),
          ),
        ),
      ],
    );
  }
}
