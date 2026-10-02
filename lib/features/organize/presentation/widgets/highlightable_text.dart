import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/citations/presentation/fragment_citation.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_edit_dialog.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_selection_aloud.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que la vista de lectura necesita de un [HighlightableText] desde afuera:
/// saber si hay algo seleccionado, extraerlo o resaltarlo con un botón propio,
/// y llevar la vista a un fragmento.
///
/// El menú de selección sigue siendo el camino de siempre; esto es para quien
/// quiere además una barra de acciones fija, que no depende de que el menú
/// nativo muestre bien sus opciones.
class HighlightableTextController extends ChangeNotifier {
  TextSelection _selection = const TextSelection.collapsed(offset: -1);
  _HighlightableTextState? _state;

  /// La selección actual, en posiciones del texto que se ve.
  TextSelection get selection => _selection;

  /// Si hay un fragmento seleccionado.
  bool get hasSelection => _selection.isValid && !_selection.isCollapsed;

  /// Extrae la selección como una nota nueva. No hace nada sin selección.
  Future<void> extractSelection() async {
    if (!hasSelection) return;
    await _state?._extractSelection(_selection);
  }

  /// Resalta la selección, pidiendo la nota del resaltado. No hace nada sin
  /// selección.
  Future<void> highlightSelection() async {
    if (!hasSelection) return;
    await _state?._highlightSelection(_selection);
  }

  /// Crea una tarjeta con la selección como respuesta, pidiendo la pregunta. La
  /// tarjeta guarda de qué fragmento salió. No hace nada sin selección.
  Future<void> createFlashcardFromSelection() async {
    if (!hasSelection) return;
    await _state?._createFlashcardFromSelection(_selection);
  }

  /// Lleva la vista al fragmento `[start, end)` del texto —posiciones del
  /// contenido, las mismas de los resaltados— y lo marca un momento.
  void jumpTo({required int start, required int end}) =>
      _state?._jumpTo(start, end);

  /// Lleva la vista hasta la posición [start] del contenido, sin marcar
  /// nada: lo que está sonando ya se ve resaltado (F23).
  void reveal(int start) => _state?._scrollTo(start);

  void _setSelection(TextSelection selection) {
    if (selection == _selection) return;
    _selection = selection;
    // Una selección puede cambiar mientras se construye la pantalla; avisar
    // ahí haría que quien escucha reconstruya en medio de una construcción.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }
}

/// El texto de una forma de contenido, subrayable.
///
/// Seleccionar una parte del texto agrega "Resaltar" al propio menú de
/// selección —junto a Copiar y Compartir—, en el lugar exacto donde ya
/// aparecen esas opciones. El resultado se ve incrustado en el propio texto
/// —con un fondo distinto— y además se lista abajo con su nota, para poder
/// repasar sin tener que encontrar cada fragmento en medio de un artículo
/// largo.
///
/// Antes había un botón aparte que aparecía debajo de todo el texto en vez
/// de junto a la selección: en cualquier forma de contenido más larga que
/// una pantalla —una transcripción, un artículo— quedaba a miles de
/// píxeles de donde el usuario estaba mirando, y en la práctica era
/// invisible. `contextMenuBuilder` lo resuelve sin volver al menú nativo
/// del sistema operativo que se había descartado antes: sigue siendo un
/// widget de Flutter, normal y corriente —se prueba con `tester.tap` como
/// cualquier otro—, solo que Flutter lo posiciona junto a la selección en
/// vez de en un lugar fijo.
class HighlightableText extends ConsumerStatefulWidget {
  const HighlightableText({
    required this.itemId,
    required this.renditionId,
    required this.content,
    this.controller,
    this.initialJump,
    this.markdown = true,
    this.playing,
    this.onTapOffset,
    super.key,
  });

