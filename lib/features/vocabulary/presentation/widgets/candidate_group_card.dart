import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Either;
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_operation.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/widgets/vocabulary_feedback.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un grupo de valores que quizá sean el mismo, para fusionar varios en uno
/// con una sola operación: se elige cuál se conserva, se marcan los que se
/// fusionan, y antes de hacerlo se ve a cuántos elementos afecta.
///
/// Solo se preseleccionan los que casi seguro son el mismo —mismo texto o casi
/// igual escrito—. Los que solo comparten palabras con el que se conserva
/// ("Guerra" y "Guerra fría") quedan sin marcar: pueden ser cosas distintas, y
/// eso lo decide quien mira.
class CandidateGroupCard extends ConsumerStatefulWidget {
  const CandidateGroupCard({required this.group, super.key});

  final MergeCandidateGroup group;

  @override
  ConsumerState<CandidateGroupCard> createState() => _CandidateGroupCardState();
}

class _CandidateGroupCardState extends ConsumerState<CandidateGroupCard> {
  late String _keepId = widget.group.suggestedKeep.id;
  late Set<String> _merging = widget.group.probableDuplicatesOf(_keepId);

  VocabularyValueStat get _keep =>
      widget.group.values.firstWhere((v) => v.id == _keepId);

  void _chooseKeep(String id) {
    setState(() {
      _keepId = id;
      // El que pasa a conservarse no se fusiona consigo mismo, y los que
      // casi seguro son el mismo que EL NUEVO se suman a lo ya marcado: el
      // que se conservaba antes suele ser uno de ellos.
      _merging = {..._merging, ...widget.group.probableDuplicatesOf(id)}
        ..remove(id);
    });
  }

  void _toggle(String id, {required bool merge}) {
    setState(() => merge ? _merging.add(id) : _merging.remove(id));
  }

  Future<void> _merge() async {
    // Antes de esperar nada: al terminar, esta tarjeta puede ya no existir.
    final feedback = VocabularyFeedback.of(context, ref);
    final controller = ref.read(vocabularyControllerProvider.notifier);
    final keep = _keep;
    final discardIds = [
      for (final value in widget.group.values)
        if (_merging.contains(value.id)) value.id,
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _MergeConfirmDialog(
        keepId: keep.id,
        keepLabel: keep.label,
        discardIds: discardIds,
      ),
    );
    if (confirmed != true) return;

    feedback.report(
      await controller.merge(keepId: keep.id, discardIds: discardIds),
    );
  }

  String _reasonLabel(AppLocalizations l10n, MergeCandidateReason reason) =>
      switch (reason) {
        MergeCandidateReason.sameText => l10n.vocabularyReasonSameText,
        MergeCandidateReason.contained => l10n.vocabularyReasonContained,
        MergeCandidateReason.similarSpelling => l10n.vocabularyReasonSimilar,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final group = widget.group;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.definitionName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final reason in group.reasons)
                      Chip(
                        label: Text(_reasonLabel(l10n, reason)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final value in group.values)
              _ValueRow(
                value: value,
                isKept: value.id == _keepId,
                isMerging: _merging.contains(value.id),
                onKeep: () => _chooseKeep(value.id),
                onToggle: (merge) => _toggle(value.id, merge: merge),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _merging.isEmpty ? null : _merge,
                child: Text(
                  l10n.vocabularyMergeAction(_merging.length, _keep.label),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.value,
    required this.isKept,
    required this.isMerging,
    required this.onKeep,
    required this.onToggle,
  });

  final VocabularyValueStat value;
  final bool isKept;
  final bool isMerging;
  final VoidCallback onKeep;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Row(
      children: [
        // Un botón con icono y no un `Radio`: `Radio` está migrando a
        // `RadioGroup` en Flutter reciente, y esto es solo "cuál se
        // conserva", sin nada de formulario.
        IconButton(
          tooltip: l10n.vocabularyKeepTooltip,
          onPressed: isKept ? null : onKeep,
          icon: Icon(
            isKept ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: isKept ? theme.colorScheme.primary : null,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: isKept ? FontWeight.w600 : null,
                  ),
                ),
                Text(
                  [
                    l10n.vocabularyUsage(value.usage),
                    if (value.aliasCount > 0)
                      l10n.vocabularyAliasCount(value.aliasCount),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        Tooltip(
          message: l10n.vocabularyMergeCheckTooltip,
          child: Checkbox(
            value: isMerging,
            // El que se conserva no se fusiona consigo mismo.
            onChanged: isKept ? null : (checked) => onToggle(checked ?? false),
          ),
        ),
      ],
    );
  }
}

/// La confirmación previa a fusionar, con cuántos elementos afecta: se
/// calcula al abrirla, sin cambiar nada todavía.
class _MergeConfirmDialog extends ConsumerStatefulWidget {
  const _MergeConfirmDialog({
    required this.keepId,
    required this.keepLabel,
    required this.discardIds,
  });

  final String keepId;
  final String keepLabel;
  final List<String> discardIds;

  @override
  ConsumerState<_MergeConfirmDialog> createState() =>
      _MergeConfirmDialogState();
}

class _MergeConfirmDialogState extends ConsumerState<_MergeConfirmDialog> {
  late final Future<Either<Failure, MergePreview>> _preview = ref
      .read(vocabularyRepositoryProvider)
      .previewMerge(keepId: widget.keepId, discardIds: widget.discardIds);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return FutureBuilder<Either<Failure, MergePreview>>(
      future: _preview,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final preview = result?.toNullable();
        final failure = result?.swap().toNullable();

        final body = switch ((preview, failure)) {
          (final MergePreview preview, _) => l10n.vocabularyMergeConfirmBody(
            preview.valueCount,
            widget.keepLabel,
            preview.affectedItems,
          ),
          (_, final Failure failure) => failure.localizedMessage(l10n),
          _ => l10n.vocabularyMergeCalculating,
        };

        return AlertDialog(
          title: Text(l10n.vocabularyMergeConfirmTitle),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              // Sin el conteo a la vista no se confirma: es justo lo que este
              // diálogo existe para mostrar.
              onPressed: preview == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: Text(l10n.vocabularyMergeConfirmAction),
            ),
          ],
        );
      },
    );
  }
}
