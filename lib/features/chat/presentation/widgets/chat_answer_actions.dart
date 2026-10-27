import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_feedback.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_message_menu.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_selection_aloud.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los íconos discretos debajo de una respuesta (F42): copiar, escuchar,
/// volver a generar —solo la última— y 👍/👎.
///
/// - **Escuchar** usa el lector flotante de siempre (F25): lee esta respuesta,
///   con lo que suena en amarillo, y se detiene al terminarla. Mientras la
///   lee, el mismo botón la deja de leer.
/// - **👍/👎** se guarda en el teléfono ([chatFeedbackProvider]) y nunca se
///   manda a nadie. Tocar otra vez el marcado lo desmarca.
class ChatAnswerActions extends ConsumerWidget {
  const ChatAnswerActions({
    required this.message,
    required this.sourceKey,
    this.onRegenerate,
    super.key,
  });

  final PersistedChatMessage message;

  /// Con qué nombre conoce el lector a esta respuesta.
  final String sourceKey;

  /// `null` si esta respuesta no se puede volver a generar: no es la última,
  /// o se está esperando otra.
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final hasText = message.text.isNotEmpty;
    final listening = ref.watch(readAloudHighlightProvider(sourceKey)) != null;
    final feedback = ref.watch(
      chatFeedbackProvider.select((all) => all[message.id]),
    );

    Widget action({
      required String key,
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      IconData? selectedIcon,
      bool? selected,
    }) => IconButton(
      key: Key('chat-answer-$key-${message.id}'),
      icon: Icon(icon, size: 20),
      selectedIcon: selectedIcon == null ? null : Icon(selectedIcon, size: 20),
      isSelected: selected,
      tooltip: tooltip,
      color: scheme.onSurfaceVariant,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );

    Future<void> rate(ChatFeedback rating) async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final marking = feedback != rating;
      await ref.read(chatFeedbackProvider.notifier).toggle(message.id, rating);
      if (marking) {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.chatAnswerRatedSnack)));
      }
    }

    return Wrap(
      spacing: 2,
      children: [
        if (hasText) ...[
          action(
            key: 'copy',
            icon: Icons.content_copy_rounded,
            tooltip: l10n.chatAnswerCopy,
            onPressed: () => unawaited(copyChatText(context, message.text)),
          ),
          action(
            key: 'listen',
            icon: listening
                ? Icons.stop_circle_outlined
                : Icons.volume_up_outlined,
            tooltip: listening
                ? l10n.chatAnswerStopListening
                : l10n.chatAnswerListen,
            onPressed: () => unawaited(
              listening
                  ? ref.read(readAloudControllerProvider.notifier).close()
                  : readSelectionAloud(
                      ref,
                      text: message.text,
                      sourceKey: sourceKey,
                      start: 0,
                      end: message.text.length,
                    ),
            ),
          ),
        ],
        if (onRegenerate case final regenerate?)
          action(
            key: 'regenerate',
            icon: Icons.refresh_rounded,
            tooltip: l10n.chatAnswerRegenerate,
            onPressed: regenerate,
          ),
        if (hasText) ...[
          action(
            key: 'good',
            icon: Icons.thumb_up_outlined,
            selectedIcon: Icons.thumb_up,
            selected: feedback == ChatFeedback.good,
            tooltip: l10n.chatAnswerGood,
            onPressed: () => unawaited(rate(ChatFeedback.good)),
          ),
          action(
            key: 'bad',
            icon: Icons.thumb_down_outlined,
            selectedIcon: Icons.thumb_down,
            selected: feedback == ChatFeedback.bad,
            tooltip: l10n.chatAnswerBad,
            onPressed: () => unawaited(rate(ChatFeedback.bad)),
          ),
        ],
      ],
    );
  }
}