  /// El elemento al que pertenece esta forma de contenido. Hace falta para
  /// "Extraer como nota": la nota nueva queda vinculada a este con
  /// [RelationKind.extractedFrom].
  final String itemId;
  final String renditionId;
  final String content;

  /// Para manejarlo desde afuera: ver la selección, extraer, saltar a un
  /// fragmento.
  final HighlightableTextController? controller;

  /// Un fragmento al que llevar la vista apenas se dibuja: `[start, end)` del
  /// contenido.
  final ({int start, int end})? initialJump;

  /// Si [content] es Markdown y se muestra con formato, o texto tal cual:
  /// ver `extractedTextIsMarkdown` (F22).
  final bool markdown;

  /// Lo que se está diciendo mientras suena el audio (F23): `[start, end)`
  /// del contenido, en amarillo. Si el lector flotante está leyendo este
  /// texto (F25), manda lo suyo: es lo que el usuario está escuchando.
  final ({int start, int end})? playing;

  /// Se tocó el texto en esta posición del contenido —sin seleccionar—: lo
  /// que lleva el audio a la palabra tocada (F23).
  final ValueChanged<int>? onTapOffset;

  @override
  ConsumerState<HighlightableText> createState() => _HighlightableTextState();
}

class _HighlightableTextState extends ConsumerState<HighlightableText> {
  /// El contenido crudo, renderizado con formato —títulos, negrita,
  /// cursiva, viñetas— sin perder la correspondencia con las posiciones
  /// del texto original: es lo que hace posible mostrar formato de verdad
  /// sin romper los resaltados existentes, que guardan sus rangos contra
  /// [HighlightableText.content] tal cual llega, no contra lo que se ve.
  late var _rendered = _render();

  RenderedMarkdown _render() => widget.markdown
      ? RenderedMarkdown.parse(widget.content)
      : RenderedMarkdown.plain(widget.content);

  final _textKey = GlobalKey();

