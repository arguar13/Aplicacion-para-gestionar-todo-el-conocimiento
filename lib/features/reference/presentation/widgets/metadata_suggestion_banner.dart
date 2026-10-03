import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/reference/domain/services/reference_draft.dart';
import 'package:sinapsis/features/reference/presentation/reference_presentation.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El aviso de una sugerencia de referencia (F15, D12): qué se encontró, en
/// una línea, y sus dos acciones —usar, que completa lo que la referencia
/// todavía no tenía, o descartar—.
///
/// El mismo widget aparece en la tarjeta «Referencia» del detalle y en la
/// tarjeta de la Bandeja: es la misma sugerencia vista desde dos lugares, y
/// aceptarla o descartarla en cualquiera de los dos la saca de los dos —es
/// una sola fila de la base, no una copia por pantalla.
class MetadataSuggestionBanner extends ConsumerStatefulWidget {
  const MetadataSuggestionBanner({required this.suggestion, super.key});

  final MetadataSuggestion suggestion;

  @override
  ConsumerState<MetadataSuggestionBanner> createState() =>
      _MetadataSuggestionBannerState();
}

class _MetadataSuggestionBannerState
    extends ConsumerState<MetadataSuggestionBanner> {
  /// Mientras se resuelve, un segundo toque no la vuelve a mandar —mismo
  /// criterio que `SuggestedPropertyChips`—.
  var _busy = false;

  Future<void> _resolve(
    Future<Either<Failure, dynamic>> Function(String id) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);

    final result = await action(widget.suggestion.id);
    if (!mounted) return;
    setState(() => _busy = false);

    final failure = result.getLeft().toNullable();
    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              failure.localizedMessage(AppLocalizations.of(context)!),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = extractedMetadataSummary(l10n, widget.suggestion.extracted);
    final repository = ref.read(suggestionRepositoryProvider);

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.referenceSuggestionBanner,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('metadata-suggestion-discard'),
                  onPressed: _busy ? null : () => _resolve(repository.reject),
                  child: Text(l10n.referenceSuggestionDiscard),
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  key: const Key('metadata-suggestion-use'),
                  onPressed: _busy ? null : () => _resolve(repository.accept),
                  child: Text(l10n.referenceSuggestionUse),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Qué trae [extracted], en una línea —«Autores · DOI · Editorial»—: no
/// repite los valores, esos ya se ven al usarla; solo dice qué se halló.
///
/// Pública para «Para revisar» (F27), que muestra la misma sugerencia en una
/// fila y la tiene que describir con las mismas palabras.
String extractedMetadataSummary(
  AppLocalizations l10n,
  ExtractedMetadata extracted,
) {
  final reference = extracted.reference;
  final parts = <String>[
    if (reference.contributors.isNotEmpty)
      ContributorRole.author.listLabel(l10n),
    if (extracted.publishedAt != null) l10n.referenceDateTitle,
    for (final field in ReferenceField.values)
      if (_hasValue(reference, field)) field.label(l10n, reference.type),
  ];
  return parts.join(' · ');
}

bool _hasValue(ReferenceData reference, ReferenceField field) =>
    switch (field) {
      ReferenceField.container => reference.containerTitle != null,
      ReferenceField.publisher => reference.publisher != null,
      ReferenceField.place => reference.publisherPlace != null,
      ReferenceField.edition => reference.edition != null,
      ReferenceField.volume => reference.volume != null,
      ReferenceField.issue => reference.issue != null,
      ReferenceField.pages => reference.pages != null,
      ReferenceField.isbn => reference.isbn != null,
      ReferenceField.issn => reference.issn != null,
      ReferenceField.doi => reference.doi != null,
      ReferenceField.accessed => reference.accessedAt != null,
      ReferenceField.citationKey => reference.citationKey != null,
    };
