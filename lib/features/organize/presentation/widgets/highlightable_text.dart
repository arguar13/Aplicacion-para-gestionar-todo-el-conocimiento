import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/presentation/fragment_citation.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_selection_aloud.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlight_note_dialog.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
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
/// Seleccionar una parte del texto abre la barrita de resaltado (F38) junto a
/// la selección: los colores para resaltar de fondo, Subrayar, Copiar,
/// Escuchar, Nota, Extraer como nota y Hacer tarjeta. El resultado se ve
/// incrustado en el propio texto —con el color y el estilo elegidos— y además
/// se lista abajo con su nota, para poder repasar sin tener que encontrar
/// cada fragmento en medio de un artículo largo. Tocar algo ya resaltado
/// abre su ficha: cambiarle el color o el estilo, escribirle la nota o
/// quitarlo.
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
///
/// Las capas, de abajo hacia arriba: las oraciones de lo estudiado (F36), lo
/// que subrayó la persona, las palabras clave y lo que suena en voz alta.
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
    this.paints = const [],
    super.key,
  });

  /// El elemento al que pertenece esta forma de contenido. Hace falta para
  /// "Extraer como nota": la nota nueva queda vinculada a este con
  /// `RelationKind.extractedFrom`.
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

  /// Capas de color por debajo y por encima de los resaltados: lo estudiado
  /// del documento (F36), en posiciones del contenido.
  final List<PaintedRange> paints;

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

    // Con las mismas capas: una palabra clave va en negrita, y eso mueve los
    // renglones.
    final painter = TextPainter(
      text: _rendered.buildSpans(
        Theme.of(context),
        const [],
        paints: widget.paints,
      ),
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

  /// La selección, que llega en posiciones del texto **renderizado** —lo que
  /// el usuario ve y tocó—, traducida al contenido crudo antes de guardar:
  /// es ahí donde vive el resto del sistema de resaltados, y donde tiene que
  /// seguir viviendo para que exportar, buscar o abrir el mismo elemento en
  /// otra pantalla encuentre el mismo fragmento.
  (int, int) _rawRange(TextSelection selection) => (
    _rendered.renderToRaw(selection.start),
    _rendered.renderToRaw(selection.end, isEnd: true),
  );

  /// Resalta la selección con el color y el estilo elegidos, sin nota.
  Future<void> _highlightRange(
    TextSelection selection,
    HighlightColor color,
    HighlightStyle style,
  ) {
    final (start, end) = _rawRange(selection);
    return saveHandHighlight(
      context,
      ref,
      renditionId: widget.renditionId,
      content: widget.content,
      start: start,
      end: end,
      color: color,
      style: style,
    );
  }

  /// Resalta la selección pidiendo antes su nota.
  Future<void> _highlightSelection(TextSelection selection) {
    final (start, end) = _rawRange(selection);
    return saveHandHighlightWithNote(
      context,
      ref,
      renditionId: widget.renditionId,
      content: widget.content,
      start: start,
      end: end,
    );
  }

  /// Crea una tarjeta de repaso con el fragmento seleccionado como respuesta
  /// (F11): la pregunta la escribe la persona, y la tarjeta guarda el rango del
  /// que salió, para poder volver a él desde el repaso.
  Future<void> _createFlashcardFromSelection(TextSelection selection) {
    final (start, end) = _rawRange(selection);
    return createFlashcardFromRange(
      context,
      ref,
      itemId: widget.itemId,
      content: widget.content,
      start: start,
      end: end,
    );
  }

  /// Convierte el fragmento seleccionado en un hecho de la línea de tiempo
  /// (F40): con la cita puesta y, si trae una fecha, la fecha cargada.
  Future<void> _addToTimeline(TextSelection selection) {
    final (start, end) = _rawRange(selection);
    return addRangeToTimeline(
      context,
      ref,
      itemId: widget.itemId,
      renditionId: widget.renditionId,
      content: widget.content,
      start: start,
      end: end,
    );
  }

  /// La barrita de resaltado —ver [buildHighlightMenu]—, con lo que este
  /// texto agrega: leer lo seleccionado en voz alta, ponerle una nota,
  /// extraerlo como nota o hacer una tarjeta. Flutter la posiciona sola junto
  /// a la selección activa, sea cual sea el punto de un texto largo donde el
  /// usuario esté parado.
  Widget _buildContextMenu(BuildContext context, EditableTextState editable) {
    final selection = editable.textEditingValue.selection;
    return buildHighlightMenu(
      context,
      ref,
      editable,
      readOnly: isReadOnlyStudyKey(widget.renditionId),
      onHighlight: (color, style) =>
          unawaited(_highlightRange(selection, color, style)),
      onReadAloud: () => unawaited(_readSelectionAloud(selection)),
      onNote: () => unawaited(_highlightSelection(selection)),
      onExtract: () => unawaited(_extractSelection(selection)),
      onCreateFlashcard: () =>
          unawaited(_createFlashcardFromSelection(selection)),
      onAddToTimeline: () => unawaited(_addToTimeline(selection)),
      // Mientras se corta del original para Procesado (F41).
      onToProcessed: cuttingForProcessed(ref, widget.itemId)
          ? () => _cutToProcessed(selection)
          : null,
    );
  }

  /// «A Procesado»: el fragmento seleccionado, a la hoja de su fuente.
  void _cutToProcessed(TextSelection selection) {
    final (start, end) = _rawRange(selection);
    cutRangeToProcessed(
      context,
      ref,
      itemId: widget.itemId,
      renditionId: widget.renditionId,
      content: widget.content,
      start: start,
      end: end,
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
  Future<void> _extractSelection(TextSelection selection) {
    final (start, end) = _rawRange(selection);
    return extractRangeAsNote(
      context,
      ref,
      itemId: widget.itemId,
      renditionId: widget.renditionId,
      content: widget.content,
      start: start,
      end: end,
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
    final validHighlights = [
      for (final h in highlights)
        if (h.endOffset <= widget.content.length) h,
    ];
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
            [?_flash],
            marks: handMarks(
              context,
              validHighlights,
              to: widget.content.length,
            ),
            activeRange:
                readAloud ??
                switch (widget.playing) {
                  final playing? => (playing.start, playing.end),
                  null => null,
                },
            paints: widget.paints,
          ),
          contextMenuBuilder: _buildContextMenu,
          onSelectionChanged: (selection, cause) {
            widget.controller?._setSelection(selection);
            final tapped =
                cause == SelectionChangedCause.tap &&
                selection.isCollapsed &&
                selection.baseOffset >= 0;
            if (!tapped) return;
            final offset = _rendered.renderToRaw(selection.baseOffset);
            widget.onTapOffset?.call(offset);
            // Eligiendo palabras clave, un toque es para elegirlas, no para
            // abrir la ficha de lo que haya debajo.
            if (ref.read(studyViewProvider(widget.renditionId)).picking) return;
            if (highlightAt(validHighlights, offset) case final highlight?) {
              unawaited(openHighlightCard(context, ref, highlight));
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
              leading: Icon(
                highlight.style == HighlightStyle.underline
                    ? Icons.format_underlined
                    : Icons.highlight,
                color: HighlightPalette.line(context, highlight.color),
              ),
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
      builder: (context) => HighlightNoteDialog(
        initialNote: highlight.note,
        excerpt: highlight.excerpt,
      ),
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
///
/// Con [paints], lleva además esas capas fijas —las palabras clave de una
/// oración de un documento procesado (F41), con los colores de estudiar—,
/// debajo del amarillo de lo que se lee.
class ReadAloudText extends ConsumerWidget {
  const ReadAloudText(
    this.text, {
    required this.sourceKey,
    this.style,
    this.textAlign,
    this.selectable = false,
    this.paints = const [],
    super.key,
  });

  final String text;

  /// Con qué nombre lo conoce el lector: el `sourceKey` de los pedazos que
  /// salen de [text], con sus posiciones contadas sobre [text] tal cual.
  final String sourceKey;

  final TextStyle? style;
  final TextAlign? textAlign;
  final bool selectable;

  /// Capas fijas sobre [text], con sus posiciones contadas sobre él.
  final List<PaintedRange> paints;

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

    if (reading == null && paints.isEmpty) {
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
      paints: paints,
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