  /// El fragmento marcado un momento después de saltar a él.
  (int, int)? _flash;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    final jump = widget.initialJump;
    if (jump != null) {
      // Recién cuando ya hay un cuadro: hasta entonces no se sabe cuánto mide
      // el texto ni dónde está dentro del desplazamiento.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpTo(jump.start, jump.end);
      });
    }
  }

  @override
  void didUpdateWidget(HighlightableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.markdown != widget.markdown) {
      _rendered = _render();
    }
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    if (widget.controller?._state == this) widget.controller?._state = null;
    super.dispose();
  }

  /// Lleva la vista a `[start, end)` y lo marca unos segundos.
  void _jumpTo(int start, int end) {
    if (start < 0 || end > widget.content.length || end <= start) return;

    _flashTimer?.cancel();
    setState(() => _flash = (start, end));
    _flashTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _flash = null);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(start));
  }

  /// Desplaza lo que rodea a este texto hasta dejar el punto [rawStart] a un
  /// cuarto de la altura de la vista.
  ///
  /// El texto es un solo widget, así que no hay dónde preguntarle en qué
  /// altura está una posición: se mide con un `TextPainter` armado con los
  /// mismos estilos y el mismo ancho que el texto real.
  void _scrollTo(int rawStart) {
    if (!mounted) return;
    final box = _textKey.currentContext?.findRenderObject() as RenderBox?;
    final position = Scrollable.maybeOf(context)?.position;
    if (box == null || !box.hasSize || position == null) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;

    final painter = TextPainter(
      text: _rendered.buildSpans(Theme.of(context), const []),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: box.size.width);
    final top = painter
        .getOffsetForCaret(
          TextPosition(offset: _rendered.rawToRender(rawStart)),
          Rect.zero,
        )
        .dy;
    painter.dispose();

    final revealed = viewport.getOffsetToReveal(
      box,
      0.25,
      rect: Rect.fromLTWH(0, top, box.size.width, 24),
    );
    unawaited(
      position.animateTo(
        revealed.offset.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      ),
    );
  }

  Future<void> _highlightSelection(TextSelection selection) async {
    // La selección llega en posiciones del texto **renderizado** —lo que
    // el usuario ve y tocó—, así que hay que traducirla al contenido crudo
    // antes de guardar: es ahí donde vive el resto del sistema de
    // resaltados, y donde tiene que seguir viviendo para que exportar,
    // buscar o abrir el mismo elemento en otra pantalla encuentre el mismo
    // fragmento.
    final startOffset = _rendered.renderToRaw(selection.start);
    final endOffset = _rendered.renderToRaw(selection.end, isEnd: true);
    final excerpt = widget.content.substring(startOffset, endOffset);

    // `null` es "se canceló". Una nota vacía sigue siendo una confirmación
    // válida —resaltar sin explicar por qué es perfectamente legítimo— y se
    // guarda como ausente, igual que hace el repositorio con cualquier nota
    // en blanco.
    final note = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(initialNote: null, excerpt: excerpt),
    );
    if (note == null || !mounted) return;

    await ref
        .read(organizeRepositoryProvider)
        .createHighlight(
          renditionId: widget.renditionId,
          startOffset: startOffset,
          endOffset: endOffset,
          excerpt: excerpt,
          note: note.isEmpty ? null : note,
        );
  }

  /// Crea una tarjeta de repaso con el fragmento seleccionado como respuesta
  /// (F11): la pregunta la escribe la persona, y la tarjeta guarda el rango del
  /// que salió, para poder volver a él desde el repaso.
  Future<void> _createFlashcardFromSelection(TextSelection selection) async {
    // Mismo cuidado que al resaltar: la selección llega en posiciones del
    // texto renderizado y se guarda contra el contenido crudo.
    final startOffset = _rendered.renderToRaw(selection.start);
    final endOffset = _rendered.renderToRaw(selection.end, isEnd: true);
    if (endOffset <= startOffset) return;
    final excerpt = widget.content.substring(startOffset, endOffset);

    final answer = await showFlashcardEditDialog(context, initialBack: excerpt);
    if (answer == null || !mounted) return;
    final (front, back) = answer;

    final result = await ref
        .read(flashcardRepositoryProvider)
        .create(
          itemId: widget.itemId,
          front: front,
          back: back,
          sourceCharStart: startOffset,
          sourceCharEnd: endOffset,
        );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.match(
              (failure) => failure.localizedMessage(l10n),
              (_) => l10n.flashcardsCreatedFromSelection,
            ),
          ),
        ),
      );
  }

  /// El menú de selección de la app —ver [selectionMenuItems]—, con lo que
  /// este texto agrega: leer lo seleccionado en voz alta, resaltarlo,
  /// extraerlo como nota o hacer una tarjeta. Flutter lo posiciona solo
  /// junto a la selección activa, sea cual sea el punto de un texto largo
  /// donde el usuario esté parado.
  Widget _buildContextMenu(BuildContext context, EditableTextState editable) {
    final selection = editable.textEditingValue.selection;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: selectionMenuItems(
        context,
        editable,
        onReadAloud: () => unawaited(_readSelectionAloud(selection)),
        onHighlight: () => unawaited(_highlightSelection(selection)),
        onExtract: () => unawaited(_extractSelection(selection)),
        onCreateFlashcard: () =>
            unawaited(_createFlashcardFromSelection(selection)),
      ),
    );
  }

  /// "Leer en voz alta": las líneas que toca la selección, con el resaltado
  /// del lector flotante (F25).
  Future<void> _readSelectionAloud(TextSelection selection) {
    final start = _rendered.renderToRaw(selection.start);
    final end = _rendered.renderToRaw(selection.end, isEnd: true);
    return readSelectionAloud(
      ref,
      text: widget.content.substring(start, end),
      sourceKey: widget.renditionId,
      start: start,
      end: end,
    );
  }

  /// Crea una nota atómica nueva con el fragmento seleccionado, vinculada
  /// al elemento actual como su fuente.
  ///
  /// Pasa por [captureItemUseCaseProvider] —el mismo camino de entrada que
  /// cualquier captura manual— en vez de armar el `KnowledgeItem` a mano:
  /// así la nota nueva recibe el mismo tratamiento (id, timestamps,
  /// guardado atómico) que cualquier otra, sin duplicar esa lógica acá.
  Future<void> _extractSelection(TextSelection selection) async {
    final startOffset = _rendered.renderToRaw(selection.start);
    final endOffset = _rendered.renderToRaw(selection.end, isEnd: true);
    final excerpt = widget.content.substring(startOffset, endOffset);

    final result = await ref.read(captureItemUseCaseProvider)(
      CaptureRequest.text(rawInput: excerpt),
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;

    final failure = result.getLeft().toNullable();
    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
      return;
    }
    final newItem = result.getRight().toNullable()!;

    await ref
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: newItem.id,
          toItemId: widget.itemId,
          kind: RelationKind.extractedFrom,
          // De dónde salió: con esto la nota lleva de vuelta al lugar exacto.
          sourceCharStart: startOffset,
          sourceCharEnd: endOffset,
        );
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.detailExtractedNoteCreated(newItem.title)),
          action: SnackBarAction(
            label: l10n.detailExtractedNoteView,
            onPressed: () {
              if (context.mounted) {
                context.push(RoutePaths.itemDetail(newItem.id));
              }
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final highlights =
        ref
            .watch(renditionHighlightsProvider(widget.renditionId))
            .valueOrNull ??
        const <Highlight>[];
    // Se ignoran los resaltados cuyo rango ya no entra en el texto actual:
    // si la rendition se regeneró —una transcripción rehecha con un modelo
    // mejor— sus índices pueden apuntar más allá de donde ahora termina el
    // texto, y usarlos tal cual pintaría un resaltado corrido hasta el
    // final en vez de mostrar el texto igual, sin ese resaltado.
    final validHighlights = highlights.where(
      (h) => h.endOffset <= widget.content.length,
    );
    final kind = ref
        .watch(libraryItemProvider(widget.itemId))
        .valueOrNull
        ?.source
        .kind;
    final isSource = kind != null && kind != SourceKind.manualNote;
    // Lo que lee el lector flotante (F25): solo este texto se redibuja
    // cuando cambia la línea, y solo si es suya.
    final readAloud = ref.watch(readAloudHighlightProvider(widget.renditionId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText.rich(
          key: _textKey,
          _rendered.buildSpans(
            theme,
            [
              for (final h in validHighlights) (h.startOffset, h.endOffset),
              ?_flash,
            ],
            activeRange:
                readAloud ??
                switch (widget.playing) {
                  final playing? => (playing.start, playing.end),
                  null => null,
                },
          ),
          contextMenuBuilder: _buildContextMenu,
          onSelectionChanged: (selection, cause) {
            widget.controller?._setSelection(selection);
            final onTap = widget.onTapOffset;
            if (onTap != null &&
                cause == SelectionChangedCause.tap &&
                selection.isCollapsed &&
                selection.baseOffset >= 0) {
              onTap(_rendered.renderToRaw(selection.baseOffset));
            }
          },
        ),
        if (highlights.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l10n.detailHighlightsTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final highlight in highlights)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.highlight),
              title: Text(
                highlight.excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: highlight.note == null ? null : Text(highlight.note!),
              onTap: () => _editNote(ref, highlight),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Una nota no se cita: solo lo que viene de una fuente.
                  if (isSource)
                    IconButton(
                      key: Key('cite-highlight-${highlight.id}'),
                      icon: const Icon(Icons.format_quote),
                      tooltip: l10n.detailHighlightCiteTooltip,
                      onPressed: () => _citeHighlight(highlight),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.detailRemoveHighlight,
                    onPressed: () => ref
                        .read(organizeRepositoryProvider)
                        .deleteHighlight(highlight.id),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  /// Copia la cita del resaltado: la de su fuente, con la página o el minuto
  /// donde empieza.
  Future<void> _citeHighlight(Highlight highlight) async {
    final locator = await ref
        .read(fragmentLocatorResolverProvider)
        .locate(
          itemId: widget.itemId,
          renditionId: widget.renditionId,
          charOffset: highlight.startOffset,
        );
    if (!mounted) return;
    await copyFragmentCitation(
      context,
      ref,
      sourceId: widget.itemId,
      locator: locator,
    );
  }

  Future<void> _editNote(WidgetRef ref, Highlight highlight) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          _NoteDialog(initialNote: highlight.note, excerpt: highlight.excerpt),
    );
    if (result == null || !mounted) return;

    await ref
        .read(organizeRepositoryProvider)
        .updateHighlightNote(id: highlight.id, note: result);
  }
}

/// Un texto corto que se muestra tal cual —un mensaje del chat, una cara de
/// una tarjeta, la nota del usuario—, con lo que está leyendo el lector
/// flotante en amarillo (F25): el mismo amarillo que [HighlightableText] y
/// que el audio (F23), para los textos que no se subrayan.
///
/// Sin nada que resaltar se dibuja igual que un `Text` —o un
/// `SelectableText`, con [selectable]— de siempre; solo el texto que se está
/// leyendo se redibuja cuando el lector cambia de línea.
class ReadAloudText extends ConsumerWidget {
  const ReadAloudText(
    this.text, {
    required this.sourceKey,
    this.style,
    this.textAlign,
    this.selectable = false,
    super.key,
  });

  final String text;

  /// Con qué nombre lo conoce el lector: el `sourceKey` de los pedazos que
  /// salen de [text], con sus posiciones contadas sobre [text] tal cual.
  final String sourceKey;

  final TextStyle? style;
  final TextAlign? textAlign;
  final bool selectable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(readAloudHighlightProvider(sourceKey));
    // El menú de selección de la app; "Leer en voz alta" lee las líneas que
    // toca la selección: las posiciones de [text] son las de sus pedazos.
    Widget menu(BuildContext context, EditableTextState editable) =>
        buildSelectionMenu(
          context,
          editable,
          onReadAloud: () {
            final selection = editable.textEditingValue.selection;
            unawaited(
              readSelectionAloud(
                ref,
                text: selection.textInside(text),
                sourceKey: sourceKey,
                start: selection.start,
                end: selection.end,
              ),
            );
          },
        );

    if (reading == null) {
      return selectable
          ? SelectableText(
              text,
              style: style,
              textAlign: textAlign,
              contextMenuBuilder: menu,
            )
          : Text(text, style: style, textAlign: textAlign);
    }

    // Las mismas piezas que un texto sin formato de [HighlightableText]:
    // así el amarillo es exactamente el mismo en toda la app. Parte del
    // estilo que tendría el `Text` de arriba, para que resaltar una línea
    // no le cambie la letra al resto.
    final spans = RenderedMarkdown.plain(text).buildSpans(
      Theme.of(context),
      const [],
      baseStyle: DefaultTextStyle.of(context).style.merge(style),
      activeRange: reading,
    );
    return selectable
        ? SelectableText.rich(
            spans,
            textAlign: textAlign,
            contextMenuBuilder: menu,
          )
        : Text.rich(spans, textAlign: textAlign);
  }
}

/// Ver o poner la nota de un resaltado: en blanco al crear uno, con lo que
/// ya tenía al editarlo.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initialNote, required this.excerpt});

  final String? initialNote;
  final String excerpt;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.detailHighlightNoteDialogTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.excerpt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: l10n.detailHighlightNoteHint,
              ),
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
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.detailSave),
        ),
      ],
    );
  }
}
