import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/features/library/presentation/widgets/summarize_button.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_follow.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_selection_aloud.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_text_provider.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_readable_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_pagination.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El contenido ya extraído de un documento —un DOCX, un EPUB, un `.txt`—,
/// en un modo de lectura propio: tipografía más grande, márgenes generosos
/// y una tarjeta con la forma de una página, en vez de la vista compacta
/// que ya tiene el detalle del elemento.
///
/// No es un renderizador de DOCX ni de EPUB de verdad —esta app no
/// reconstruye la maquetación original, página por página, como haría Word
/// o un lector de EPUB dedicado—: muestra el texto que ya extrajo
/// `DocxParser`/`EpubParser`, con el mismo formato Markdown con el que se
/// guardó, pero pensado para leer de corrido en vez de mirar de pasada. Ver
/// la decisión 3 en docs/arquitectura.md sobre por qué esta app construye
/// sus propios lectores en vez de sumar un renderizador de formato cerrado:
/// nadie mantiene un motor de maquetación de DOCX en Flutter, y uno que se
/// abandone dejaría la lectura rota de un día para el otro.
///
/// **Paginado, no un solo scroll infinito.** [splitIntoReaderPages] corta
/// [content] antes de que esta pantalla le ponga formato a una sola letra;
/// `PageView.builder` arma —y descarta— una página Markdown por vez, así
/// que abrir un libro de mil páginas cuesta lo mismo que abrir uno de diez.
/// Ver el comentario de esa función para por qué hace falta.
///
/// **Ir a página, no solo pasar de a una.** Ver la decisión 24 en
/// docs/arquitectura.md. La letra —cuál y de qué tamaño— es la de
/// «Apariencia» del marco de lectura (F47, paso 1), la misma en todos los
/// lectores; los capítulos van en «Contenido».
///
/// Sin `Scaffold` propio a propósito: el marco de lectura lo pone como cuerpo
/// a pantalla completa (`DocumentReaderScreen`, `OriginalView`), y
/// `EmbeddedFileViewer` lo embebe tal cual dentro de un marco acotado en el
/// detalle del elemento.
///
/// **Se lee en voz alta, entero (F25).** Ofrece al lector flotante el libro de
/// punta a punta —partido fuera del hilo de la pantalla si es largo, ver
/// `readableTextProvider`—, y empieza a leer en la página que se ve. Con
/// [study] es el mismo documento que «Escuchar» de la tarjeta de estudiar
/// —el mismo id, los mismos pedazos, las posiciones del texto entero—: lo que
/// se empezó a escuchar ahí sigue acá sin volver a empezar, y al revés.
/// Mientras lee, la línea va en amarillo —con «Palabras clave», solo la
/// palabra— y el lector **sigue la lectura**: da vuelta la página y, dentro
/// de una página más alta que la pantalla, se desplaza hasta la línea. Si la
/// persona pasa de página o desplaza a mano, la deja tranquila y ofrece
/// «Volver a la lectura» (ver `ReadAloudFollow`). Lo mismo en el marco del
/// texto largo del detalle: lo que ofrece va por encima de lo del detalle,
/// que no trae ese texto, y seguir la lectura mueve el marco, no el detalle.
///
/// **Lo estudiado se pinta en la página (F36).** Con [study], las
/// oraciones del resumen o de la síntesis y las palabras clave se ven con sus
/// colores de resaltador, y eligiendo palabras clave, tocar una la agrega o
/// la saca. Cada página es un tramo tal cual de [content] —ver
/// [readerPageRanges]—, así que lo marcado cae en su lugar sin traducir nada.
/// Los botones de estudiar van arriba, en el original (F45, paso 7b:
/// `OriginalView`), el mismo en Procesado y en la Biblioteca; abajo, sin
/// [study], «Resumir con IA».
///
/// **Se resalta a mano (F38).** Con [study], [content] es el texto extraído
/// del elemento, así que lo que se resalta acá son los mismos resaltados de
/// «Texto extraído»: seleccionar abre la barrita con los colores, Subrayar,
/// Copiar, Escuchar, Nota, Extraer como nota y Hacer tarjeta, y tocar algo
/// ya resaltado abre su ficha. Entre las capas, lo que subrayó la persona va
/// encima de las oraciones y debajo de las palabras clave. Sin [study] —un
/// adjunto, que no es el texto de ningún elemento—, el menú de siempre.
class DocumentReaderView extends ConsumerStatefulWidget {
  const DocumentReaderView({
    required this.title,
    required this.content,
    this.markdown = true,
    this.controlsAtBottom = false,
    this.study,
    super.key,
  });

