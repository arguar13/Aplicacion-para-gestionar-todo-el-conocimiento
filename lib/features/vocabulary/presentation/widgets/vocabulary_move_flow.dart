import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/widgets/vocabulary_feedback.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Pone [value] bajo [parent] —o en el primer nivel, si [parent] es `null`—
/// con el camino de siempre para lo que cambia una rama entera: una vista
/// previa que valida y cuenta cuánto se mueve, una confirmación que lo dice, y
/// el aviso con «Deshacer».
///
/// Es UN solo camino para todas las entradas —el árbol, arrastrando o por el
/// menú, y la sugerencia de las tarjetas de candidatos—: que mover diga y
/// valide lo mismo, venga de donde venga.
///
/// Devuelve `true` si se movió.
Future<bool> requestVocabularyMove(
  BuildContext context,
  WidgetRef ref, {
  required VocabularyValueStat value,
  required VocabularyValueStat? parent,
}) async {
  // Antes de esperar nada: al terminar, quien lo pidió puede haber cambiado.
  final feedback = VocabularyFeedback.of(context, ref);
  final controller = ref.read(vocabularyControllerProvider.notifier);
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  final preview = await ref
      .read(vocabularyRepositoryProvider)
      .previewMove(valueId: value.id, parentId: parent?.id);
  if (!context.mounted) return false;
  final plan = preview.fold((failure) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    return null;
  }, (plan) => plan);
  if (plan == null) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.vocabularyMoveConfirmTitle),
      content: Text(
        parent == null
            ? l10n.vocabularyMoveToRootConfirmBody(plan.valueCount, value.label)
            : l10n.vocabularyMoveConfirmBody(
                plan.valueCount,
                value.label,
                parent.label,
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.vocabularyMoveConfirmAction),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  final result = await controller.move(valueId: value.id, parentId: parent?.id);
  feedback.report(result);
  return result.isRight();
}
