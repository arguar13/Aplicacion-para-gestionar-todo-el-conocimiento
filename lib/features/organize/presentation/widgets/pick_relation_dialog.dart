import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Elige qué tipo de vínculo es, y opcionalmente por qué.
///
/// Compartido entre `RelationsSection` y `GraphScreen` — ver `PickItemDialog`
/// para la misma razón.
class PickRelationDialog extends StatefulWidget {
  const PickRelationDialog({super.key});

  @override
  State<PickRelationDialog> createState() => _PickRelationDialogState();
}

class _PickRelationDialogState extends State<PickRelationDialog> {
  RelationKind _kind = RelationKind.relatedTo;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.pickRelationKindTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in RelationKind.values)
                  ChoiceChip(
                    label: Text(kind.shortLabel(l10n)),
                    avatar: Icon(kind.icon, size: 18),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(hintText: l10n.pickRelationNoteHint),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop((
            kind: _kind,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          )),
          child: Text(l10n.pickRelationConfirm),
        ),
      ],
    );
  }
}
