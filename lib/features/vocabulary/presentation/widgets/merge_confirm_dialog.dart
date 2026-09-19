import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Either;
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_operation.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La confirmación previa a fusionar, con cuántos elementos afecta: se
/// calcula al abrirla, sin cambiar nada todavía.
class MergeConfirmDialog extends ConsumerStatefulWidget {
  const MergeConfirmDialog({
    required this.keepId,
    required this.keepLabel,
    required this.discardIds,
    super.key,
  });

  final String keepId;
  final String keepLabel;
  final List<String> discardIds;

  @override
  ConsumerState<MergeConfirmDialog> createState() => MergeConfirmDialogState();
}

class MergeConfirmDialogState extends ConsumerState<MergeConfirmDialog> {
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
