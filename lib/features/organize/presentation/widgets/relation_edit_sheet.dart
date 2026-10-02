import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/relation_update_outcome.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_badge.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre la hoja para corregir el vínculo [relation] (F27): cambiar el tipo,
/// editar la frase, borrarlo y, si lo hizo la IA, decir que «no era».
///
/// Lo que pasó después —se fundió con otro, la IA no lo va a volver a
/// proponer— se avisa en la pantalla de abajo, con «Deshacer» cuando se
/// puede.
Future<void> showRelationEditSheet(
  BuildContext context, {
  required ItemRelation relation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RelationEditSheet(relation: relation),
  );
}

/// El contenido de [showRelationEditSheet]. Público para probarlo solo.
class RelationEditSheet extends ConsumerStatefulWidget {
  const RelationEditSheet({required this.relation, super.key});

  final ItemRelation relation;

  @override
  ConsumerState<RelationEditSheet> createState() => _RelationEditSheetState();
}

class _RelationEditSheetState extends ConsumerState<RelationEditSheet> {
  late RelationKind _kind = widget.relation.kind;
  late final _note = TextEditingController(text: widget.relation.note);
  var _busy = false;

  ItemRelation get _relation => widget.relation;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String? get _cleanNote {
    final text = _note.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Sin cambios no se escribe nada: guardar tal cual uno de la IA no es
    // adoptarlo, es cerrar la hoja.
    if (_kind == _relation.kind && _cleanNote == _relation.note) {
      navigator.pop();
      return;
    }

    setState(() => _busy = true);
    final result = await ref
        .read(organizeRepositoryProvider)
        .updateRelation(_relation.relationId, kind: _kind, note: _cleanNote);
    if (!mounted) return;

    result.match(
      (failure) {
        setState(() => _busy = false);
        _show(messenger, failure.localizedMessage(l10n));
      },
      (outcome) {
        navigator.pop();
        if (outcome == RelationUpdateOutcome.merged) {
          _show(messenger, l10n.relationEditMerged);
        }
      },
    );
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final result = await ref
        .read(organizeRepositoryProvider)
        .deleteRelation(_relation.relationId);
    if (!mounted) return;

    result.match((failure) {
      setState(() => _busy = false);
      _show(messenger, failure.localizedMessage(l10n));
    }, (_) => navigator.pop());
  }

  Future<void> _reject() async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Se toma antes de cerrar la hoja: el «Deshacer» del aviso corre cuando
    // esta hoja ya no existe.
    final repository = ref.read(organizeRepositoryProvider);
    setState(() => _busy = true);
    final result = await repository.rejectAiRelation(_relation.relationId);
    if (!mounted) return;

    result.match(
      (failure) {
        setState(() => _busy = false);
        _show(messenger, failure.localizedMessage(l10n));
      },
      (receipt) {
        navigator.pop();
        _show(
          messenger,
          l10n.relationRejected,
          action: SnackBarAction(
            label: l10n.aiRejectionUndo,
            onPressed: () async {
              final undone = await repository.restoreRejectedRelation(receipt);
              undone.match(
                (failure) => _show(messenger, failure.localizedMessage(l10n)),
                (_) {},
              );
            },
          ),
        );
      },
    );
  }

  static void _show(
    ScaffoldMessengerState messenger,
    String message, {
    SnackBarAction? action,
  }) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fixedKind = _relation.kind.isStructural;

    return Padding(
      // El teclado no tapa la frase que se está escribiendo.
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.relationEditTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_relation.isFromAi) AiBadge(tooltip: l10n.relationMadeByAi),
              ],
            ),
            const SizedBox(height: 8),
            // La frase con el tipo elegido: lo que va a decir la fila.
            Row(
              children: [
                Icon(
                  _kind.icon,
                  size: 20,
                  color: _kind.color(theme.colorScheme),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _kind.describe(
                      l10n,
                      direction: _relation.direction,
                      otherItemTitle: _relation.otherItemTitle,
                    ),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (fixedKind)
              Text(
                l10n.relationEditKindFixed,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              Text(
                l10n.relationEditKindLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in RelationKind.values)
                    if (!kind.isStructural)
                      ChoiceChip(
                        label: Text(kind.shortLabel(l10n)),
                        avatar: Icon(kind.icon, size: 18),
                        selected: _kind == kind,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _kind = kind),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _note,
              enabled: !_busy,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.pickRelationNoteHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: const Icon(Icons.link_off),
                  label: Text(l10n.commonDelete),
                ),
                if (_relation.isFromAi)
                  Tooltip(
                    message: l10n.aiNotRightHint,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _reject,
                      icon: const Icon(Icons.thumb_down_alt_outlined),
                      label: Text(l10n.aiNotRight),
                    ),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(l10n.detailSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
