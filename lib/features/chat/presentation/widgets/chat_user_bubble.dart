import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_attachments.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_message_menu.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que escribió la persona (F42): una burbuja a la derecha, con lo que
/// adjuntó arriba.
///
/// Mantenerla apretada ofrece copiar, seleccionar una parte y **editar y
/// reenviar**: la burbuja se vuelve un campo con el texto, y «Reenviar» lo
/// manda corregido —con los mismos adjuntos— como un mensaje nuevo al final.
/// Lo ya conversado no se toca: el modelo lo sigue teniendo en cuenta, y el
/// historial queda como pasó.
class ChatUserBubble extends StatefulWidget {
  const ChatUserBubble({
    required this.message,
    required this.sourceKey,
    this.onResend,
    super.key,
  });

  final PersistedChatMessage message;

  /// Con qué nombre lo conoce el lector en voz alta (F25).
  final String sourceKey;

  /// Manda [PersistedChatMessage.text] corregido; `null` mientras se espera
  /// una respuesta, cuando no se puede mandar nada.
  final void Function(String text)? onResend;

  @override
  State<ChatUserBubble> createState() => _ChatUserBubbleState();
}

class _ChatUserBubbleState extends State<ChatUserBubble> {
  TextEditingController? _editing;

  @override
  void dispose() {
    _editing?.dispose();
    super.dispose();
  }

  void _startEditing() => setState(
    () => _editing = TextEditingController(text: widget.message.text),
  );

  void _stopEditing() {
    final editing = _editing;
    setState(() => _editing = null);
    // Se suelta después del cuadro: el campo todavía lo usa en este.
    WidgetsBinding.instance.addPostFrameCallback((_) => editing?.dispose());
  }

  void _resend() {
    final text = _editing?.text.trim() ?? '';
    final resend = widget.onResend;
    if (text.isEmpty || resend == null) return;
    _stopEditing();
    resend(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = widget.message;
    final editing = _editing;

    final bubble = editing != null
        ? _EditBox(
            controller: editing,
            onCancel: _stopEditing,
            onSend: widget.onResend == null ? null : _resend,
          )
        : Semantics(
            onLongPressHint: l10n.chatMessageOptionsHint,
            child: GestureDetector(
              onLongPress: () {
                Feedback.forLongPress(context);
                unawaited(
                  showChatMessageMenu(
                    context,
                    text: message.text,
                    readable: message.text,
                    onEdit: widget.onResend == null ? null : _startEditing,
                  ),
                );
              },
              child: Container(
                key: Key('chat-user-bubble-${message.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: const BorderRadiusDirectional.only(
                    topStart: Radius.circular(20),
                    topEnd: Radius.circular(20),
                    bottomStart: Radius.circular(20),
                    bottomEnd: Radius.circular(6),
                  ),
                ),
                child: ReadAloudText(
                  message.text,
                  sourceKey: widget.sourceKey,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (message.attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final attachment in message.attachments)
                  ChatAttachmentTile(attachment: attachment),
              ],
            ),
          ),
        if (message.text.isNotEmpty || editing != null)
          LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ConstrainedBox(
                // Lo de la persona no ocupa todo el ancho: se lee como una
                // burbuja de su lado, y la respuesta, a lo ancho, como el
                // texto.
                constraints: BoxConstraints(
                  maxWidth: editing != null
                      ? constraints.maxWidth
                      : constraints.maxWidth * 0.82,
                ),
                child: bubble,
              ),
            ),
          ),
      ],
    );
  }
}

/// La burbuja mientras se edita: el campo y «Cancelar» · «Reenviar».
class _EditBox extends StatelessWidget {
  const _EditBox({
    required this.controller,
    required this.onCancel,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onCancel;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      key: const Key('chat-user-edit'),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 8,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
            ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(onPressed: onCancel, child: Text(l10n.commonCancel)),
              FilledButton(
                key: const Key('chat-user-edit-send'),
                onPressed: onSend,
                child: Text(l10n.chatEditResend),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
