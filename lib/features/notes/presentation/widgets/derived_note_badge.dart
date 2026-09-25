import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/notes/presentation/providers/derived_note_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La marca visible de una nota generada (F16, D3): qué modelo la escribió
/// y cuándo, y si el usuario ya la hizo suya editándola —en el texto del
/// tooltip, no en la insignia misma, para no competir con el resto de la
/// fila de insignias—.
///
/// No dibuja nada si [itemId] no es un derivado: la inmensa mayoría de las
/// notas.
class DerivedNoteBadge extends ConsumerWidget {
  const DerivedNoteBadge({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mark = ref.watch(derivedNoteMarkProvider(itemId)).valueOrNull;
    if (mark == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMd(locale).format(mark.generatedAt);
    final tooltip = mark.edited
        ? l10n.derivedNoteBadgeTooltipEdited(mark.model, date)
        : l10n.derivedNoteBadgeTooltip(mark.model, date);

    return Tooltip(
      message: tooltip,
      child: Chip(
        avatar: const Icon(Icons.auto_awesome, size: 16),
        label: Text(l10n.derivedNoteBadgeLabel),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
