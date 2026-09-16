import 'package:flutter/material.dart';

/// Ícono, título, mensaje opcional y una acción opcional, para cualquier
/// "acá no hay nada todavía" de la app: la biblioteca recién estrenada, una
/// conversación del chat sin empezar, el repaso del día ya terminado.
///
/// El ícono va sobre un fondo circular con degradé suave en vez de suelto
/// sobre la pantalla: le da presencia sin necesitar una ilustración de
/// verdad, que pesaría más en tiempo de armado del que vale una pantalla
/// que casi nadie mira dos veces. Entra con una animación breve, para que
/// la pantalla no salte de golpe de "cargando" a "vacío".
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Los dos juntos o ninguno: una acción sin qué hacer, o un botón mudo, no
  /// tienen sentido.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        colors.primaryContainer.withValues(alpha: 0.9),
                        colors.primaryContainer.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 40, color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    message!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 24),
                  FilledButton.tonal(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