  /// El nombre del documento: lo que muestra el lector flotante (F25).
  final String title;

  final String content;

  /// Si [content] es Markdown y se muestra con formato, o texto tal cual
  /// (F22): ver `TextResolvedViewer.markdown`.
  final bool markdown;

  /// Si los controles de abajo —resumir, pasar de página— quedan contra el
  /// borde de abajo de la pantalla, como a pantalla completa: el lector
  /// flotante se para encima de ellos en vez de tapar "siguiente" (F25).
  /// Embebido en el detalle se desplazan con el resto, y no hay nada que
  /// esquivar.
  final bool controlsAtBottom;

  /// El texto que se estudia, si [content] es ese texto (F36); sin él —un
  /// adjunto, que no se estudia—, no se pinta nada.
  final StudyText? study;

  @override
  ConsumerState<DocumentReaderView> createState() => _DocumentReaderViewState();
}

class _DocumentReaderViewState extends ConsumerState<DocumentReaderView> {
  /// Dónde está cada página, o `null` mientras se parte el libro. Uno largo
  /// se parte en otro hilo —recorre todo el texto—, y entretanto se ve un
  /// indicador; uno corto, en el momento.
  List<({int start, int end})>? _ranges;

  /// Las páginas, o ninguna mientras se parte el libro.
  List<({int start, int end})> get _pages => _ranges ?? const [];

  /// Cuántas páginas tiene el libro; 0 mientras se parte.
  int get _pageCount => _pages.length;

  /// El texto de la página [index], cortado recién cuando se pide: copiar las
  /// mil páginas de un libro al abrirlo costaría lo que no cuesta mostrarlo.
  String _pageText(int index) {
    final range = _pages[index];
    return widget.content.substring(range.start, range.end);
  }

  late final _controller = PageController();
  var _pageIndex = 0;

  /// Con qué nombre conoce el lector flotante a este texto: el de su forma si
  /// se estudia —el mismo que en «Texto extraído» y en la tarjeta de
  /// estudiar—; si no, uno propio del contenido. Las posiciones de lo que lee
  /// son siempre las del texto entero, y cada página resalta lo suyo.
  late final String _sourceKey =
      widget.study?.renditionId ?? 'reader:${widget.content.hashCode}';

  /// El libro entero, para el lector flotante. Con [DocumentReaderView.study]
  /// es lo mismo que ofrece «Escuchar» de la tarjeta de estudiar —ver
  /// `studyReadableDocument`—: el mismo id, el texto y si es Markdown del
  /// texto que se estudia.
  late final ReadableText _readableText = switch (widget.study) {
    final study? => (
      id: studyReadableId(study.renditionId),
      title: widget.title,
      sourceKey: _sourceKey,
      content: study.content,
      markdown: study.markdown,
    ),
    null => (
      id: _sourceKey,
      title: widget.title,
      sourceKey: _sourceKey,
      content: widget.content,
      markdown: widget.markdown,
    ),
  };

  /// Lo que se ofrece ahora: el mismo documento mientras no cambie el libro
  /// partido ni lo estudiado.
  (ReadableDocument, Map<ReadScope, List<ReadableSegment>>, ReadableDocument)?
  _offered;

  /// Si el lector sigue la lectura o la persona se fue a otro lado.
  final _follow = ReadAloudFollow();

