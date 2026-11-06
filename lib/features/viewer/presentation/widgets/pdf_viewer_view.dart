import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/design/reading_scroll_physics.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_follow.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_text_provider.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_readable_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/presentation/providers/text_note_providers.dart';
import 'package:sinapsis/features/text_notes/presentation/text_note_actions.dart';
import 'package:sinapsis/features/text_notes/presentation/widgets/text_note_margin.dart';
import 'package:sinapsis/features/text_notes/presentation/widgets/text_notes_list_sheet.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/features/viewer/domain/services/pdf_study_pages.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_highlight_toolbar.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_selection.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_drag_selection.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_study_overlay.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El PDF, paginado y con zoom, igual que cualquier lector nativo —Adobe
/// Reader, el visor del sistema—.
///
/// `pdfrx` es el mismo PDFium que ya usa `PdfParser` para extraer texto (ver
/// `pdfrx_engine` en `pubspec.yaml`), con el widget de lectura completo
/// encima. Renderiza página por página bajo demanda —no carga el documento
/// entero en memoria de una vez—, así que abrir un PDF de mil páginas cuesta
/// lo mismo que uno de diez: se puede embeber directo en el detalle de un
/// elemento sin distinguir "vista previa" de "el visor de verdad", los dos
/// son el mismo widget.
///
/// Mantener apretado sobre el texto lo selecciona —y, sin levantar el dedo,
/// arrastrarlo la extiende: ver [PdfLongPressDragSelection]—, con tiradores
/// para ajustarlo y el menú "Copiar / Seleccionar todo" de `pdfrx`. Ese menú solo se puede construir dentro de
/// [PdfrxMaterialBridge]: ver ahí por qué.
///
/// Con [text], lo estudiado del documento (F36) se pinta sobre las letras de
/// cada página —ver [PdfStudyOverlay]—, y eligiendo palabras clave, tocar una
/// palabra la agrega o la saca.
///
/// **Resaltar a mano (F38).** También con [text], los resaltados de la
/// persona se pintan sobre las letras, con su color y su estilo, y lo que se
/// selecciona muestra la barrita de resaltado —la de «Texto extraído», ver
/// `documentHighlightToolbar`— en vez del menú de `pdfrx`. Tocar un
/// resaltado abre su ficha; con palabras clave en elección, el toque es de
/// ellas.
///
/// **Se escucha entero, y la lectura se sigue en la página.** También con
/// [text], ofrece al lector flotante el texto extraído del PDF de punta a
/// punta —el mismo documento que «Escuchar» de la tarjeta de estudiar, ver
/// `studyReadableDocument`—, con «Leer: Todo · Resumen · Síntesis · Palabras
/// clave», y empieza a leer en la página que se ve. Lo que suena se pinta en
/// amarillo sobre las letras del PDF —la línea u oración, o con «Palabras
/// clave», la palabra—, por encima de todo lo demás (ver
/// [PdfStudyOverlay.setReading]). Mientras la persona no lo mueva, el visor
/// sigue la lectura: cuando la línea sale de la parte cómoda de la vista, la
/// trae cerca de arriba, como quien da vuelta la hoja (ver `ReadAloudBand`).
/// Si la persona desplaza o hace zoom, la deja tranquila y ofrece «Volver a la
/// lectura» (ver `ReadAloudFollow`).
///
/// **Las notas en el texto (F45, paso 8c)**, también con [text], van sobre la
/// página: el pedazo de cada una con su subrayado fino punteado y, al costado
/// de su renglón, en el margen derecho de la página, **el globito** del color
/// de la nota, como el ícono de nota de Adobe —siguen a la página al hacer
/// zoom y al desplazarse, y el globito no crece con el zoom—. Tocar el
/// globito o el pedazo abre la tarjeta de la nota. En «Notas (N)» del marco,
/// tocar una lleva a su página y a su renglón, lo marca un momento y la abre.
///
/// Sin `Scaffold` propio a propósito: `PdfViewerScreen` lo envuelve para
/// mostrarlo a pantalla completa. En el detalle del elemento se ve su primera
/// página fija —ver `PdfFirstPagePreview`—, no este visor.
class PdfViewerView extends ConsumerStatefulWidget {
  const PdfViewerView({
    required this.path,
    this.text,
    this.title = '',
    this.initialPage,
    super.key,
  });

  final String path;

