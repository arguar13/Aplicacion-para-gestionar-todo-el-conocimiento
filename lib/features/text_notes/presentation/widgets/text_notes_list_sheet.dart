import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/domain/services/text_note_placement.dart';
import 'package:sinapsis/features/text_notes/presentation/providers/text_note_providers.dart';
import 'package:sinapsis/features/text_notes/presentation/text_note_actions.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un texto con notas que se lee en un marco (F45, paso 8b): lo que el cuerpo
/// le cuenta al marco para «Notas (N)» —de qué texto son ([target]), el texto
/// que se muestra ([content]) y cómo llevar la vista a un lugar ([reveal])—.
///
/// - [content] `null`: el texto no está a mano —un informe, que no se elige
///   de corrido—, y todas sus notas van a «Sin lugar».
/// - [reveal] lleva la vista a `[start, end)` de [content] y lo marca un
///   momento; devuelve si pudo —lo que se ve puede no tenerlo: el resumen no
///   trae todas las oraciones—. `null` si el cuerpo no puede —una página de
///   PDF—: tocar una nota la abre.
/// - [title]: con varios textos en el mismo marco —una extracción de varios
///   documentos—, el de cada uno, arriba de sus notas.
/// - [onPage]: el cuerpo muestra la página tal cual —un PDF, una página web,
///   la imagen de una foto— y no lleva globitos: la lista lo dice.
@immutable
class TextNoteSource {
  const TextNoteSource({
    required this.target,
    this.content,
    this.reveal,
    this.title,
    this.onPage = false,
  });

  final TextNoteTarget target;
  final String? content;
  final bool Function(int start, int end)? reveal;
  final String? title;
  final bool onPage;

  /// Si [other] es el mismo texto, sin mirar [reveal] —una función nueva en
  /// cada cuadro—.
  bool sameTextAs(TextNoteSource other) =>
      other.target == target &&
      other.content == content &&
      other.title == title &&
      other.onPage == onPage &&
      (other.reveal == null) == (reveal == null);
}

/// «Notas (N)» (F45, paso 8b): la lista de las notas de [sources] en el orden
/// del texto, con «Sin lugar» al final, y abajo «Nota sobre el texto entero».
/// Tocar una lleva a su lugar —si el cuerpo puede— y la abre. Para el lector
/// de pantalla, cada nota es «Nota: …, sobre "…"», con su encabezado.
///
/// [ref] es el de la pantalla de abajo, que sigue ahí cuando la lista ya se
/// cerró: lo que se abre después —la tarjeta, la hoja de una nota nueva— lo
/// usa.
Future<void> showTextNotesList(
  BuildContext context,
  WidgetRef ref, {
  required List<TextNoteSource> sources,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    minChildSize: 0.3,
    maxChildSize: 0.95,
    builder: (sheetContext, scroll) => _NotesList(
      host: context,
      hostRef: ref,
      sources: sources,
      scroll: scroll,
    ),
  ),
);

class _NotesList extends ConsumerWidget {
  const _NotesList({
    required this.host,
    required this.hostRef,
    required this.sources,
    required this.scroll,
  });

  /// La pantalla de abajo: lo que se abre después de cerrar la lista va ahí,
  /// con su [hostRef].
  final BuildContext host;
  final WidgetRef hostRef;
  final List<TextNoteSource> sources;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final several = sources.length > 1;
    final placedOf = {
      for (final source in sources)
        source: ref
            .watch(
              placedTextNotesProvider((
                target: source.target,
                content: source.content ?? '',
              )),
            )
            .valueOrNull,
    };
    final total = placedOf.values.fold(
      0,
      (sum, list) => sum + (list?.length ?? 0),
    );
    final loading = placedOf.values.any((list) => list == null);

    void open(TextNoteSource source, PlacedTextNote placed) {
      Navigator.of(context).pop();
      if (placed.placed) source.reveal?.call(placed.start!, placed.end!);
      if (!host.mounted) return;
      unawaited(openTextNote(host, hostRef, placed.note));
    }

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
        child: Semantics(
          header: true,
          child: Text(
            l10n.f45S8bNotesMenu(total),
            key: const Key('text-notes-list-title'),
            style: theme.textTheme.titleLarge,
          ),
        ),
      ),
      if (sources.any((source) => source.onPage))
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
          child: Text(
            l10n.f45S8bNotesOnPage,
            key: const Key('text-notes-on-page'),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      if (!loading && total == 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Text(
            l10n.f45S8bNotesEmpty,
            key: const Key('text-notes-empty'),
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
      for (final source in sources) ...[
        if (several && source.title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Semantics(
              header: true,
              child: Text(
                source.title!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ..._notesOf(context, source, placedOf[source] ?? const [], open),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: Key('text-notes-new-whole-${sources.indexOf(source)}'),
              icon: const Icon(Icons.add_comment_outlined),
              label: Text(l10n.f45S8bNewWholeNote),
              onPressed: () {
                Navigator.of(context).pop();
                if (!host.mounted) return;
                unawaited(
                  writeWholeTextNote(host, hostRef, target: source.target),
                );
              },
            ),
          ),
        ),
      ],
    ];

    return ListView(
      key: const Key('text-notes-list'),
      controller: scroll,
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  /// Las notas de [source]: primero las que tienen lugar, en el orden del
  /// texto; después, con su encabezado, las sin lugar.
  List<Widget> _notesOf(
    BuildContext context,
    TextNoteSource source,
    List<PlacedTextNote> placed,
    void Function(TextNoteSource source, PlacedTextNote placed) open,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final unplaced = [
      for (final p in placed)
        if (!p.placed) p,
    ];
    return [
      for (final p in placed)
        if (p.placed) TextNoteTile(note: p.note, onTap: () => open(source, p)),
      if (unplaced.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Semantics(
            header: true,
            child: Text(
              l10n.f45S8bNotesNoPlace,
              key: Key('text-notes-no-place-${sources.indexOf(source)}'),
              style: theme.textTheme.titleSmall,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 2, 24, 4),
          child: Text(
            l10n.f45S8bNotesNoPlaceHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final p in unplaced)
          TextNoteTile(note: p.note, onTap: () => open(source, p)),
      ],
    ];
  }
}