  /// El marco de lectura de arriba, si lo hay: a su «Contenido» van los
  /// capítulos del libro, una vez.
  ReadingFrameController? _frame;
  var _outlined = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frame = ReadingFrameController.maybeOf(context);
    _outlineSoon();
  }

  /// Los títulos del libro, cada uno con su página, para «Contenido» del
  /// marco: se buscan en otro hilo si el libro es largo, y se mandan cuando
  /// ya se sabe en qué página cae cada uno.
  void _outlineSoon() {
    final frame = _frame;
    if (_outlined || frame == null || !widget.markdown || _ranges == null) {
      return;
    }
    _outlined = true;
    unawaited(() async {
      final headings = await readerHeadingsOff(widget.content);
      if (!mounted || headings.isEmpty) return;
      final l10n = AppLocalizations.of(context)!;
      frame.outline = [
        for (final (index, heading) in headings.indexed)
          ReadingOutlineEntry(
            key: Key('reader-outline-$index'),
            label: heading.text,
            depth: heading.level - 1,
            detail: l10n.documentReaderPageOf(
              _pageAt(heading.offset) + 1,
              _pageCount,
            ),
            onSelected: () {
              if (_controller.hasClients) {
                _controller.jumpToPage(_pageAt(heading.offset));
              }
            },
          ),
      ];
    }());
  }

  @override
  void initState() {
    super.initState();
    if (widget.content.length <= kReaderInlineChars) {
      _ranges = readerPageRanges(widget.content);
    } else {
      unawaited(_paginate());
    }
    _follow.addListener(_onFollowChanged);
    // Lo que suena, desde ya: abrir el libro mientras se lee lleva a la
    // página de lo que suena.
    ref.listenManual(
      readAloudHighlightProvider(_sourceKey),
      (previous, next) => _followReading(next),
      fireImmediately: true,
    );
  }

  Future<void> _paginate() async {
    final ranges = await readerPageRangesOff(widget.content);
    if (!mounted) return;
    setState(() => _ranges = ranges);
    _outlineSoon();
    // Lo que suena, ahora que se sabe en qué página cae.
    _followReading(ref.read(readAloudHighlightProvider(_sourceKey)));
  }

  @override
  void dispose() {
    _controller.dispose();
    _follow.dispose();
    super.dispose();
  }

  ReadableDocument? _offer(
    ReadableDocument? book,
    Map<ReadScope, List<ReadableSegment>> studied,
  ) {
    if (book == null) return null;
    final cached = _offered;
    if (cached != null &&
        identical(cached.$1, book) &&
        identical(cached.$2, studied)) {
      return cached.$3;
    }
    final document = book.withScopes(studied).withStartAt(_placeInView);
    _offered = (book, studied, document);
    return document;
  }

  /// Por dónde va la vista: el comienzo de la página que se ve. Un tear-off
  /// de este objeto, el mismo en cada cuadro —ver
  /// [ReadableDocument.startAt]—; cerrado el libro ya no hay vista.
  ReadablePlace? _placeInView() {
    if (!mounted || _pages.isEmpty) return null;
    return (sourceKey: _sourceKey, offset: _pages[_pageIndex].start);
  }

  /// La página donde está la posición [offset] del texto entero: la última
  /// que empieza ahí o antes.
  int _pageAt(int offset) {
    var low = 0;
    var high = _pages.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_pages[middle].start <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// Lo que suena pasó a [range]: si está en otra página, se la da vuelta —a
  /// la de al lado con la animación de siempre; más lejos, de un salto, sin
  /// armar las del medio—. Dentro de la página, la acerca la página misma.
  void _followReading((int, int)? range) {
    if (range == null || !_follow.following || _pages.isEmpty) return;
    final page = _pageAt(range.$1);
    if (page == _pageIndex) return;
    if (!_controller.hasClients) {
      // Recién abierto: el `PageView` todavía no se armó.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _followReading(ref.read(readAloudHighlightProvider(_sourceKey)));
        }
      });
      return;
    }
    if ((page - _pageIndex).abs() == 1 &&
        !MediaQuery.disableAnimationsOf(context)) {
      _goTo(page);
    } else {
      _controller.jumpToPage(page);
    }
  }

  /// Se pasó a la página [index]. A otra que la de lo que suena —a mano—, el
  /// lector deja de seguir la lectura; a la de lo que suena, la sigue: así
  /// llega siempre el lector cuando da vuelta solo, y así la retoma la
  /// persona volviendo a mano.
  void _onPageChanged(int index) {
    setState(() => _pageIndex = index);
    final reading = ref.read(readAloudHighlightProvider(_sourceKey));
    if (reading == null) return;
    if (_pageAt(reading.$1) == index) {
      _follow.resume();
    } else {
      _follow.release();
    }
  }

  /// La persona desplazó a mano la página [page]: si es la de lo que suena,
  /// deja de seguirla.
  void _onPageScrolledByHand(int page) {
    final reading = ref.read(readAloudHighlightProvider(_sourceKey));
    if (reading != null && _pageAt(reading.$1) == page) _follow.release();
  }

  /// Volvió a seguir la lectura —«Volver a la lectura», otra lectura—: va a
  /// la página de lo que suena; ahí, la página la acerca.
  void _onFollowChanged() {
    if (!_follow.following) return;
    _followReading(ref.read(readAloudHighlightProvider(_sourceKey)));
  }

  void _goTo(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openPagePicker(AppLocalizations l10n) async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) =>
          _PagePickerDialog(current: _pageIndex, total: _pageCount),
    );
    if (chosen != null) _goTo(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appearance = ref.watch(readingAppearanceProvider);
    _follow.resumeOnNewReadings(ref);

    if (_ranges == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pageCount == 0) return const SizedBox.shrink();

    final studied = switch (widget.study) {
      final study? => ref.watch(studyReadScopesProvider(study)),
      null => const <ReadScope, List<ReadableSegment>>{},
    };

    return ReadableRegion(
      document: _offer(ref.watch(readableTextProvider(_readableText)), studied),
      child: _buildReader(l10n, appearance),
    );
  }

  Widget _buildReader(AppLocalizations l10n, ReadingAppearance appearance) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pageCount > 1)
          LinearProgressIndicator(value: (_pageIndex + 1) / _pageCount),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _buildPages(appearance)),
              // Arriba de la página.
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: ReadAloudBackToReading(
                    sourceKey: _sourceKey,
                    follow: _follow,
                    onPressed: _follow.resume,
                  ),
                ),
              ),
            ],
          ),
        ),
        ReadAloudClearance(
          enabled: widget.controlsAtBottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sin texto que se estudia —un adjunto—, resumir la página.
              if (widget.study == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [SummarizeButton(content: _pageText(_pageIndex))],
                  ),
                ),
              if (_pageCount > 1)
                _PageControls(
                  label: l10n.documentReaderPageOf(_pageIndex + 1, _pageCount),
                  onLabelTap: () => _openPagePicker(l10n),
                  onPrevious: _pageIndex > 0
                      ? () => _goTo(_pageIndex - 1)
                      : null,
                  onNext: _pageIndex < _pageCount - 1
                      ? () => _goTo(_pageIndex + 1)
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPages(ReadingAppearance appearance) {
    return PageView.builder(
      controller: _controller,
      itemCount: _pageCount,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) => _ReaderPage(
        content: _pageText(index),
        start: _pages[index].start,
        appearance: appearance,
        markdown: widget.markdown,
        sourceKey: _sourceKey,
        follow: _follow,
        onScrolledByHand: () => _onPageScrolledByHand(index),
        study: switch (widget.study) {
          final study? => (
            itemId: study.itemId,
            renditionId: study.renditionId,
            content: widget.content,
            markdown: study.markdown,
          ),
          null => null,
        },
      ),
    );
  }
}