  /// La página en que se abre, desde 1: «Abrir en el original» desde un
  /// capítulo del Índice (F46, paso 4). `null`, la primera.
  final int? initialPage;

  /// El nombre del documento: lo que muestra el lector flotante.
  final String title;

  /// El texto extraído del PDF y su forma: de ahí sale lo estudiado y es
  /// donde se resalta.
  final StudyText? text;

  @override
  ConsumerState<PdfViewerView> createState() => _PdfViewerViewState();
}

class _PdfViewerViewState extends ConsumerState<PdfViewerView> {
  final _controller = PdfViewerController();
  late final _dragSelection = PdfLongPressDragSelection(_controller);
  late final _study = PdfStudyOverlay(_controller);

  /// La misma lista siempre: `pdfrx` compara los parámetros, y lo que cambia
  /// lo pinta [PdfStudyOverlay] pidiendo que se redibuje.
  late final _paintCallbacks = [_study.paintPage];

  late final DocumentSelection _selection = _PdfSelection(this);

  bool _picking = false;

  /// Si el visor sigue lo que se lee en voz alta o la persona se movió.
  final _follow = ReadAloudFollow();

  /// Cuántas veces cambió lo que suena: ubicarlo en el PDF lleva un rato, y
  /// lo que se ubicó de una línea que ya pasó no mueve la vista.
  var _followed = 0;

  ProviderSubscription<(int, int)?>? _reading;

  /// El zoom de la página, para «Apariencia» del marco de lectura (F47, paso
  /// 1); fuera de un marco no lo usa nadie.
  late final _zoom = _PdfZoom(_controller);
  ReadingFrameController? _frame;

  /// Lo que se ofrece para leer: el mismo documento mientras no cambie el
  /// texto partido ni lo estudiado.
  (ReadableDocument, Map<ReadScope, List<ReadableSegment>>, ReadableDocument)?
  _offered;

  /// Apaga la nota a la que se fue desde «Notas (N)».
  Timer? _flashTimer;

  /// Cuántas veces se fue a una nota: ubicarla lleva un rato, y lo que se
  /// ubicó de una a la que ya no se va no mueve la vista.
  var _revealed = 0;

  @override
  void initState() {
    super.initState();
    _follow.addListener(_onFollowChanged);
    _listenToReading();
  }

  @override
  void didUpdateWidget(PdfViewerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text?.renditionId != widget.text?.renditionId) {
      _reading?.close();
      _listenToReading();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final frame = ReadingFrameController.maybeOf(context);
    if (identical(frame, _frame)) return;
    _frame = frame;
    // Después del cuadro: avisarle al marco mientras se construye no se puede.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) frame?.zoom = _zoom;
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _frame?.dropZoom(_zoom);
    _zoom.dispose();
    _reading?.close();
    _follow.dispose();
    super.dispose();
  }

  /// Lo que suena del texto, desde ya: abrir el PDF mientras se lee lo pinta
  /// y va hasta ahí.
  void _listenToReading() {
    final text = widget.text;
    _reading = text == null
        ? null
        : ref.listenManual(
            readAloudHighlightProvider(text.renditionId),
            (previous, next) => _onReading(next),
            fireImmediately: true,
          );
  }

  void _onReading((int, int)? range) {
    _study.setReading(range == null ? null : (start: range.$1, end: range.$2));
    if (range != null) unawaited(_showReading(range));
  }

