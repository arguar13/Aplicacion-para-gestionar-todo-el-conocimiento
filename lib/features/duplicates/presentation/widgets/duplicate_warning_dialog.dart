import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/services/dedup_fingerprint.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_candidate_selector.dart';
import 'package:sinapsis/features/duplicates/presentation/providers/duplicate_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Antes de guardar un texto ya completo —nota manual o texto pegado, en
/// la captura de texto o al crear una nota nueva en el editor de
/// bloques—, se fija si ya existe algo parecido (F7, deduplicación): con
/// el texto todavía completo en memoria es el único momento en que avisar
/// de inmediato, antes de guardar, tiene sentido — una fuente que hay que
/// traer de la red recién tiene texto después de procesarse, y ahí avisa
/// con una sugerencia pendiente en cambio, no con este diálogo.
///
/// Devuelve el `itemId` con el que fusionar si el usuario eligió
/// "Fusionar", o `null` si no había ningún parecido o si eligió "Guardar
/// aparte" — en los dos casos, seguir guardando tal cual, sin hacer nada
/// más.
Future<String?> checkForDuplicateBeforeSave({
  required BuildContext context,
  required WidgetRef ref,
  required String text,
}) async {
  final normalized = normalizeForDedup(text);
  if (normalized.isEmpty) return null;

  final dedupHash = contentHashOf(normalized);
  final simhash = simhashOf(normalized);
  final candidates = await ref
      .read(duplicateCandidateSelectorProvider)
      .selectCandidatesForFingerprint(dedupHash: dedupHash, simhash: simhash);
  if (candidates.isEmpty) return null;
  if (!context.mounted) return null;

  final choice = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => DuplicateWarningDialog(candidate: candidates.first),
  );

  return (choice ?? false) ? candidates.first.itemId : null;
}

/// "¿Fusionar o guardar aparte?" — ver [checkForDuplicateBeforeSave].
///
/// Sin botón de cancelar ni cierre al tocar afuera: es una decisión, no un
/// aviso que se pueda descartar sin más. No elegir nada equivale a
/// "Guardar aparte" —seguir con el guardado que el usuario ya había
/// pedido es menos sorprendente que dejarlo sin guardar—.
class DuplicateWarningDialog extends StatelessWidget {
  const DuplicateWarningDialog({required this.candidate, super.key});

  final DuplicateCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(
        candidate.matchKind == DuplicateMatchKind.exact
            ? l10n.duplicateWarningTitleExact
            : l10n.duplicateWarningTitleNear,
      ),
      content: Text(l10n.duplicateWarningBody(candidate.title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.duplicateWarningKeepSeparate),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.duplicateWarningMerge),
        ),
      ],
    );
  }
}