/// Una página del libro: el mismo formato de tarjeta que tenía la pantalla
/// entera antes de paginarse, ahora acotado a lo que entra en una página.
/// Lo que lee el lector flotante, en amarillo (F25), y lo estudiado con
/// sus colores (F36).
///
/// Si la página es más alta que la pantalla —letra grande—, mientras el
/// lector sigue la lectura se desplaza sola hasta la línea que suena, sin
/// moverse mientras esa línea se vea cómoda (ver `ReadAloudBand`).
class _ReaderPage extends ConsumerStatefulWidget {
  const _ReaderPage({
    required this.content,
    required this.start,
    required this.appearance,
    required this.markdown,
    required this.sourceKey,
    required this.follow,
    required this.onScrolledByHand,
    required this.study,
  });

  final String content;

  /// Dónde empieza [content] en el texto entero: lo que se lee, lo estudiado y
  /// lo resaltado a mano guardan posiciones del texto entero.
  final int start;

  /// La letra, su tamaño y el color de lo que suena: los de «Apariencia».
  final ReadingAppearance appearance;
  final bool markdown;

  /// Con qué nombre conoce el lector flotante al texto entero.
  final String sourceKey;

  final ReadAloudFollow follow;

  /// La persona desplazó la página con el dedo.
  final VoidCallback onScrolledByHand;

