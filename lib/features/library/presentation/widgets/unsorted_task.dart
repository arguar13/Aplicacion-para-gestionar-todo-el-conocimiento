import 'package:flutter/material.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «49 elementos sin tema», para qué ordenarlos y «Ordenarlos» (F45, mejora
/// 17): lo que quedó sin tema, como una tarea más.
///
/// Antes era una tarjeta grande arriba de la lista de la Biblioteca (F37), que
/// la empujaba hacia abajo cada vez que se abría. Ahora es una tarea en los
/// dos lugares donde se mira lo pendiente, con la misma cuenta: el panel de
/// estado desplegado (`HealthPanel`, que plegado la muestra como una píldora
/// más) y la lista de «Organizar» de la barra de abajo, que es donde se
/// ordena.
///
/// No cuenta nada: [count] lo trae quien la pone —los dos miran
/// `unsortedCountProvider`—, y sin nada sin tema no la pone. [onOpen] abre la
/// lista para ordenarlos; desde una hoja, primero la cierra.
class UnsortedTask extends StatelessWidget {
  const UnsortedTask({required this.count, required this.onOpen, super.key});

  /// Cuántos elementos no están en ningún tema; más de cero.
  final int count;

  final VoidCallback onOpen;

  /// Desde este ancho, «Ordenarlos» va al costado del texto; más angosto,
  /// debajo, a la derecha, para que el texto no quede en una columna finita.
  static const double _sideBySideWidth = 520;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.folder_off_outlined, size: 20, color: scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.libraryUnsortedTitle(count),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.libraryUnsortedBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final action = FilledButton.tonal(
      key: const Key('unsorted-task-open'),
      onPressed: onOpen,
      child: Text(l10n.libraryUnsortedAction),
    );

    // Un solo grupo para el lector de pantalla: la cuenta, para qué y el
    // botón, juntos.
    return Semantics(
      container: true,
      child: Material(
        key: const ValueKey('unsorted-task'),
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= _sideBySideWidth) {
                return Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 12),
                    action,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  text,
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
