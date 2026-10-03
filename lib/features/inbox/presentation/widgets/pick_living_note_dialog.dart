import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/inbox/domain/entities/note_reference.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se eligió en [PickLivingNoteDialog]: una nota viva que ya existe, o
/// crear una nueva con ese nombre (F28).
sealed class LivingNoteChoice {
  const LivingNoteChoice();
}

/// Una nota viva que ya existía.
final class ExistingLivingNote extends LivingNoteChoice {
  const ExistingLivingNote(this.note);

  final NoteReference note;
}

/// Crear una nota viva nueva llamada [title].
final class NewLivingNote extends LivingNoteChoice {
  const NewLivingNote(this.title);

  final String title;
}

/// Elige con qué nota viva vincular, buscando entre las que ya existen, o
/// pide crear una (F28).
///
/// Calco de `PickItemDialog` —mismo patrón de búsqueda con debounce
/// implícito vía `setState`—, pero sobre [livingNotesProvider] en vez de
/// toda la biblioteca: acá solo tiene sentido elegir entre notas de tipo
/// `living`, no cualquier elemento.
///
/// Sin ninguna nota viva, antes el selector solo decía que no había y la
/// fuente se perdía de la Bandeja igual. Ahora lo buscado que no coincide
/// exacto con ninguna se ofrece como nota nueva, y sin ninguna todavía, el
/// selector explica que alcanza con escribir de qué trata. El nombre lo pone
/// quien vincula —no se propone el de la fuente: una nota con el mismo título
/// que su fuente haría ambiguo cada `[[Título]]`—. El diálogo solo devuelve
/// la elección: crear la nota y vincular es de quien lo abrió, que es quien
/// puede deshacerlo.
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
    if (notes.isEmpty && searchText.isEmpty) return const _NoLivingNotes();

    // Lo buscado que no coincide exacto con ninguna se ofrece como nota nueva,
    // arriba de todo: buscar y no encontrar es justo cuando hace falta.
    final exact = notes.any(
      (n) => n.title.trim().toLowerCase() == searchText.toLowerCase(),
    );
    final offerNew = searchText.isNotEmpty && !exact;

    // Lo que va antes de las notas: la oferta de crear y, si no hay ninguna,
    // por qué. Las notas, con `builder`: pueden ser cientos.
    final header = [
      if (offerNew)
        ListTile(
          key: const Key('pick-living-note-create'),
          leading: const Icon(Icons.add),
          title: Text(
            l10n.pickLivingNoteCreate(searchText),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).pop(NewLivingNote(searchText)),
        ),
      if (notes.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.pickLivingNoteNoMatches(searchText),
            textAlign: TextAlign.center,
          ),
        ),
    ];

    return ListView.builder(
      itemCount: header.length + notes.length,
      itemBuilder: (context, index) {
        if (index < header.length) return header[index];
        final note = notes[index - header.length];
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
          onTap: () => Navigator.of(context).pop(ExistingLivingNote(note)),
        );
      },
    );
  }
}

/// Sin ninguna nota viva todavía: lo dice, y explica que escribir de qué
/// trata alcanza para crear la primera.
class _NoLivingNotes extends StatelessWidget {
  const _NoLivingNotes();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.spa_outlined, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(l10n.pickLivingNoteNoOthers, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            l10n.pickLivingNoteCreateHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
