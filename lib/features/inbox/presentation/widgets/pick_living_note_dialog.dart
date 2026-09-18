import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/inbox/domain/entities/note_reference.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Elige con qué nota viva vincular, buscando entre las que ya existen.
///
/// Calco de `PickItemDialog` —mismo patrón de búsqueda con debounce
/// implícito vía `setState`—, pero sobre [livingNotesProvider] en vez de
/// toda la biblioteca: acá solo tiene sentido elegir entre notas de tipo
/// `living`, no cualquier elemento.
class PickLivingNoteDialog extends ConsumerStatefulWidget {
  const PickLivingNoteDialog({this.excludeItemId, super.key});

  /// La nota que no debe aparecer en la lista — normalmente, la que se
  /// está por vincular, si ya es en sí misma una nota viva.
  final String? excludeItemId;

  @override
  ConsumerState<PickLivingNoteDialog> createState() =>
      _PickLivingNoteDialogState();
}

class _PickLivingNoteDialogState extends ConsumerState<PickLivingNoteDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final searchText = _controller.text.trim();

    final notes =
        (ref
                    .watch(
                      livingNotesProvider(
                        searchText.isEmpty ? null : searchText,
                      ),
                    )
                    .valueOrNull ??
                const <NoteReference>[])
            .where((n) => n.id != widget.excludeItemId)
            .toList();

    return AlertDialog(
      title: Text(l10n.pickLivingNoteTitle),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.pickLivingNoteSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildList(context, l10n, notes, searchText)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    AppLocalizations l10n,
    List<NoteReference> notes,
    String searchText,
  ) {
    if (notes.isEmpty) {
      final message = searchText.isEmpty
          ? l10n.pickLivingNoteNoOthers
          : l10n.pickLivingNoteNoMatches(searchText);

      return Center(child: Text(message, textAlign: TextAlign.center));
    }

    return ListView.builder(
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return ListTile(
          leading: const Icon(Icons.edit_note_outlined),
          title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: note.subtitle == null
              ? null
              : Text(
                  note.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => Navigator.of(context).pop(note.id),
        );
      },
    );
  }
}
