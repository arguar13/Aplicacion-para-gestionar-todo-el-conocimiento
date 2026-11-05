import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/domain/repositories/text_note_repository.dart';
import 'package:sinapsis/features/text_notes/presentation/providers/text_note_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

// Poner, ver, editar y borrar una nota en el texto (F45, paso 8b, mejora 19):
// lo mismo en todos los lectores —el original de la Biblioteca y el de
// Procesado, el texto de un procesado con su resumen y su síntesis, y lo
// creado—, que solo saben dónde está lo elegido.
//
// - **Escribir**: [writeTextNote] sobre lo elegido —«Nota» en la barrita de
//   la selección— y [writeWholeTextNote] sobre el texto entero —desde «Notas
//   (N)»—. Una hoja con los colores de resaltar y el campo; «Listo» la
//   guarda, y cerrarla de cualquier otro modo con algo escrito también: lo
//   escrito no se pierde (se guarda sola). En blanco no se guarda nunca.
// - **Abrir**: [openTextNote] —tocar el globito, el pedazo o la nota de la
//   lista— muestra la tarjeta: lo que dice, el pedazo, la fecha, los colores
//   (cambian en el acto), «Editar», «Copiar» y «Borrar» con «Deshacer». El
//   globito de un renglón con varias abre [openTextNotes].
//
// Nada toca el documento: las notas se agregan (decisión E).

/// Lo que se escribió en la hoja de una nota: su texto, sin espacios en las
/// puntas, y su color.
typedef _Written = ({String text, HighlightColor color});

/// «Nota» sobre `[start, end)` del texto de [target], cuyo pedazo es
/// [excerpt]: pide la nota y la pone. Si algo falla, lo dice.
Future<void> writeTextNote(
  BuildContext context,
  WidgetRef ref, {
  required TextNoteTarget target,
  required int start,
  required int end,
  required String excerpt,
}) async {
  if (start < 0 || end <= start || excerpt.trim().isEmpty) return;
  final repository = ref.read(textNoteRepositoryProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context)!;
  final written = await _write(context, ref, excerpt: excerpt);
  if (written == null) return;
  final created = await repository.create(
    target: target,
    start: start,
    end: end,
    excerpt: excerpt,
    note: written.text,
    color: written.color,
  );
  _sayFailure(messenger, l10n, created.getLeft().toNullable());
}

/// Una nota sobre el texto entero de [target], sin elegir nada: va a «Sin
/// lugar» (`TextNote.wholeText`).
Future<void> writeWholeTextNote(
  BuildContext context,
  WidgetRef ref, {
  required TextNoteTarget target,
}) async {
  final repository = ref.read(textNoteRepositoryProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context)!;
  final written = await _write(context, ref);
  if (written == null) return;
  final created = await repository.createOnWholeText(
    target: target,
    note: written.text,
    color: written.color,
  );
  _sayFailure(messenger, l10n, created.getLeft().toNullable());
}

/// Abre la hoja para escribir una nota —sobre [excerpt], o sobre el texto
/// entero sin él— con el último color elegido para resaltar. `null` si se
/// canceló o quedó en blanco.
Future<_Written?> _write(
  BuildContext context,
  WidgetRef ref, {
  String? excerpt,
}) async {
  // Lo escrito vive acá y no en la hoja: si se cierra sin «Listo», se lee
  // igual. Los controles los tiene la hoja, que los suelta cuando termina de
  // irse —soltarlos acá, al volver, los dejaba en una hoja que todavía se
  // estaba yendo—.
  final draft = _Draft(ref.read(lastHighlightColorProvider));
  final kept = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NoteEditor(draft: draft, excerpt: excerpt),
  );
  // «Cancelar» dice que no; «Listo» o cerrarla de otro modo, que sí.
  final note = draft.text.trim();
  if (kept == false || note.isEmpty) return null;
  ref.read(lastHighlightColorProvider.notifier).state = draft.color;
  return (text: note, color: draft.color);
}

/// Lo que se va escribiendo en la hoja de una nota.
class _Draft {
  _Draft(this.color);

  String text = '';
  HighlightColor color;
}

/// Abre la tarjeta de [note]: leerla, editarla, cambiarle el color, copiarla
/// o borrarla con «Deshacer».
Future<void> openTextNote(BuildContext context, WidgetRef ref, TextNote note) {
  // Antes de abrir: la tarjeta puede cerrarse cuando quien la abrió ya no
  // está, y el aviso de «Deshacer» va en la pantalla de abajo.
  final repository = ref.read(textNoteRepositoryProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NoteCard(
      key: Key('text-note-card-${note.id}'),
      note: note,
      repository: repository,
      messenger: messenger,
    ),
  );
}

