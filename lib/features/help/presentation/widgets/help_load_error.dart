import 'package:flutter/material.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un texto de la Ayuda que no se pudo leer (F47, paso 7): lo dice y deja
/// volver a intentarlo. No debería pasar —va empaquetado con la app—, pero
/// una pantalla en blanco no explica nada.
class HelpLoadError extends StatelessWidget {
  const HelpLoadError({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.f47P7HelpLoadError,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('help-retry'),
              onPressed: onRetry,
              child: Text(l10n.f47P7HelpRetry),
            ),
          ],
        ),
      ),
    );
  }
}
