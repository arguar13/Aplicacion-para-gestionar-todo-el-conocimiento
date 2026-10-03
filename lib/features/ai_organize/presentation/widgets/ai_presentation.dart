import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que dice una cuenta de la IA, parte por parte y sin los ceros: «4
/// vínculos», «6 tarjetas», «3 temas» (F27).
List<String> aiTallyParts(AppLocalizations l10n, AiRunTally tally) => [
  if (tally.relations > 0) l10n.aiTallyRelations(tally.relations),
  if (tally.flashcards > 0) l10n.aiTallyFlashcards(tally.flashcards),
  if (tally.properties > 0) l10n.aiTallyProperties(tally.properties),
];

/// La cuenta en una línea: «4 vínculos · 6 tarjetas · 3 temas». La misma en
/// el detalle, en la confirmación y en el aviso, para que se lea igual en
/// todos lados.
String aiTallyText(AppLocalizations l10n, AiRunTally tally) =>
    aiTallyParts(l10n, tally).join(' · ');

/// El ✨ de la IA en un círculo tonal, del mismo tamaño que los círculos de
/// las franjas del panel de la fuente (F26): lo que identifica de un vistazo
/// que esa fila habla de la IA.
class AiSparkCircle extends StatelessWidget {
  const AiSparkCircle({
    this.size = 32,
    this.icon = Icons.auto_awesome,
    super.key,
  });

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.tertiaryContainer,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.56, color: scheme.onTertiaryContainer),
    );
  }
}

/// La cuenta de una pasada como píldoras tonales —ícono y número—, para la
/// actividad: se leen de un vistazo y no se confunden con un botón.
///
/// No son `Chip`: no se tocan, y un `Chip` promete que sí.
class AiTallyPills extends StatelessWidget {
  const AiTallyPills({required this.tally, super.key});

  final AiRunTally tally;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (tally.relations > 0)
          _Pill(
            icon: Icons.link,
            label: l10n.aiTallyRelations(tally.relations),
          ),
        if (tally.flashcards > 0)
          _Pill(
            icon: Icons.style_outlined,
            label: l10n.aiTallyFlashcards(tally.flashcards),
          ),
        if (tally.properties > 0)
          _Pill(
            icon: Icons.sell_outlined,
            label: l10n.aiTallyProperties(tally.properties),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: scheme.secondaryContainer.withValues(alpha: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onSecondaryContainer),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pregunta antes de deshacer lo de la IA (F27): una pasada o, con
/// [wholeItem], todo lo de un elemento. Dice qué se va a borrar —lo que sigue
/// siendo de la IA, [tally]—, que lo editado queda y que la IA no vuelve a
/// organizar sola ese elemento. Devuelve si la persona confirmó.
Future<bool> confirmAiUndo(
  BuildContext context, {
  required String itemTitle,
  required AiRunTally tally,
  bool wholeItem = false,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.undo),
      title: Text(wholeItem ? l10n.aiUndoItemTitle : l10n.aiUndoRunTitle),
      content: Text(l10n.aiUndoMessage(itemTitle, aiTallyText(l10n, tally))),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('ai-undo-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.aiUndoConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Avisa cómo salió deshacer: lo que se borró, que no quedaba nada de la IA,
/// o por qué falló.
///
/// Recibe el [messenger] y los textos ya tomados: quien deshace espera a la
/// base, y para entonces la pantalla que lo pidió puede haberse ido.
void showAiUndoResult(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  Either<Failure, AiRunTally> result,
) {
  final message = result.match(
    (failure) => failure.localizedMessage(l10n),
    (tally) => tally.isEmpty
        ? l10n.aiUndoNothing
        : l10n.aiUndoDone(aiTallyText(l10n, tally)),
  );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
