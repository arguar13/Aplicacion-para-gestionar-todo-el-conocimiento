import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se ve mientras el modelo prepara la respuesta, antes de su primera
/// palabra (F42): un punto de luz con los colores del tema que respira y gira
/// despacio, y una frase con un brillo que la recorre —«Buscando en tu
/// bóveda…», «Pensando…»—. Reemplaza al círculo que giraba.
///
/// Con «sin animaciones» se queda quieto: el punto y la frase, sin brillo.
/// Para el lector de pantalla es una región viva que dice la frase.
class ChatTypingIndicator extends StatefulWidget {
  const ChatTypingIndicator({required this.mode, super.key});

  final ChatConversationMode mode;

  @override
  State<ChatTypingIndicator> createState() => _ChatTypingIndicatorState();
}

class _ChatTypingIndicatorState extends State<ChatTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final still = MediaQuery.disableAnimationsOf(context);
    final label = widget.mode == ChatConversationMode.vault
        ? l10n.chatThinkingVault
        : l10n.chatThinkingFree;
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final orbSize = MediaQuery.textScalerOf(context).scale(18);

    return Semantics(
      key: const Key('chat-typing'),
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = still ? 0.0 : _controller.value;
          // Respira: crece y achica con una onda suave, una vez por vuelta.
          final breath = 0.85 + 0.15 * math.sin(t * 2 * math.pi);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: orbSize,
                child: Transform.scale(
                  scale: breath,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        transform: GradientRotation(t * 2 * math.pi),
                        colors: [
                          scheme.primary,
                          scheme.tertiary,
                          scheme.secondary,
                          scheme.primary,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.35),
                          blurRadius: 8 * breath,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: still
                    ? Text(label, style: textStyle)
                    : ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            scheme.onSurfaceVariant,
                            scheme.onSurface,
                            scheme.onSurfaceVariant,
                          ],
                          stops: const [0, 0.5, 1],
                          // El brillo cruza de un borde al otro y vuelve a
                          // empezar.
                          begin: Alignment(-3 + 4 * t, 0),
                          end: Alignment(-1 + 4 * t, 0),
                        ).createShader(bounds),
                        child: Text(label, style: textStyle),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
