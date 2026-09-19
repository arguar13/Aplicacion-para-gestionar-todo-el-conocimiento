import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El selector del subtipo (atómica, viva o mapa) de las notas que se crean
/// desde un enlace roto.
///
/// `Wrap` de `ChoiceChip`s y no un `SegmentedButton`: con tres etiquetas y un
/// ícono cada una, el segmentado desborda en una pantalla angosta, y los chips
/// simplemente pasan a la línea de abajo.
class NoteKindChips extends StatelessWidget {
  const NoteKindChips({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final NoteKind selected;

  /// `null` deja todos los chips sin respuesta.
  final ValueChanged<NoteKind>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onChanged = this.onChanged;

    return Semantics(
      container: true,
      label: l10n.linksNoteKindLabel,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final kind in NoteKind.values)
            ChoiceChip(
              avatar: Icon(kind.icon, size: 18),
              label: Text(kind.label(l10n)),
              selected: selected == kind,
              showCheckmark: false,
              onSelected: onChanged == null ? null : (_) => onChanged(kind),
            ),
        ],
      ),
    );
  }
}
