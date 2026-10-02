import 'package:flutter/material.dart';

/// La marca ✨ de lo que hizo la IA sola (F27): un vínculo, una tarjeta.
///
/// Discreta a propósito —un ícono chico, del color terciario del tema—: dice
/// de quién es sin competir con lo que marca. [tooltip] lo dice en palabras, y
/// el `Tooltip` lo deja también para un lector de pantalla.
class AiBadge extends StatelessWidget {
  const AiBadge({required this.tooltip, super.key});

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Icon(
        Icons.auto_awesome,
        size: 16,
        color: Theme.of(context).colorScheme.tertiary,
      ),
    );
  }
}
