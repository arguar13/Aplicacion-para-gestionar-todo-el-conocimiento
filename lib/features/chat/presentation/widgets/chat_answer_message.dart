import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_answer.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_answer_actions.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_citations.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_message_menu.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una respuesta ya guardada (F42), a todo lo ancho y sin burbuja: el texto
/// con formato, el aviso si algo falló, «Fuentes» plegable y las acciones.
///
/// Lo de siempre, en su lugar nuevo (decisión D):
/// - lo que alcanzó a escribir antes de un error se ve igual, con el aviso
///   debajo (F30);
/// - sin el modelo, el chat es un buscador: las fuentes son la respuesta, con
///   su explicación, y no se pliegan;
/// - sin nada encontrado, lo dice.
class ChatAnswerMessage extends StatelessWidget {
  const ChatAnswerMessage({
    required this.message,
    required this.sourceKey,
    this.onRegenerate,
    super.key,
  });

  final PersistedChatMessage message;
  final String sourceKey;

  /// Ver [ChatAnswerActions.onRegenerate].
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = message.error;
    final hasText = message.text.isNotEmpty;

    // Sobre su propio fondo, no en el rojo del tema sobre el papel: ese no
    // llega a leerse bien (AA) en todos los temas claros.
    Widget errorNotice(String text) => DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasText) ...[
          Semantics(
            onLongPressHint: l10n.chatMessageOptionsHint,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () {
                Feedback.forLongPress(context);
                unawaited(
                  showChatMessageMenu(
                    context,
                    text: message.text,
                    readable: chatAnswerPlainText(message.text),
                  ),
                );
              },
              child: ChatAnswerBody(
                text: message.text,
                sourceKey: sourceKey,
                sources: message.sources,
              ),
            ),
          ),
          if (error != null) ...[const SizedBox(height: 8), errorNotice(error)],
          if (message.sources.isNotEmpty) ...[
            const SizedBox(height: 10),
            ChatSourcesSection(sources: message.sources),
          ],
        ] else if (error != null)
          errorNotice(error)
        else if (message.sources.isNotEmpty) ...[
          Text(
            l10n.chatSourcesOnlyExplanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ChatSourcesSection(sources: message.sources, alwaysOpen: true),
        ] else
          Text(l10n.chatNoSourcesFound, style: theme.textTheme.bodyMedium),
        if (hasText || onRegenerate != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ChatAnswerActions(
                message: message,
                sourceKey: sourceKey,
                onRegenerate: onRegenerate,
              ),
            ),
          ),
      ],
    );
  }
}
