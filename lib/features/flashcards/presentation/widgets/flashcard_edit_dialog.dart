import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Pide la pregunta y la respuesta de una tarjeta. Devuelve `(pregunta,
/// respuesta)` o `null` si se cancela; no valida: eso lo hace quien la crea.
///
/// [initialBack] pone algo escrito en la respuesta —el fragmento que se
/// seleccionó al crear la tarjeta desde la lectura (F11)—, para que la persona
/// solo tenga que escribir la pregunta, y pueda cambiarlo si quiere.
///
/// Con [card] edita una que ya existe (F27): arranca con su pregunta y su
/// respuesta, y el título lo dice. Guardarla es asunto de quien llama
/// (`FlashcardRepository.update`).
Future<(String, String)?> showFlashcardEditDialog(
  BuildContext context, {
  String? initialBack,
  Flashcard? card,
}) {
  return showDialog<(String, String)>(
    context: context,
    builder: (context) =>
        _FlashcardEditDialog(initialBack: initialBack, card: card),
  );
}

class _FlashcardEditDialog extends StatefulWidget {
  const _FlashcardEditDialog({this.initialBack, this.card});

  final String? initialBack;
  final Flashcard? card;

  @override
  State<_FlashcardEditDialog> createState() => _FlashcardEditDialogState();
}

class _FlashcardEditDialogState extends State<_FlashcardEditDialog> {
  late final _frontController = TextEditingController(text: widget.card?.front);
  late final _backController = TextEditingController(
    text: widget.card?.back ?? widget.initialBack,
  );

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
      title: Text(
        widget.card == null
            ? l10n.flashcardsAddAction
            : l10n.flashcardsEditAction,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _frontController,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(hintText: l10n.flashcardsFrontHint),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _backController,
            minLines: 1,
            maxLines: 6,
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
