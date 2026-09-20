import 'package:flutter/material.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La barra con lo que se hace con lo marcado: descartarlo o aceptarlo, cada
/// botón con cuántos son.
///
/// La usan la pantalla del lote y la hoja de la Bandeja: las dos aplican igual.
/// Mientras algo se está aplicando, [busy], no deja tocar nada.
class PropertySuggestionActionBar extends StatelessWidget {
  const PropertySuggestionActionBar({
    required this.count,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    super.key,
  });

  final int count;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: Text(l10n.suggestionReviewReject(count)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  child: Text(l10n.suggestionReviewAccept(count)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