  /// Lleva la vista hasta [range] si el visor sigue la lectura y la línea
  /// salió de la parte cómoda de la vista. Si no la sigue, y la línea llegó
  /// sola a lo que la persona está mirando, vuelve a seguirla.
  Future<void> _showReading((int, int) range) async {
    final followed = ++_followed;
    if (!_controller.isReady) return;
    final place = await _study.placeOf((
      start: range.$1,
      end: range.$2,
    ), _controller.pages);
    if (!mounted ||
        followed != _followed ||
        place == null ||
        !_controller.isReady) {
      return;
    }
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 350);
    final letters = place.rect;
    if (letters == null) {
      // Una página escaneada: no tiene letras donde ver la línea, pero sí
      // dónde está.
      if (_follow.following && _controller.pageNumber != place.pageNumber) {
        await _controller.goToPage(
          pageNumber: place.pageNumber,
          duration: duration,
        );
      }
      return;
    }
    final view = _controller.visibleRect;
    final line = _controller.calcRectForRectInsidePage(
      pageNumber: place.pageNumber,
      rect: letters,
    );
    if (!_follow.shouldMoveTo(
      comfortable: ReadAloudBand.contains(view, line),
    )) {
      return;
    }
    await _controller.goTo(
      _controller.calcMatrixFor(ReadAloudBand.centerFor(view, line)),
      duration: duration,
    );
  }

  /// Lleva la vista a la nota `[start, end)` del texto extraído —a su página
  /// y a su renglón— y la marca un momento (F45, paso 8c): lo que hace tocar
  /// una nota en «Notas (N)». En una página escaneada, a su página.
  bool _revealNote(int start, int end) {
    if (!_controller.isReady) return false;
    final range = (start: start, end: end);
    _follow.release();
    _study.flash(range);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 2), () => _study.flash(null));
    unawaited(_goToNote(range, ++_revealed));
    return true;
  }

  Future<void> _goToNote(TextSlice range, int revealed) async {
    final place = await _study.placeOf(range, _controller.pages);
    if (!mounted ||
        revealed != _revealed ||
        place == null ||
        !_controller.isReady) {
      return;
    }
    final letters = place.rect;
    if (letters == null) {
      await _controller.goToPage(
        pageNumber: place.pageNumber,
        duration: Duration.zero,
      );
      return;
    }
    final line = _controller.calcRectForRectInsidePage(
      pageNumber: place.pageNumber,
      rect: letters,
    );
    await _controller.goTo(
      _controller.calcMatrixFor(
        ReadAloudBand.centerFor(_controller.visibleRect, line),
      ),
      duration: Duration.zero,
    );
  }

  /// Los globitos de las notas de [page] (F45, paso 8c), en el margen derecho
  /// de la página a la altura del renglón donde empieza cada una: para
  /// [PdfViewerParams.pageOverlaysBuilder], que los pone sobre la página
  /// —[pageRect] es dónde está en el visor— y los mueve con ella.
  List<Widget> _noteOverlays(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
  ) {
    final spots = _study.noteSpots(page);
    if (spots.isEmpty) return const [];
    return [
      for (final spot in spots)
        PdfNoteBubble(
          spot: spot,
          lineInPage: spot.line.toRect(
            page: page,
            scaledPageSize: pageRect.size,
          ),
          pageSize: pageRect.size,
          onOpen: (notes) => unawaited(openTextNotes(this.context, ref, notes)),
        ),
    ];
  }

  /// La persona desplazó o hizo zoom: el visor deja de seguir la lectura.
  void _onInteractionStart(ScaleStartDetails details) => _follow.release();

  /// El PDF terminó de abrirse: si ya se estaba leyendo, va hasta ahí.
  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    final text = widget.text;
    if (text == null) return;
    final range = ref.read(readAloudHighlightProvider(text.renditionId));
    if (range != null) unawaited(_showReading(range));
  }

  /// Volvió a seguir la lectura —«Volver a la lectura», otra lectura—: va
  /// hasta lo que suena.
  void _onFollowChanged() {
    final text = widget.text;
    if (!_follow.following || text == null) return;
    final range = ref.read(readAloudHighlightProvider(text.renditionId));
    if (range != null) unawaited(_showReading(range));
  }

  /// Por dónde va la vista: el comienzo de la página que se ve —ver
  /// [ReadableDocument.startAt]—. Cerrado el visor, o sin saber todavía
  /// dónde empieza cada página, `null`: se lee desde el principio.
  ReadablePlace? _placeInView() {
    final text = widget.text;
    if (!mounted || text == null || !_controller.isReady) return null;
    final page = _controller.pageNumber;
    if (page == null) return null;
    final start = _study.pageStart(page, _controller.pageCount);
    return start == null ? null : (sourceKey: text.renditionId, offset: start);
  }

  /// El texto del PDF para el lector flotante, con lo estudiado y desde
  /// dónde se empieza; `null` mientras se parte.
  ReadableDocument? _readable(StudyText text) {
    final whole = ref.watch(
      readableTextProvider((
        id: studyReadableId(text.renditionId),
        title: widget.title,
        sourceKey: text.renditionId,
        content: text.content,
        markdown: text.markdown,
      )),
    );
    final studied = ref.watch(studyReadScopesProvider(text));
    if (whole == null) return null;
    final cached = _offered;
    if (cached != null &&
        identical(cached.$1, whole) &&
        identical(cached.$2, studied)) {
      return cached.$3;
    }
    final document = whole.withScopes(studied).withStartAt(_placeInView);
    _offered = (whole, studied, document);
    return document;
  }

  /// Eligiendo palabras clave, un toque sobre una letra la agrega o la saca;
  /// cualquier otro toque sigue a la selección de siempre.
  bool _onGeneralTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    final text = widget.text;
    if (text != null && details.type == PdfViewerGeneralTapType.tap) {
      if (_picking) {
        final offset = _study.offsetAt(details.documentPosition);
        if (offset != null) {
          unawaited(
            pickStudyAt(
              ref,
              this.context,
              renditionId: text.renditionId,
              content: text.content,
              markdown: text.markdown,
              offset: offset,
            ),
          );
          return true;
        }
      } else {
        // Una nota en el texto (F45, paso 8c); la de un resaltado de antes,
        // sola, abre su resaltado, como en el texto.
        final highlight = _study.highlightAt(details.documentPosition);
        final noted = _study.notesAt(details.documentPosition);
        if (noted.isNotEmpty &&
            !noted.every((note) => note.id == highlight?.id)) {
          unawaited(openTextNotes(this.context, ref, noted));
          return true;
        }
        if (highlight != null) {
          unawaited(openHighlightCard(this.context, ref, highlight));
          return true;
        }
      }
    }
    return _dragSelection.onGeneralTap(context, controller, details);
  }

  /// La barrita de resaltado sobre lo seleccionado, con el texto de este
  /// documento; nada mientras el dedo arrastra la selección.
  Widget? _buildMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    final text = widget.text;
    final delegate = params.textSelectionDelegate;
    if (text == null ||
        _dragSelection.isDragging ||
        !delegate.hasSelectedText) {
      return null;
    }
    // Ocupa el visor entero y se para junto a la selección: `pdfrx` pone
    // tal cual un widget que ya dice dónde va.
    return Positioned.fill(
      child: documentHighlightToolbar(
        // Las acciones usan el contexto del visor: el de la barrita ya no
        // existe cuando termina un diálogo.
        this.context,
        ref,
        anchors: TextSelectionToolbarAnchors(
          primaryAnchor: params.anchorA,
          secondaryAnchor: params.anchorB,
        ),
        selection: _selection,
        text: text,
        canCopy: delegate.isCopyAllowed,
        moreActions: [
          if (!delegate.isSelectingAllText)
            HighlightToolbarAction(
              label: AdaptiveTextSelectionToolbar.getButtonLabel(
                context,
                const ContextMenuButtonItem(
                  type: ContextMenuButtonType.selectAll,
                  onPressed: null,
                ),
              ),
              onPressed: () => unawaited(delegate.selectAllText()),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    _follow.resumeOnNewReadings(ref);
    _study.playingColor = ref.watch(readingHighlightColorProvider);
    if (text != null) {
      _picking = ref.watch(studyViewProvider(text.renditionId)).picking;
      _study.update(
        content: text.content,
        // La página de un PDF es blanca también en modo oscuro.
        paints: watchStudyPaints(
          ref,
          context,
          text.renditionId,
          brightness: Brightness.light,
        ),
        scannedNotice: AppLocalizations.of(context)!.studyScannedPage,
        highlights:
            ref
                .watch(renditionHighlightsProvider(text.renditionId))
                .valueOrNull ??
            const [],
        notes:
            ref
                .watch(
                  placedTextNotesProvider((
                    target: textNoteTargetOf(text),
                    content: text.content,
                  )),
                )
                .valueOrNull ??
            const [],
      );
    }
    final drag = _dragSelection;
    final viewer = PdfrxMaterialBridge(
      child: Listener(
        onPointerDown: drag.onPointerDown,
        onPointerMove: drag.onPointerMove,
        onPointerUp: drag.onPointerUp,
        onPointerCancel: drag.onPointerUp,
        child: PdfViewer.file(
          widget.path,
          controller: _controller,
          // Una página que el PDF no tiene la acota `pdfrx` a la última.
          initialPageNumber: math.max(1, widget.initialPage ?? 1),
          params: PdfViewerParams(
            // Un fondo neutro entre página y página, para que se distinga
            // dónde termina una y empieza la otra al scrollear — lo mismo
            // que hace cualquier lector de PDF de verdad.
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
            // La física de una lista —la de la plataforma, y más enérgica al
            // soltar con impulso—, no la de un visor con zoom: con la de
            // pdfrx por defecto un arrastre rápido se frenaba enseguida y
            // pasar hojas pedía un gesto por página (pedido del usuario).
            scrollPhysics: ReadingScrollPhysics(
              parent: PdfViewerParams.getScrollPhysics(context),
            ),
            onGeneralTap: _onGeneralTap,
            onInteractionStart: _onInteractionStart,
            onViewerReady: _onViewerReady,
            pagePaintCallbacks: _paintCallbacks,
            // Los globitos de las notas, sobre cada página (F45, paso 8c).
            pageOverlaysBuilder: text == null ? null : _noteOverlays,
            // Sin el texto del documento no hay dónde guardar un resaltado:
            // el menú de `pdfrx`, Copiar y Seleccionar todo.
            buildContextMenu: text == null ? null : _buildMenu,
            customizeContextMenuItems: _dragSelection.hideMenuWhileDragging,
            textSelectionParams: const PdfTextSelectionParams(
              buildSelectionHandle: buildPdfSelectionHandle,
              // Sin la lupa que `pdfrx` pone sobre el renglón al arrastrar
              // un tirador: el usuario no la quiere (F22).
              magnifier: PdfViewerSelectionMagnifierParams(enabled: false),
            ),
          ),
        ),
      ),
    );
    if (text == null) return viewer;
    // Las notas del texto, para «Notas (N)» del marco: tocar una lleva a su
    // lugar en la página.
    return ReadingNotesOffer(
      sources: [
        TextNoteSource(
          target: textNoteTargetOf(text),
          content: text.content,
          reveal: _revealNote,
        ),
      ],
      child: ReadableRegion(
        document: _readable(text),
        child: Stack(
          children: [
            Positioned.fill(child: viewer),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: ReadAloudBackToReading(
                  sourceKey: text.renditionId,
                  follow: _follow,
                  onPressed: _follow.resume,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El globito de las notas de un renglón sobre la página de un PDF (F45, paso
/// 8c), como el ícono de nota de Adobe: en el margen derecho de la página, a
/// la altura de [lineInPage] —el renglón donde empiezan, en coordenadas de la
/// página dibujada, de [pageSize]—, del color de la primera, con el número si
/// son varias. Mide lo mismo con cualquier zoom; se toca en un cuadrado de
/// [touchSize] que no le quita al visor ni el arrastre ni el zoom
/// (`PdfOverlayInteractionRegion`). Para el lector de pantalla, lo mismo que
/// el globito del texto.
class PdfNoteBubble extends StatelessWidget {
  const PdfNoteBubble({
    required this.spot,
    required this.lineInPage,
    required this.pageSize,
    required this.onOpen,
    super.key,
  });

  final PdfNoteSpot spot;
  final Rect lineInPage;
  final Size pageSize;
  final ValueChanged<List<TextNote>> onOpen;

  /// Lo que mide el dibujo, como el ícono de nota de un lector de PDF.
  static const size = 24.0;

  /// Lo que mide donde se toca.
  static const touchSize = 40.0;

  /// Dónde va, dentro de la página: pegado al borde derecho y centrado en el
  /// renglón, sin salirse de ella.
  static Rect placeIn(Size pageSize, Rect line) {
    final left = math.max(0, pageSize.width - touchSize - 2).toDouble();
    final top = (line.center.dy - touchSize / 2).clamp(
      0.0,
      math.max(0, pageSize.height - touchSize).toDouble(),
    );
    return Rect.fromLTWH(left, top, touchSize, touchSize);
  }

  @override
  Widget build(BuildContext context) {
    final notes = spot.notes;
    void open() => onOpen(notes);
    return Positioned.fromRect(
      rect: placeIn(pageSize, lineInPage),
      child: TextNoteBubbleSemantics(
        notes: notes,
        onTap: open,
        child: PdfOverlayInteractionRegion(
          onTap: (_) {
            open();
            return true;
          },
          child: Center(
            child: TextNoteBubbleFace(notes: notes, size: size, onPaper: true),
          ),
        ),
      ),
    );
  }
}

/// El zoom del PDF para «Apariencia» del marco (F47, paso 1): cuánto se
/// acercó respecto de la página a lo ancho, acercar y alejar a los pasos de
/// `pdfrx` —los mismos del doble toque— y volver al ancho.
class _PdfZoom implements ReadingZoom {
  _PdfZoom(this._controller) {
    _controller.addListener(_update);
  }

  final PdfViewerController _controller;

  @override
  final ValueNotifier<double> level = ValueNotifier(1);

  void _update() {
    if (!_controller.isReady) return;
    final cover = _controller.coverScale;
    if (cover > 0) level.value = _controller.currentZoom / cover;
  }

  @override
  void zoomIn() {
    if (_controller.isReady) unawaited(_controller.zoomUp());
  }

  @override
  void zoomOut() {
    if (_controller.isReady) unawaited(_controller.zoomDown());
  }

  @override
  void fit() {
    if (!_controller.isReady) return;
    unawaited(
      _controller.setZoom(_controller.centerPosition, _controller.coverScale),
    );
  }

  void dispose() {
    _controller.removeListener(_update);
    level.dispose();
  }
}

/// La selección del PDF como la ve quien arma el menú (F38): lo seleccionado
/// en `pdfrx`, llevado al texto extraído con [PdfStudyOverlay].
class _PdfSelection implements DocumentSelection {
  _PdfSelection(this._state);

  final _PdfViewerViewState _state;

  PdfTextSelectionDelegate get _delegate =>
      _state._controller.textSelectionDelegate;

  @override
  Future<String> text() => _delegate.getSelectedText();

  @override
  Future<SelectionLocation> locate() async {
    final controller = _state._controller;
    if (!controller.isReady || !_delegate.hasSelectedText) {
      return const SelectionLocation.failed(HighlightIssue.nothingSelected);
    }
    final ranges = await _delegate.getSelectedTextRanges();
    if (ranges.isEmpty) {
      return const SelectionLocation.failed(HighlightIssue.nothingSelected);
    }
    return _state._study.locateSelection(ranges, controller.pages);
  }

  @override
  Future<HighlightOutcome> highlight({
    HighlightColor? color,
    HighlightStyle style = HighlightStyle.fill,
    String? note,
  }) async {
    final text = _state.widget.text;
    if (text == null) {
      return const HighlightOutcome.issue(HighlightIssue.nothingSelected);
    }
    final location = await locate();
    final issue = location.issue;
    if (issue != null) return HighlightOutcome.issue(issue);
    // Pudo pasar tiempo —leyendo páginas— y el visor cerrarse.
    if (!_state.mounted) {
      return const HighlightOutcome.issue(HighlightIssue.nothingSelected);
    }
    return saveHighlights(
      _state.ref.read(organizeRepositoryProvider),
      renditionId: text.renditionId,
      content: text.content,
      slices: location.slices,
      color: color,
      style: style,
      note: note,
    );
  }

  @override
  Future<void> clear() => _delegate.clearTextSelection();
}

/// El lado del área táctil de un tirador: más grande que lo que se ve, para
/// que se agarre con el dedo sin buscarlo.
const pdfSelectionHandleTouchSize = 40.0;

/// El diámetro de la gota que se ve.
const _handleDiameter = 22.0;

/// Los tiradores de la selección de texto del PDF: una gota —un círculo con
/// una punta que toca la letra—, como los de Material y Google Lens, en vez
/// del triángulo de `pdfrx` (F22, pedido del usuario).
///
/// `pdfrx` pone el tirador del principio arriba y a la izquierda de la
/// primera letra —la esquina de abajo a la derecha del tirador toca la
/// letra— y el del final abajo y a la derecha de la última —la esquina de
/// arriba a la izquierda—. La gota se dibuja en esa esquina, con la punta
/// ahí; el resto del área táctil es transparente.
Widget? buildPdfSelectionHandle(
  BuildContext context,
  PdfTextSelectionAnchor anchor,
  PdfViewerTextSelectionAnchorHandleState state,
) {
  final tip = pdfSelectionHandleTip(
    start: anchor.type == PdfTextSelectionAnchorType.a,
    // En un texto de derecha a izquierda, `pdfrx` los pone del lado
    // opuesto.
    rightToLeft:
        anchor.direction == PdfTextDirection.rtl ||
        anchor.direction == PdfTextDirection.vrtl,
  );
  final color = Theme.of(context).colorScheme.primary;
  return SizedBox.square(
    dimension: pdfSelectionHandleTouchSize,
    child: ColoredBox(
      color: Colors.transparent,
      child: Align(
        alignment: tip,
        child: _Teardrop(
          tip: tip,
          color: state == PdfViewerTextSelectionAnchorHandleState.dragging
              ? color
              : color.withValues(alpha: 0.9),
          elevated: state != PdfViewerTextSelectionAnchorHandleState.dragging,
        ),
      ),
    ),
  );
}

/// La esquina del tirador que toca la letra —donde va la punta de la
/// gota—, según dónde lo pone `pdfrx`: ver [buildPdfSelectionHandle].
Alignment pdfSelectionHandleTip({
  required bool start,
  required bool rightToLeft,
}) => switch ((start, rightToLeft)) {
  (true, false) => Alignment.bottomRight,
  (true, true) => Alignment.bottomLeft,
  (false, false) => Alignment.topLeft,
  (false, true) => Alignment.topRight,
};

class _Teardrop extends StatelessWidget {
  const _Teardrop({
    required this.tip,
    required this.color,
    required this.elevated,
  });

  /// La esquina con punta: la que toca la letra.
  final Alignment tip;
  final Color color;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    const round = Radius.circular(_handleDiameter / 2);
    return Container(
      width: _handleDiameter,
      height: _handleDiameter,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: tip == Alignment.topLeft ? Radius.zero : round,
          topRight: tip == Alignment.topRight ? Radius.zero : round,
          bottomLeft: tip == Alignment.bottomLeft ? Radius.zero : round,
          bottomRight: tip == Alignment.bottomRight ? Radius.zero : round,
        ),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
    );
  }
}

/// Les da a los widgets de `pdfrx` las traducciones y el tema que esperan.
///
/// Desde la 2.5.0, `pdfrx` arma sus widgets —el menú de copiar, entre
/// otros— con `material_ui`, una **copia** de Material publicada aparte,
/// con sus propias clases: su `MaterialLocalizations` y su `Theme` son de
/// otro tipo que los de `package:flutter/material.dart`, que es lo que usa
/// esta app. Sin este puente, `MaterialLocalizations.of` de `material_ui` no
/// encuentra nada: en Android, mantener apretado sobre el texto seleccionaba
/// bien, pero el menú reventaba al pedir la etiqueta "Copiar" y la versión
/// release lo reemplazaba por el recuadro gris de error de Flutter, del
/// tamaño del visor entero (F22). Las traducciones heredan el idioma de la
/// app; el tema copia los colores y la tipografía del tema de la app, para
/// que el menú se vea igual que el resto —modo oscuro incluido— y no con el
/// tema de respaldo claro de `material_ui`.
///
/// Si algún día la app migra entera a `material_ui`, este puente sobra.
class PdfrxMaterialBridge extends StatelessWidget {
  const PdfrxMaterialBridge({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Localizations.override(
      context: context,
      delegates: const [mui.GlobalMaterialLocalizations.delegate],
      child: mui.Theme(
        data: mui.ThemeData(
          colorScheme: _colorScheme(theme.colorScheme),
          fontFamily: theme.textTheme.bodyMedium?.fontFamily,
        ),
        child: child,
      ),
    );
  }

  static mui.ColorScheme _colorScheme(ColorScheme c) => mui.ColorScheme(
    brightness: c.brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryContainer,
    onPrimaryContainer: c.onPrimaryContainer,
    secondary: c.secondary,
    onSecondary: c.onSecondary,
    secondaryContainer: c.secondaryContainer,
    onSecondaryContainer: c.onSecondaryContainer,
    tertiary: c.tertiary,
    onTertiary: c.onTertiary,
    error: c.error,
    onError: c.onError,
    surface: c.surface,
    onSurface: c.onSurface,
    surfaceContainerLowest: c.surfaceContainerLowest,
    surfaceContainerLow: c.surfaceContainerLow,
    surfaceContainer: c.surfaceContainer,
    surfaceContainerHigh: c.surfaceContainerHigh,
    surfaceContainerHighest: c.surfaceContainerHighest,
    onSurfaceVariant: c.onSurfaceVariant,
    outline: c.outline,
    outlineVariant: c.outlineVariant,
    shadow: c.shadow,
    scrim: c.scrim,
    inverseSurface: c.inverseSurface,
    onInverseSurface: c.onInverseSurface,
    inversePrimary: c.inversePrimary,
    surfaceTint: c.surfaceTint,
  );
}
