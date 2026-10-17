import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_organize/domain/services/word_diff.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_review_cards.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/reference/domain/services/reference_draft.dart';
import 'package:sinapsis/features/reference/presentation/reference_presentation.dart';
import 'package:sinapsis/features/suggestions/domain/entities/correction_review_item.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El encabezado de «Revisión» (F33, «Revisar con otro modelo»): cuántas
/// correcciones esperan, qué son, y las dos acciones en lote.
class AiCorrectionsHeader extends StatelessWidget {
  const AiCorrectionsHeader({
    required this.count,
    required this.onAcceptAll,
    required this.onDiscardAll,
    super.key,
  });

  final int count;
  final VoidCallback? onAcceptAll;
  final VoidCallback? onDiscardAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(l10n.aiCorrectionsTitle, style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Badge(
                  key: ValueKey(count),
                  backgroundColor: scheme.primary,
                  textColor: scheme.onPrimary,
                  label: Text('$count'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            l10n.aiCorrectionsHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                key: const Key('ai-corrections-accept-all'),
                onPressed: onAcceptAll,
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(l10n.aiReviewAcceptAll),
              ),
              TextButton.icon(
                key: const Key('ai-corrections-discard-all'),
                onPressed: onDiscardAll,
                icon: const Icon(Icons.clear_all, size: 18),
                label: Text(l10n.aiReviewDiscardAll),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Las correcciones de un elemento: su título —que lo abre—, una fila por
/// corrección con el antes y el después, y aceptar todas las del elemento si
/// hay más de una.
class AiCorrectionItemCard extends StatelessWidget {
  const AiCorrectionItemCard({
    required this.item,
    required this.hidden,
    required this.onAccept,
    required this.onDiscard,
    required this.onAcceptItem,
    this.onOpen,
    super.key,
  });

  final CorrectionReviewItem item;

  /// Las ya resueltas para la persona que la base todavía no sacó.
  final Set<String> hidden;
  final ValueChanged<CorrectionSuggestion> onAccept;
  final ValueChanged<CorrectionSuggestion> onDiscard;

  /// Acepta las que se ven de este elemento.
  final ValueChanged<List<CorrectionSuggestion>> onAcceptItem;

  /// Abre el elemento; `null` si ya se está mirando solo ese.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = [
      for (final correction in item.corrections)
        if (!hidden.contains(correction.id)) correction,
    ];

    return AiCollapse(
      visible: visible.isNotEmpty,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          key: Key('ai-corrections-item-${item.itemId}'),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.itemTitle,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onOpen != null)
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
              for (final (index, correction) in item.corrections.indexed)
                AiCollapse(
                  key: ValueKey(correction.id),
                  visible: !hidden.contains(correction.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (index > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      _CorrectionRow(
                        correction: correction,
                        onAccept: () => onAccept(correction),
                        onDiscard: () => onDiscard(correction),
                      ),
                    ],
                  ),
                ),
              if (visible.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      key: Key('ai-corrections-accept-item-${item.itemId}'),
                      onPressed: () => onAcceptItem(visible),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: Text(l10n.aiCorrectionsAcceptItem(visible.length)),
                    ),
                  ),
                )
              else
                const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una corrección: qué propone y quién, el antes y el después resaltados, el
/// porqué, y aceptar o descartar.
class _CorrectionRow extends StatelessWidget {
  const _CorrectionRow({
    required this.correction,
    required this.onAccept,
    required this.onDiscard,
  });

  final CorrectionSuggestion correction;
  final VoidCallback onAccept;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final after = correction.after;
    final removes = after == null;
    final model = correction.model;

    return Padding(
      key: Key('ai-correction-${correction.id}'),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                removes ? Icons.delete_sweep_outlined : Icons.auto_fix_high,
                size: 18,
                color: removes ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _correctionTitle(l10n, correction, removes: removes),
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (model != null) _ModelChip(model: model),
            ],
          ),
          const SizedBox(height: 10),
          ...switch (correction.subject) {
            CorrectionSubject.flashcard => [
              _DiffField(
                label: l10n.aiCorrectionQuestion,
                before: correction.before[FlashcardCorrectionField.front] ?? '',
                after: after?[FlashcardCorrectionField.front],
              ),
              const SizedBox(height: 8),
              _DiffField(
                label: l10n.aiCorrectionAnswer,
                before: correction.before[FlashcardCorrectionField.back] ?? '',
                after: after?[FlashcardCorrectionField.back],
              ),
            ],
            CorrectionSubject.property => [
              _DiffField(
                label: l10n.aiCorrectionPropertyValue,
                before: correction.before[PropertyCorrectionField.value] ?? '',
                after: after?[PropertyCorrectionField.value],
              ),
            ],
            CorrectionSubject.space => [
              _DiffField(
                label: l10n.aiCorrectionSpace,
                before: correction.before[SpaceCorrectionField.name] ?? '',
                after: after?[SpaceCorrectionField.name],
              ),
            ],
            CorrectionSubject.reference => [
              _DiffField(
                label: _referenceFieldLabel(l10n, correction),
                before: correction.before[ReferenceCorrectionField.value] ?? '',
                after: after?[ReferenceCorrectionField.value],
              ),
            ],
            CorrectionSubject.mapIntro => [
              _DiffField(
                label: l10n.aiCorrectionMapIntro,
                before: correction.before[MapIntroCorrectionField.text] ?? '',
                after: after?[MapIntroCorrectionField.text],
              ),
            ],
            CorrectionSubject.relation => [
              _DiffField(
                label: l10n.aiCorrectionRelationKind,
                before: _kindLabel(
                  l10n,
                  correction.before[RelationCorrectionField.kind],
                ),
                after: after == null
                    ? null
                    : _kindLabel(l10n, after[RelationCorrectionField.kind]),
              ),
              const SizedBox(height: 8),
              _DiffField(
                label: l10n.aiCorrectionRelationNote,
                before: correction.before[RelationCorrectionField.note] ?? '',
                after: after?[RelationCorrectionField.note],
              ),
            ],
          },
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  correction.reason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: Key('ai-correction-discard-${correction.id}'),
                onPressed: onDiscard,
                child: Text(l10n.aiReviewDiscard),
              ),
              const SizedBox(width: 4),
              FilledButton.tonal(
                key: Key('ai-correction-accept-${correction.id}'),
                onPressed: onAccept,
                child: Text(l10n.aiReviewAccept),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Qué propone [correction]: corregir o sacar, y qué.
String _correctionTitle(
  AppLocalizations l10n,
  CorrectionSuggestion correction, {
  required bool removes,
}) {
  return switch ((correction.subject, correction.label)) {
    (CorrectionSubject.flashcard, _) =>
      removes ? l10n.aiCorrectionRemoveCard : l10n.aiCorrectionFixCard,
    (CorrectionSubject.relation, null) =>
      removes
          ? l10n.aiCorrectionRemoveRelationPlain
          : l10n.aiCorrectionFixRelationPlain,
    (CorrectionSubject.relation, final String title) =>
      removes
          ? l10n.aiCorrectionRemoveRelation(title)
          : l10n.aiCorrectionFixRelation(title),
    // La categoría va siempre en el antes: es parte de lo que vio el modelo.
    (CorrectionSubject.property, _) =>
      removes
          ? l10n.aiCorrectionRemoveProperty(
              correction.before[PropertyCorrectionField.category] ?? '',
            )
          : l10n.aiCorrectionFixProperty(
              correction.before[PropertyCorrectionField.category] ?? '',
            ),
    (CorrectionSubject.space, _) =>
      removes ? l10n.aiCorrectionRemoveSpace : l10n.aiCorrectionFixSpace,
    (CorrectionSubject.reference, _) =>
      removes
          ? l10n.aiCorrectionClearReference(
              _referenceFieldLabel(l10n, correction),
            )
          : l10n.aiCorrectionFixReference(
              _referenceFieldLabel(l10n, correction),
            ),
    // Una introducción no se saca: es parte del índice del tema.
    (CorrectionSubject.mapIntro, _) => l10n.aiCorrectionFixMapIntro,
  };
}

/// Cómo se llama el dato de la referencia que corrige [correction], como en
/// el formulario de la referencia: según la clase de obra, el contenedor de
/// un artículo es la revista.
String _referenceFieldLabel(
  AppLocalizations l10n,
  CorrectionSuggestion correction,
) {
  final name = correction.before[ReferenceCorrectionField.field];
  final field = switch (AiChangedField.values.asNameMap()[name]) {
    AiChangedField.containerTitle => ReferenceField.container,
    AiChangedField.publisher => ReferenceField.publisher,
    AiChangedField.publisherPlace => ReferenceField.place,
    AiChangedField.edition => ReferenceField.edition,
    AiChangedField.volume => ReferenceField.volume,
    AiChangedField.issue => ReferenceField.issue,
    AiChangedField.pages => ReferenceField.pages,
    AiChangedField.isbn => ReferenceField.isbn,
    AiChangedField.issn => ReferenceField.issn,
    AiChangedField.doi => ReferenceField.doi,
    _ => null,
  };
  final type = ReferenceType.values
      .asNameMap()[correction.before[ReferenceCorrectionField.type]];
  return field?.label(l10n, type) ?? name ?? '';
}

/// El nombre del tipo de vínculo guardado como [name].
String _kindLabel(AppLocalizations l10n, String? name) =>
    RelationKind.values.asNameMap()[name]?.shortLabel(l10n) ?? name ?? '';

/// Quién propone la corrección: el modelo que revisó, con el ✨.
class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.model});

  final String model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = AppLocalizations.of(
      context,
    )!.aiCorrectionBy(modelLabel(model));

    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 12,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                modelLabel(model),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un dato de lo corregido —la pregunta, la respuesta—: igual, se muestra tal
