import 'package:flutter/material.dart';

/// El aviso de que el modelo no puede contestar todavía —falta bajarlo, una
/// clave, la cuota— con el botón que lo resuelve (F42; antes, una franja gris
/// arriba de todo).
///
/// En el chat vacío es una tarjeta tranquila debajo de las sugerencias; en
/// una conversación, [compact]: una línea arriba del campo, para que siga a
/// la vista sin comerse la charla.
class ChatModelNotice extends StatelessWidget {
  const ChatModelNotice({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.icon,
    this.compact = false,
    super.key,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  /// Qué falta: la descarga, una cuenta, la cuota.
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final badge = Container(
      padding: EdgeInsets.all(compact ? 6 : 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: compact ? 16 : 20,
        color: scheme.onSecondaryContainer,
      ),
    );

    if (compact) {
      return Padding(
        key: const Key('chat-model-notice'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
            child: Row(
              children: [
                badge,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      key: const Key('chat-model-notice'),
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              badge,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonal(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}