  /// El texto entero que se estudia.
  final ({String itemId, String renditionId, String content, bool markdown})?
  study;

  @override
  ConsumerState<_ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<_ReaderPage> {
  final _scroll = ScrollController();
  final _textKey = GlobalKey();

  /// El texto de la página con formato, de la última vez que se armó: de ahí
  /// sale dónde se ve cada posición.
  RenderedMarkdown? _rendered;

  ({String sourceKey, int from, int to}) get _span => (
    sourceKey: widget.sourceKey,
    from: widget.start,
    to: widget.start + widget.content.length,
  );

  @override
  void initState() {
    super.initState();
    widget.follow.addListener(_onFollowChanged);
    // Recién armada —se dio vuelta hasta acá—, con lo que suena adentro.
    _revealSoon(ref.read(readAloudSpanProvider(_span)));
  }

  @override
  void didUpdateWidget(_ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.follow != widget.follow) {
      oldWidget.follow.removeListener(_onFollowChanged);
      widget.follow.addListener(_onFollowChanged);
    }
  }

  @override
  void dispose() {
    widget.follow.removeListener(_onFollowChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onFollowChanged() {
    if (!widget.follow.following) return;
    _revealSoon(ref.read(readAloudSpanProvider(_span)));
  }

  /// Acerca [span] —lo que suena, en posiciones de la página— después del
  /// cuadro en que se pinta.
  void _revealSoon((int, int)? span) {
    if (span == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(span);
    });
  }

  /// Desplaza la página para que [span] quede en la franja cómoda de la
  /// vista, si el lector sigue la lectura y no está ya ahí (ver
  /// `ReadAloudFollow.shouldMoveTo`).
  void _reveal((int, int) span) {
    final rendered = _rendered;
    final editable = _editable();
    if (rendered == null || editable == null || !_scroll.hasClients) return;
    final boxes = editable.getBoxesForSelection(
      TextSelection(
        baseOffset: rendered.rawToRender(span.$1),
        extentOffset: rendered.rawToRender(span.$2),
      ),
    );
    if (boxes.isEmpty) return;
    var line = boxes.first.toRect();
    for (final box in boxes.skip(1)) {
      line = line.expandToInclude(box.toRect());
    }
    final viewport = RenderAbstractViewport.maybeOf(editable);
    if (viewport == null) return;
    final position = _scroll.position;
    // Con la línea arriba de todo; de ahí, cualquier otra altura.
    final atTop = viewport.getOffsetToReveal(editable, 0, rect: line).offset;
    final extent = position.viewportDimension;
    final view = Rect.fromLTWH(0, position.pixels, 1, extent);
    final shown = Rect.fromLTWH(0, atTop, 1, line.height);
    final comfortable = ReadAloudBand.contains(view, shown);
    if (!widget.follow.shouldMoveTo(comfortable: comfortable)) return;
    final target = (atTop - extent * ReadAloudBand.landing).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 1) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      unawaited(
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  /// El texto que se ve, para saber dónde queda cada letra.
  RenderEditable? _editable() {
    RenderEditable? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderEditable) {
        found = object;
      } else {
        object.visitChildren(visit);
      }
    }

    final root = _textKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final appearance = widget.appearance;
    final markdown = widget.markdown;
    final pageStart = widget.start;
    final theme = Theme.of(context);
    final reading = ref.watch(readAloudSpanProvider(_span));
    ref.listen(readAloudSpanProvider(_span), (_, next) => _revealSoon(next));
    final study = widget.study;
    final paints = study == null
        ? const <PaintedRange>[]
        : paintsWithin(
            watchStudyPaints(ref, context, study.renditionId),
            pageStart,
            pageStart + content.length,
          );
    // Lo subrayado a mano de esta página, en posiciones de la página. Los que
    // ya no entran en el texto —la forma se regeneró— no se pintan.
    final highlights = study == null
        ? const <Highlight>[]
        : [
            for (final highlight
                in ref
                        .watch(renditionHighlightsProvider(study.renditionId))
                        .valueOrNull ??
                    const <Highlight>[])
              if (highlight.endOffset <= study.content.length) highlight,
          ];
    final marks = study == null
        ? const <HandMark>[]
        : handMarks(
            context,
            highlights,
            from: pageStart,
            to: pageStart + content.length,
          );
    final rendered = _rendered = markdown
        ? RenderedMarkdown.parse(content)
        : RenderedMarkdown.plain(content);

    // La columna de lectura del marco (F47, paso 1): de ancho cómodo, con los
    // márgenes de un libro y sin la tarjeta de papel de antes.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: readingColumnWidth),
        child: Padding(
          padding: readingColumnPadding(context).copyWith(top: 16, bottom: 16),
          child: NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (notification.depth == 0 &&
                  notification.direction != ScrollDirection.idle) {
                widget.onScrolledByHand();
              }
              return false;
            },
            // La física de la plataforma: dentro de una página se lee de
            // corrido; las hojas se pasan con el `PageView` (F45, mejora 13).
            child: SingleChildScrollView(
              controller: _scroll,
              child: SelectableText.rich(
                key: _textKey,
                rendered.buildSpans(
                  theme,
                  const [],
                  baseStyle: appearance.bodyStyle(theme),
                  activeRange: reading,
                  playing: appearance.highlight.color,
                  paints: paints,
                  marks: marks,
                ),
                // Eligiendo palabras clave, tocar una la agrega o la saca; si
                // no, tocar algo ya resaltado abre su ficha.
                onSelectionChanged: study == null
                    ? null
                    : (selection, cause) {
                        if (cause != SelectionChangedCause.tap ||
                            !selection.isCollapsed ||
                            selection.baseOffset < 0) {
                          return;
                        }
                        final offset =
                            pageStart +
                            rendered.renderToRaw(selection.baseOffset);
                        if (ref
                            .read(studyViewProvider(study.renditionId))
                            .picking) {
                          unawaited(
                            pickStudyAt(
                              ref,
                              context,
                              renditionId: study.renditionId,
                              content: study.content,
                              markdown: study.markdown,
                              offset: offset,
                            ),
                          );
                        } else if (highlightAt(highlights, offset)
                            case final highlight?) {
                          unawaited(openHighlightCard(context, ref, highlight));
                        }
                      },
                contextMenuBuilder: (menuContext, editable) {
                  final selection = editable.textEditingValue.selection;
                  // La selección, en posiciones de [content] —la página— y en
                  // las del texto entero, que es donde se guarda todo.
                  (int, int) pageRange() => (
                    rendered.renderToRaw(selection.start),
                    rendered.renderToRaw(selection.end, isEnd: true),
                  );
                  (int, int) textRange() {
                    final (start, end) = pageRange();
                    return (pageStart + start, pageStart + end);
                  }

                  // "Leer en voz alta" lee las líneas que toca la selección, en
                  // las posiciones del texto entero.
                  void readAloud() {
                    final (start, end) = pageRange();
                    final (from, to) = textRange();
                    unawaited(
                      readSelectionAloud(
                        ref,
                        text: content.substring(start, end),
                        sourceKey: widget.sourceKey,
                        start: from,
                        end: to,
                      ),
                    );
                  }

                  // Sin el texto de un elemento al que atar un resaltado, el
                  // menú de la app de siempre.
                  if (study == null) {
                    return buildSelectionMenu(
                      menuContext,
                      editable,
                      onReadAloud: readAloud,
                    );
                  }
                  // Las acciones usan el contexto de la página: el del menú ya
                  // no existe cuando termina un diálogo.
                  return buildHighlightMenu(
                    menuContext,
                    ref,
                    editable,
                    readOnly: isReadOnlyStudyKey(study.renditionId),
                    onHighlight: (color, style) {
                      final (start, end) = textRange();
                      unawaited(
                        saveHandHighlight(
                          context,
                          ref,
                          renditionId: study.renditionId,
                          content: study.content,
                          start: start,
                          end: end,
                          color: color,
                          style: style,
                        ),
                      );
                    },
                    onReadAloud: readAloud,
                    onNote: () {
                      final (start, end) = textRange();
                      unawaited(
                        saveHandHighlightWithNote(
                          context,
                          ref,
                          renditionId: study.renditionId,
                          content: study.content,
                          start: start,
                          end: end,
                        ),
                      );
                    },
                    onExtract: () {
                      final (start, end) = textRange();
                      unawaited(
                        extractRangeAsNote(
                          context,
                          ref,
                          itemId: study.itemId,
                          renditionId: study.renditionId,
                          content: study.content,
                          start: start,
                          end: end,
                        ),
                      );
                    },
                    onCreateFlashcard: () {
                      final (start, end) = textRange();
                      unawaited(
                        createFlashcardFromRange(
                          context,
                          ref,
                          itemId: study.itemId,
                          content: study.content,
                          start: start,
                          end: end,
                        ),
                      );
                    },
                    onAddToTimeline: () {
                      final (start, end) = textRange();
                      unawaited(
                        addRangeToTimeline(
                          context,
                          ref,
                          itemId: study.itemId,
                          renditionId: study.renditionId,
                          content: study.content,
                          start: start,
                          end: end,
                        ),
                      );
                    },
                    // Mientras se corta del original para Procesado (F41).
                    onToProcessed: cuttingForProcessed(ref, study.itemId)
                        ? () {
                            final (start, end) = textRange();
                            cutRangeToProcessed(
                              context,
                              ref,
                              itemId: study.itemId,
                              renditionId: study.renditionId,
                              content: study.content,
                              start: start,
                              end: end,
                            );
                          }
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ir a la página anterior/siguiente, y en qué página está parada. Además
/// del gesto de deslizar que ya da `PageView`: un botón es más fácil de
/// tocar con precisión que un swipe cuando lo que se quiere es "una página
/// más", no cualquier punto intermedio. El indicador central es tocable
/// para saltar directo a cualquier página — imprescindible en un libro de
/// cientos de páginas, donde ir pasando de a una sería impracticable.
class _PageControls extends StatelessWidget {
  const _PageControls({
    required this.label,
    required this.onLabelTap,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onLabelTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrevious,
          ),
          TextButton(
            onPressed: onLabelTap,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }
}

/// El diálogo de "ir a página": un control deslizante en vez de un campo de
/// número, porque en un libro de cientos de páginas arrastrar hasta la zona
/// aproximada es más rápido que escribir un número exacto que igual habría
/// que adivinar.
class _PagePickerDialog extends StatefulWidget {
  const _PagePickerDialog({required this.current, required this.total});

  final int current;
  final int total;

  @override
  State<_PagePickerDialog> createState() => _PagePickerDialogState();
}

class _PagePickerDialogState extends State<_PagePickerDialog> {
  late var _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.documentReaderGoToPage),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.documentReaderPageOf(_selected + 1, widget.total)),
          Slider(
            value: _selected.toDouble(),
            max: (widget.total - 1).toDouble(),
            divisions: widget.total > 1 ? widget.total - 1 : null,
            onChanged: (value) => setState(() => _selected = value.round()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text(l10n.documentReaderGoToPage),
        ),
      ],
    );
  }
}
