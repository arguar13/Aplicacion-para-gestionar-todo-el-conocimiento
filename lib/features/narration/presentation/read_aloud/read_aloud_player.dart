import 'package:flutter/material.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El lado del botón redondo del lector.
const readAloudButtonSize = 56.0;

/// El botón redondo del lector en voz alta (F25), abajo a la derecha: empieza
/// a leer el texto de la pantalla. Aparece solo mientras no se lee nada; lo
/// que suena se maneja desde el reproductor anclado (F47, paso 2), y el marco
/// de lectura (paso 1) lo reemplaza en los lectores por su propio botón.
class ReadAloudButton extends StatelessWidget {
  const ReadAloudButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: readAloudButtonSize,
      child: FloatingActionButton(
        key: const Key('read-aloud-button'),
        // Por encima del `Navigator`: no hay ruta con la que volar.
        heroTag: null,
        tooltip: l10n.readAloudTooltip,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: const CircleBorder(),
        onPressed: onPressed,
        child: const Icon(Icons.record_voice_over_rounded),
      ),
    );
  }
}