/// El globito de un renglón con varias [notes]: con una, su tarjeta; con
/// más, la lista de ese renglón, y de ahí cada tarjeta.
Future<void> openTextNotes(
  BuildContext context,
  WidgetRef ref,
  List<TextNote> notes,
) async {
  if (notes.isEmpty) return;
  if (notes.length == 1) return openTextNote(context, ref, notes.single);
  final l10n = AppLocalizations.of(context)!;
  final chosen = await showModalBottomSheet<TextNote>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        key: const Key('text-notes-line-sheet'),
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.f45S8bSeveralTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final note in notes)
              TextNoteTile(
                note: note,
                onTap: () => Navigator.of(context).pop(note),
              ),
          ],
        ),
      ),
    ),
  );
  if (chosen == null || !context.mounted) return;
  await openTextNote(context, ref, chosen);
}

/// Lo que dice el lector de pantalla de [note]: «Nota: …, sobre "…"».
String textNoteSemantics(AppLocalizations l10n, TextNote note) => note.wholeText
    ? l10n.f45S8bBubbleWhole(note.note)
    : l10n.f45S8bBubble(note.note, note.excerpt);

/// El tono de [color] para el fondo de un globito o de una muestra; sin
/// color —un resaltado de antes—, el de siempre.
Color textNoteFill(BuildContext context, HighlightColor? color) =>
    HighlightPalette.resolve(context, color);

/// La línea de [color] —el punteado del pedazo, el borde del globito—, que
/// se ve sobre el fondo del tema.
Color textNoteLine(BuildContext context, HighlightColor? color) =>
    HighlightPalette.line(context, color);

/// Una nota en una lista —«Notas (N)», el globito de un renglón con
/// varias—: su color, lo que dice y, debajo, el pedazo citado (o «Sobre el
/// texto entero»). Para el lector de pantalla, una sola cosa: «Nota: …,
/// sobre "…"», que se toca para abrirla.
class TextNoteTile extends StatelessWidget {
  const TextNoteTile({required this.note, required this.onTap, super.key});

  final TextNote note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      key: Key('text-note-tile-${note.id}'),
      button: true,
      label: textNoteSemantics(l10n, note),
      onTapHint: l10n.f45S8bOpenNote,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: TextNoteDot(color: note.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.note,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note.wholeText
                          ? l10n.f45S8bWholeText
                          : '«${note.excerpt}»',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontStyle: note.wholeText ? null : FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La muestra redonda del color de una nota.
class TextNoteDot extends StatelessWidget {
  const TextNoteDot({required this.color, this.size = 18, super.key});

  final HighlightColor? color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: textNoteFill(context, color),
      border: Border.all(color: textNoteLine(context, color), width: 1.5),
    ),
  );
}