/// cual; cambiado, el antes con lo que se va tachado y el después con lo que
/// llega resaltado; sin [after] —se saca—, el antes tachado entero.
class _DiffField extends StatelessWidget {
  const _DiffField({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final String before;
  final String? after;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium!;
    final removedStyle = body.copyWith(
      color: scheme.onErrorContainer,
      backgroundColor: scheme.errorContainer,
      decoration: TextDecoration.lineThrough,
      decorationColor: scheme.onErrorContainer,
    );
    final addedStyle = body.copyWith(
      color: scheme.onPrimaryContainer,
      backgroundColor: scheme.primaryContainer,
      fontWeight: FontWeight.w600,
    );
    final changedTo = after;

    final Widget content;
    if (changedTo == null) {
      content = Text(before, style: removedStyle);
    } else if (changedTo.trim() == before.trim()) {
      content = Text(changedTo, style: body);
    } else {
      final diff = wordDiff(before, changedTo);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: l10n.aiCorrectionBefore,
            child: Text.rich(
              TextSpan(
                children: [
                  for (final segment in diff.before)
                    TextSpan(
                      text: segment.text,
                      style: segment.kind == DiffKind.removed
                          ? removedStyle
                          : body.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Icon(
              Icons.arrow_downward,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Semantics(
            label: l10n.aiCorrectionAfter,
            child: Text.rich(
              TextSpan(
                children: [
                  for (final segment in diff.after)
                    TextSpan(
                      text: segment.text,
                      style: segment.kind == DiffKind.added ? addedStyle : body,
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: content,
        ),
      ],
    );
  }
}