/// La hoja donde se escribe una nota: el pedazo, los colores y el campo. Lo
/// escrito y el color van, a medida que cambian, a [draft], que es de quien
/// la abrió ([_write]): así lo escrito no se pierde si la hoja se cierra sin
/// «Listo».
class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.draft, required this.excerpt});

  final _Draft draft;

  /// El pedazo sobre el que se escribe, o `null` en el texto entero.
  final String? excerpt;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _text = TextEditingController(text: widget.draft.text);
  var _blank = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() {
    if (_text.text.trim().isEmpty) {
      setState(() => _blank = true);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final excerpt = widget.excerpt;
    return SingleChildScrollView(
      key: const Key('text-note-editor'),
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.f45S8bEditorTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            excerpt == null ? l10n.f45S8bWholeText : '«$excerpt»',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: excerpt == null ? null : FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _ColorRow(
            keyPrefix: 'text-note-color',
            chosen: widget.draft.color,
            onChosen: (color) => setState(() => widget.draft.color = color),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('text-note-field'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (text) {
              widget.draft.text = text;
              if (_blank) setState(() => _blank = false);
            },
            decoration: InputDecoration(
              hintText: l10n.f45S8bEditorHint,
              border: const OutlineInputBorder(),
              errorText: _blank ? l10n.f45S8bEditorBlank : null,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                key: const Key('text-note-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: const Key('text-note-done'),
                onPressed: _done,
                child: Text(l10n.f45S8bEditorDone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Los colores de resaltar, para elegir el de una nota: nueve muestras que
/// pasan a la línea de abajo si no entran.
class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.keyPrefix,
    required this.chosen,
    required this.onChosen,
  });

  final String keyPrefix;
  final HighlightColor? chosen;
  final ValueChanged<HighlightColor> onChosen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      container: true,
      label: l10n.f45S8bEditorColor,
      child: Wrap(
        children: [
          for (final color in HighlightColor.values)
            HighlightColorDot(
              key: Key('$keyPrefix-${color.name}'),
              color: color,
              selected: color == chosen,
              tooltip: highlightColorName(l10n, color),
              onPressed: () => onChosen(color),
            ),
        ],
      ),
    );
  }
}

/// La tarjeta de una nota: lo que dice, el pedazo y la fecha; los colores,
/// que cambian en el acto; «Editar», «Copiar» y «Borrar» con «Deshacer».
/// Muestra siempre la última versión: lo que devolvió el repositorio.
class _NoteCard extends StatefulWidget {
  const _NoteCard({
    required this.note,
    required this.repository,
    required this.messenger,
    super.key,
  });

  final TextNote note;
  final TextNoteRepository repository;
  final ScaffoldMessengerState? messenger;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  late var _note = widget.note;
  TextEditingController? _editing;
  var _blank = false;

  @override
  void dispose() {
    _editing?.dispose();
    super.dispose();
  }

  Future<void> _recolor(HighlightColor color) async {
    final result = await widget.repository.recolor(_note, color);
    if (!mounted) return;
    result.match(_say, (note) => setState(() => _note = note));
  }

  void _startEditing() =>
      setState(() => _editing = TextEditingController(text: _note.note));

  void _stopEditing() {
    final editing = _editing;
    setState(() {
      _editing = null;
      _blank = false;
    });
    // Recién cuando el campo ya se fue: hasta el cuadro siguiente lo usa.
    WidgetsBinding.instance.addPostFrameCallback((_) => editing?.dispose());
  }

  Future<void> _saveEdit() async {
    final text = _editing!.text;
    if (text.trim().isEmpty) {
      setState(() => _blank = true);
      return;
    }
    final result = await widget.repository.edit(_note, text);
    if (!mounted) return;
    result.match(_say, (note) {
      _note = note;
      _stopEditing();
    });
  }

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: _note.note));
    widget.messenger
      ?..hideCurrentSnackBar()
      ..showAppSnackBar(AppSnackBar(content: Text(l10n.f45S8bCopied)));
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final repository = widget.repository;
    final messenger = widget.messenger;
    final result = await repository.delete(_note);
    if (!mounted) return;
    final failure = result.getLeft().toNullable();
    if (failure != null) return _say(failure);
    final removed = result.getRight().toNullable()!;
    Navigator.of(context).pop();
    messenger
      ?..hideCurrentSnackBar()
      ..showAppSnackBar(
        AppSnackBar(
          key: const Key('text-note-deleted'),
          content: Text(l10n.f45S8bDeleted),
          action: SnackBarAction(
            key: const Key('text-note-undo'),
            label: l10n.inboxUndo,
            onPressed: () => unawaited(() async {
              final restored = await repository.restore(removed);
              _sayFailure(messenger, l10n, restored.getLeft().toNullable());
            }()),
          ),
        ),
      );
  }

  void _say(Failure failure) =>
      _sayFailure(widget.messenger, AppLocalizations.of(context)!, failure);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final note = _note;
    final editing = _editing;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final edited = note.updatedAt.isAfter(note.createdAt);
    final date = DateFormat.yMMMd(
      locale,
    ).add_Hm().format((edited ? note.updatedAt : note.createdAt).toLocal());

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextNoteDot(color: note.color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.f45S8bEditorTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            edited ? l10n.f45S8bCardEdited(date) : l10n.f45S8bCardWritten(date),
            key: const Key('text-note-card-date'),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 12),
          Text(
            note.wholeText ? l10n.f45S8bWholeText : '«${note.excerpt}»',
            key: const Key('text-note-card-excerpt'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: note.wholeText ? null : FontStyle.italic,
              color: muted,
            ),
          ),
          const SizedBox(height: 12),
          if (editing == null)
            SelectableText(
              note.note,
              key: const Key('text-note-card-text'),
              style: theme.textTheme.bodyLarge,
            )
          else
            TextField(
              key: const Key('text-note-card-field'),
              controller: editing,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_blank) setState(() => _blank = false);
              },
              decoration: InputDecoration(
                hintText: l10n.f45S8bEditorHint,
                border: const OutlineInputBorder(),
                errorText: _blank ? l10n.f45S8bEditorBlank : null,
              ),
            ),
          if (note.origin == TextNoteOrigin.highlight) ...[
            const SizedBox(height: 8),
            Text(
              l10n.f45S8bCardFromHighlight,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          const SizedBox(height: 12),
          _ColorRow(
            keyPrefix: 'text-note-card-color',
            chosen: note.color,
            onChosen: (color) => unawaited(_recolor(color)),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: editing == null
                ? [
                    TextButton.icon(
                      key: const Key('text-note-card-delete'),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.f45S8bCardDelete),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      onPressed: () => unawaited(_delete()),
                    ),
                    TextButton.icon(
                      key: const Key('text-note-card-copy'),
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(l10n.f45S8bCardCopy),
                      onPressed: () => unawaited(_copy()),
                    ),
                    FilledButton.tonalIcon(
                      key: const Key('text-note-card-edit'),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(l10n.f45S8bCardEdit),
                      onPressed: _startEditing,
                    ),
                  ]
                : [
                    TextButton(
                      key: const Key('text-note-card-cancel'),
                      onPressed: _stopEditing,
                      child: Text(l10n.commonCancel),
                    ),
                    FilledButton(
                      key: const Key('text-note-card-save'),
                      onPressed: () => unawaited(_saveEdit()),
                      child: Text(l10n.f45S8bEditorDone),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

/// Dice [failure] con un aviso, si hay uno y dónde decirlo.
void _sayFailure(
  ScaffoldMessengerState? messenger,
  AppLocalizations l10n,
  Failure? failure,
) {
  if (failure == null) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showAppSnackBar(
      AppSnackBar(content: Text(failure.localizedMessage(l10n))),
    );
}
