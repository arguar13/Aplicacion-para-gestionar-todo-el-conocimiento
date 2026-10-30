import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_follow.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_text_provider.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_triage_providers.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_readable_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_alignment.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_study.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_hand_marks.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_highlight_toolbar.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_selection.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Lo que se le pide a la página guardada para mostrar lo que [view] deja ver
/// (F36): el resumen y la síntesis, cada uno por su lado (F39); las palabras
/// clave —también eligiéndolas—, y si tocar elige.
@visibleForTesting
String webPageStudyState(StudyView view) => archivedPageStateScript(
  summary: view.summary,
  synthesis: view.synthesis,
  keywords: view.showsKeywords,
  picking: view.picking,
);

/// La página tal como quedó archivada al guardarla: con sus imágenes y sus
/// estilos incrustados, no la versión en Markdown que ya se ve en el
/// detalle.
///
/// Existe aparte del lector de documentos porque cumple un propósito
/// distinto: el Markdown del detalle es para leer y buscar, este visor es
/// para *ver la página como era* — el diseño, las imágenes en su lugar,
/// cualquier cosa que la extracción del artículo no haya conservado. Es el
/// mismo archivo que sirve de seguro contra el enlace que un día da 404 (ver
/// `WebArticleTransformer`), ahora con una forma de mirarlo sin salir de la
/// app.
///
/// Corre sobre un `WebView` con el archivo local leído del disco y volcado
/// directo con `loadHtmlString`, así que funciona igual con o sin conexión.
/// Lo único que puede pedir por red es una foto que no quedó guardada
/// adentro del archivo: se abre con la dirección de la página, y con
/// conexión aparece en vez de quedar el hueco.
///
/// **Las fotos (F36).** Se muestra una copia con cada foto lista —ver
/// `showArchivedImages`—: la guardada sola, sin un `srcset` que el teléfono
/// prefiera y que no se guardó; la de una carga perezosa, con su dirección
/// de verdad. Así se ven también las páginas archivadas antes de que el
/// archivador eligiera bien la foto.
///
/// No se usa `loadRequest(Uri.file(...))`: desde Android 10, el proceso del
/// `WebView` corre aislado del de la app —la razón detrás de las
/// vulnerabilidades de `file://` que motivaron el cambio— y no tiene permiso
/// para leer directamente el almacenamiento privado de la app, así que
/// termina en `net::ERR_ACCESS_DENIED` aunque el archivo exista y la app
/// misma pueda leerlo sin problema. Como el archivo ya trae sus imágenes y
/// estilos incrustados (ver `HtmlPageArchiver`), volcar el HTML tal cual con
/// `loadHtmlString` evita el problema de raíz: no hay ningún `file://` que
/// resolver.
///
/// **Lo estudiado (F36, decisión E).** Con [text], la copia se arma una sola
/// vez —ver `showableArchivedPage`—: sin los programas de la página, que con
/// JavaScript apagado tampoco corrían, y con el de la app, que pinta lo
/// estudiado mientras la página está abierta (F39) y prende el resumen, la
/// síntesis y las palabras clave cambiando clases. Elegir a mano no la vuelve
/// a cargar: cualquier palabra se toca, la página avisa dónde, y eso se ubica
/// en el texto extraído. Sin [text], la página se muestra como siempre, con
/// JavaScript apagado.
///
/// **Resaltar a mano (F38).** Con [text], la copia lleva también cómo se
/// corresponde el texto de la página con el extraído —ver
/// `ArchivedPageAlignment`—. Con eso, lo que la persona selecciona en la
/// página se ubica en el texto extraído y se puede resaltar (ver
/// [DocumentSelection]); los resaltados guardados se pintan en la página, con
/// su color y su estilo, encima de las oraciones y debajo de las palabras
/// clave; y tocar uno abre su ficha. Junto a lo seleccionado aparece la
/// barrita de resaltado, la de «Texto extraído» (ver
/// `documentHighlightToolbar`), del lado donde no está la del sistema —el
/// `WebView` muestra la suya y no hay cómo ocultarla—: una encima de la otra,
/// sin taparse (F39). La de la app suma Compartir, Seleccionar todo y Buscar
/// en la Web, como sobre cualquier otro texto.
///
/// **Lo que se lee en voz alta.** También con [text], lo que suena del
/// artículo se pinta en la página en amarillo —la línea u oración, o con
/// «Palabras clave», la palabra—, por encima de lo estudiado y de lo
/// resaltado, en una capa aparte que no vuelve a envolver nada (ver
/// `archivedPageReadingScript`). Embebida en el detalle solo lo pinta: lo que
/// se ofrece para leer ahí es el detalle. A pantalla completa —con
/// [readAloud]— además ofrece el artículo entero al lector flotante —el mismo
/// documento que «Escuchar» de la tarjeta de estudiar—, empieza a leer por lo
/// que se ve y **sigue la lectura**, desplazándose cuando la línea sale de la
/// parte cómoda de la vista; si la persona mueve la página, la deja tranquila
/// y ofrece «Volver a la lectura» (ver `ReadAloudFollow`).
///
/// Sin `Scaffold` propio a propósito: `WebPageViewerScreen` lo envuelve para
/// mostrarlo a pantalla completa, y `EmbeddedFileViewer` lo embebe tal cual
/// dentro de un marco acotado en el detalle del elemento.
class WebPageViewerView extends ConsumerStatefulWidget {
  const WebPageViewerView({
    required this.path,
    this.url,
    this.text,
    this.title = '',
    this.readAloud = false,
    this.mobile = false,
    super.key,
  });

  final String path;

  /// La dirección de la página: una foto que no quedó guardada adentro del
  /// archivo se busca ahí, si hay conexión.
  final String? url;

  /// El artículo extraído de la página y su forma: de ahí sale lo estudiado y
  /// es donde se resalta.
  final StudyText? text;

  /// El nombre de la página: lo que muestra el lector flotante.
  final String title;

  /// Si ofrece el artículo para leer en voz alta y sigue la lectura: a
  /// pantalla completa sí; embebida en el detalle, que ofrece lo suyo, no.
  final bool readAloud;

  /// Si la página se ve como en un navegador del teléfono: con el ancho de la
  /// pantalla, sin el menú lateral ni las columnas de escritorio (F45, paso
  /// 4; ver `makeArchivedPageMobile`). Lo pide el original, el mismo en
  /// Procesado y en la Biblioteca (F45, paso 7b); la pantalla de cortes de
  /// una fuente también lo usa, porque muestra su original.
  final bool mobile;

  @override
  ConsumerState<WebPageViewerView> createState() => _WebPageViewerViewState();
}

class _WebPageViewerViewState extends ConsumerState<WebPageViewerView> {
  /// `null` donde `webview_flutter` no tiene implementación —en escritorio,
  /// en las pruebas—: crearlo ahí revienta, y se ve el aviso.
  final WebViewController? _webView = _createWebView();

  static WebViewController? _createWebView() {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setBackgroundColor(Colors.white);
      // Como un navegador del teléfono (F39): con el «viewport ancho» apagado
      // —lo que trae el `WebView` de Android— se ignora el `<meta
      // name="viewport">` y la página se arma siempre con el ancho de la
      // pantalla. Una página de escritorio que declara `width=1120`
      // (Wikipedia) se armaba en 412 px, se pasaba de ancho con su cuadro de
      // datos y el `WebView` se achicaba para mostrarla entera, dejando una
      // franja vacía a la derecha. Con el viewport ancho, la página se arma
      // con el ancho que dice y se ve entera, como en Chrome.
      final platform = controller.platform;
      if (platform is AndroidWebViewController) {
        unawaited(platform.setUseWideViewPort(true));
      }
      return controller;
      // Sin implementación nativa falla una aserción o un null: ninguna de
      // las dos cosas tiene un tipo que atrapar.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  WebViewController get _controller => _webView!;

  late final Future<bool> _loaded = _load();

  /// Lo último que se le pidió a la página, y si ya terminó de cargar.
  String? _state;
  bool _pageReady = false;

  /// Lo estudiado del texto, el pedido para pintarlo en la página (F39) y
  /// cuál ya se le mandó.
  List<StudyMark> _studyMarks = const [];
  String? _study;
  String? _appliedStudy;

  /// Cómo se corresponde el texto de la copia que se ve con el extraído; solo
  /// con [WebPageViewerView.text].
  ArchivedPageAlignment? _alignment;

  /// Los resaltados de la persona, de abajo hacia arriba, y el pedido para
  /// pintarlos en la página; y cuál se le mandó a esta copia de la página.
  List<Highlight> _highlights = const [];

  /// Lo cortado para Procesado mientras se corta de esta página (F41): se
  /// pinta con los resaltados, encima.
  List<ProcessedAnchor> _cuts = const [];
  String? _marks;
  String? _appliedMarks;

  /// Lo que la persona tiene seleccionado en la página, o `null`.
  ArchivedPageSelected? _selected;

  late final DocumentSelection _selection = _WebSelection(this);

  /// Lo que se lee en voz alta del artículo, en posiciones del texto
  /// extraído; el pedido para pintarlo y seguirlo, y cuál se le mandó.
  (int, int)? _reading;
  String? _readingScript;
  String? _appliedReading;
  ProviderSubscription<(int, int)?>? _readingSubscription;

  /// Si la página sigue lo que se lee o la persona la movió.
  final _follow = ReadAloudFollow();

  /// Si la persona apagó las animaciones en el sistema: la página salta en
  /// vez de deslizarse.
  var _still = false;

  /// Por dónde va la vista, en el texto extraído: lo que la página avisó la
  /// última vez que quedó quieta.
  int? _viewOffset;

  /// Lo que se ofrece para leer: el mismo documento mientras no cambie el
  /// texto partido ni lo estudiado.
  (ReadableDocument, Map<ReadScope, List<ReadableSegment>>, ReadableDocument)?
  _offered;

  @override
  void initState() {
    super.initState();
    // Dejar de seguir o volver a seguir —«Volver a la lectura»— cambia lo que
    // se le pide a la página: siguiendo, ella misma va hasta lo que suena.
    _follow.addListener(_updateReading);
    _listenToReading();
  }

  @override
  void didUpdateWidget(WebPageViewerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text?.renditionId != widget.text?.renditionId) {
      _readingSubscription?.close();
      _listenToReading();
    } else if (oldWidget.readAloud != widget.readAloud) {
      _updateReading();
    }
  }

  @override
  void dispose() {
    _readingSubscription?.close();
    _follow
      ..removeListener(_updateReading)
      ..dispose();
    super.dispose();
  }

  void _listenToReading() {
    final text = widget.text;
    _readingSubscription = text == null
        ? null
        : ref.listenManual(readAloudHighlightProvider(text.renditionId), (
            previous,
            next,
          ) {
            _reading = next;
            _updateReading();
          }, fireImmediately: true);
  }

  Future<bool> _load() async {
    if (_webView == null) return false;
    try {
      await _show(await File(widget.path).readAsString());
      return true;
      // El archivo puede haberse borrado del disco después de indexarse, o
      // `WebViewController` puede no tener implementación nativa en esta
      // plataforma —de escritorio, por ejemplo—: cualquiera de las dos cosas
      // es un motivo tan válido como el otro para caer en el aviso en vez
      // de una excepción sin atrapar.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return false;
    }
  }

  /// Muestra la copia de la página archivada [html], una sola vez: con
  /// texto, lleva el programa de la app y cómo se corresponde su texto con el
  /// extraído —lo que permite estudiar y resaltar sobre ella—; sin texto,
  /// solo sus fotos listas.
  Future<void> _show(String html) async {
    final text = widget.text;
    final study = text == null
        ? null
        : (content: text.content, colors: _colors());
    final mobile = widget.mobile;
    // Una página archivada pesa megas: se arma fuera del hilo de la pantalla.
    final shown = await Isolate.run(
      () => showArchivedPage(html, study: study, mobile: mobile),
    );
    if (!mounted) return;
    if (study != null) await _prepareStudy();
    _alignment = shown.alignment;
    _updateStudy(force: true);
    _updateMarks(force: true);
    _updateReading();
    await _controller.loadHtmlString(shown.html, baseUrl: widget.url);
  }

  Future<void> _prepareStudy() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.addJavaScriptChannel(
      archivedPageChannel,
      onMessageReceived: (message) => _onWordTapped(message.message),
    );
    await _controller.addJavaScriptChannel(
      archivedPageMarksChannel,
      onMessageReceived: (message) => _onPageEvent(message.message),
    );
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          _pageReady = true;
          unawaited(_apply());
        },
      ),
    );
  }

  /// Eligiendo a mano, lo que se tocó en la página (F39): cualquier palabra,
  /// ubicada en el texto extraído.
  void _onWordTapped(String message) {
    final text = widget.text;
    final alignment = _alignment;
    if (text == null || alignment == null || !mounted) return;
    final offset = archivedPageTappedOffset(alignment, message);
    if (offset == null) return;
    unawaited(
      pickStudyAt(
        ref,
        context,
        renditionId: text.renditionId,
        content: text.content,
        markdown: text.markdown,
        offset: offset,
      ),
    );
  }

  void _select(ArchivedPageSelected? selected) {
    if (mounted && _selected != selected) setState(() => _selected = selected);
  }

  /// Lo que la página avisa (F38): una selección nueva, que ya no hay, o un
  /// resaltado tocado.
  void _onPageEvent(String message) {
    if (!mounted) return;
    switch (parseArchivedPageEvent(message)) {
      case final ArchivedPageSelected selected:
        _select(selected);
      case ArchivedPageDeselected():
        _select(null);
      case ArchivedPageMarkTapped(:final id):
        for (final highlight in _highlights) {
          if (highlight.id == id) {
            unawaited(openHighlightCard(context, ref, highlight));
          }
        }
      case ArchivedPageMoved():
        _follow.release();
      case ArchivedPageReadingSeen():
        _follow.resume();
      case ArchivedPageViewed(:final position):
        _viewOffset = _alignment?.contentOffsetAt(position);
      case null:
        break;
    }
  }

  Future<void> _apply() async {
    final state = _state;
    if (!_pageReady) return;
    try {
      if (state != null) await _controller.runJavaScript(state);
      // Lo estudiado y los resaltados se pintan una vez y de nuevo cuando
      // cambian: volver a envolver el texto con cada cosa que se prende sería
      // un parpadeo de balde.
      final study = _study;
      if (study != null && study != _appliedStudy) {
        _appliedStudy = study;
        await _controller.runJavaScript(study);
      }
      final marks = _marks;
      if (marks != null && marks != _appliedMarks) {
        _appliedMarks = marks;
        await _controller.runJavaScript(marks);
      }
      final reading = _readingScript;
      if (reading != null && reading != _appliedReading) {
        _appliedReading = reading;
        await _controller.runJavaScript(reading);
      }
      // Una página que se está cambiando por otra no tiene dónde correrlo:
      // lo recibe la siguiente al terminar de cargar.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }

  /// Arma el pedido para pintar lo estudiado [_studyMarks] en la copia que se
  /// ve (F39), y lo manda si cambió (o con [force]).
  void _updateStudy({bool force = false}) {
    final alignment = _alignment;
    if (alignment == null) return;
    final script = archivedPageStudyScript(alignment, _studyMarks);
    if (script == _study && !force) return;
    _study = script;
    unawaited(_apply());
  }

  /// Arma el pedido para pintar los resaltados de la persona [_highlights] —y,
  /// mientras se corta para Procesado, lo cortado [_cuts]— en la copia que se
  /// ve, y lo manda si cambió (o con [force]).
  void _updateMarks({bool force = false}) {
    final alignment = _alignment;
    if (alignment == null) return;
    final marks = <ArchivedPageMark>[];
    for (final highlight in _highlights) {
      final ranges = alignment.pageRangesOf(
        highlight.startOffset,
        highlight.endOffset,
      );
      if (ranges.isEmpty) continue;
      final underline = highlight.style == HighlightStyle.underline;
      marks.add((
        id: highlight.id,
        ranges: ranges,
        color:
            (underline
                    ? HighlightPalette.lineOnPaper(highlight.color)
                    : HighlightPalette.onPaper(highlight.color))
                .toARGB32(),
        underline: underline,
      ));
    }
    for (final (index, cut) in _cuts.indexed) {
      final ranges = alignment.pageRangesOf(cut.start, cut.end);
      if (ranges.isEmpty) continue;
      // Tocarlo no abre ninguna ficha: no es un resaltado. Se quita desde la
      // lista de lo cortado.
      marks.add((
        id: 'processed-cut-$index',
        ranges: ranges,
        color: ProcessedCutPalette.light.toARGB32(),
        underline: false,
      ));
    }
    final script = archivedPageMarksScript(marks);
    if (script == _marks && !force) return;
    _marks = script;
    unawaited(_apply());
  }

  /// Arma el pedido para pintar lo que se lee en voz alta y, a pantalla
  /// completa, seguirlo; lo manda si cambió.
  void _updateReading() {
    final alignment = _alignment;
    if (alignment == null) return;
    final reading = _reading;
    final script = archivedPageReadingScript(
      reading == null
          ? const []
          : alignment.pageRangesOf(reading.$1, reading.$2),
      color: RenderedMarkdown.playingColor.toARGB32(),
      follow: widget.readAloud && _follow.following,
      report: widget.readAloud,
      smooth: !_still,
      bandTop: ReadAloudBand.top,
      bandBottom: ReadAloudBand.bottom,
      landing: ReadAloudBand.landing,
    );
    if (script == _readingScript) return;
    _readingScript = script;
    unawaited(_apply());
  }

  /// Por dónde va la vista —ver [ReadableDocument.startAt]—; sin saberlo, o
  /// cerrada la página, `null`: se lee desde el principio.
  ReadablePlace? _placeInView() {
    final text = widget.text;
    final offset = _viewOffset;
    if (!mounted || text == null || offset == null) return null;
    return (sourceKey: text.renditionId, offset: offset);
  }

  /// El artículo para el lector flotante, con lo estudiado y desde dónde se
  /// empieza; `null` mientras se parte.
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

  /// La página es la del sitio, sobre su fondo: los colores claros, en los
  /// dos modos.
  ArchivedPageColors _colors() {
    final palette = StudyPalette.of(Brightness.light);
    return (
      summary: palette.summary.toARGB32(),
      synthesis: palette.synthesis.toARGB32(),
      keyword: palette.keyword.toARGB32(),
      summaryLine: StudyPalette.summaryLine.toARGB32(),
    );
  }

  void _followStudy(StudyText text) {
    final study = ref
        .watch(documentStudyProvider(text.renditionId))
        .valueOrNull;
    final view = ref.watch(studyViewProvider(text.renditionId));
    final marks = study?.marks ?? const <StudyMark>[];
    if (!listEquals(marks, _studyMarks)) {
      _studyMarks = marks;
      _updateStudy();
    }

    final state = webPageStudyState(view);
    if (state != _state) {
      _state = state;
      unawaited(_apply());
    }

    final highlights = stackedHighlights(
      ref.watch(renditionHighlightsProvider(text.renditionId)).valueOrNull ??
          const <Highlight>[],
    );
    final cuts = watchProcessedCuts(ref, text.renditionId);
    if (!listEquals(highlights, _highlights) || !listEquals(cuts, _cuts)) {
      _highlights = highlights;
      _cuts = cuts;
      _updateMarks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (text != null) _followStudy(text);
    final still = MediaQuery.disableAnimationsOf(context);
    if (still != _still) {
      _still = still;
      _updateReading();
    }
    if (text == null || !widget.readAloud) return _buildPage();
    _follow.resumeOnNewReadings(ref);
    return ReadableRegion(
      document: _readable(text),
      child: Stack(
        children: [
          Positioned.fill(child: _buildPage()),
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
    );
  }

  Widget _buildPage() {
    return FutureBuilder<bool>(
      future: _loaded,
      builder: (context, snapshot) {
        // El `WebView` ya se ve mientras carga: mostrarlo desde el
        // principio, y no solo cuando `_loaded` se resuelve, es lo que hace
        // que la carga se sienta instantánea en vez de un salto de pantalla
        // en blanco a contenido.
        final webView = _webView;
        if (webView == null || snapshot.data == false) {
          return Center(
            child: Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        final page = WebViewWidget(controller: webView);
        final selected = _selected;
        final text = widget.text;
        // La página siempre en el mismo lugar del árbol: si cambiara de
        // lugar al aparecer la barra, el `WebView` se armaría de nuevo.
        return Stack(
          children: [
            Positioned.fill(child: page),
            if (selected != null && text != null)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    // La página cuenta en sus píxeles; la pantalla, en los
                    // suyos.
                    final scale = constraints.maxWidth / selected.viewWidth;
                    final bounds = selected.bounds;
                    final center = (bounds.left + bounds.right) / 2 * scale;
                    return documentHighlightToolbar(
                      // El de la pantalla: el de la barrita ya no existe
                      // cuando termina un diálogo.
                      this.context,
                      ref,
                      anchors: TextSelectionToolbarAnchors(
                        primaryAnchor: Offset(center, bounds.top * scale),
                        secondaryAnchor: Offset(center, bounds.bottom * scale),
                      ),
                      selection: _selection,
                      text: text,
                      systemToolbarExtent:
                          defaultTargetPlatform == TargetPlatform.android
                          ? HighlightToolbar.androidSystemToolbarExtent
                          : 0,
                      moreActions: _moreActions(context, selected.text),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  /// Lo que va detrás de «Más opciones» (F39): lo mismo que el sistema
  /// ofrece en su barra —Compartir, Seleccionar todo, Buscar en la Web—, para
  /// que la de la app alcance sola.
  List<HighlightToolbarAction> _moreActions(
    BuildContext context,
    String selected,
  ) {
    String label(ContextMenuButtonType type) =>
        AdaptiveTextSelectionToolbar.getButtonLabel(
          context,
          ContextMenuButtonItem(type: type, onPressed: null),
        );
    return [
      HighlightToolbarAction(
        label: label(ContextMenuButtonType.share),
        onPressed: () => unawaited(() async {
          await _selection.clear();
          // Lo mismo que hace un texto de Flutter al compartir lo elegido.
          await SystemChannels.platform.invokeMethod<void>(
            'Share.invoke',
            selected,
          );
        }()),
      ),
      HighlightToolbarAction(
        label: label(ContextMenuButtonType.selectAll),
        onPressed: () => unawaited(_runInPage('window.sinapsis.selectAll();')),
      ),
      HighlightToolbarAction(
        label: label(ContextMenuButtonType.searchWeb),
        onPressed: () => unawaited(() async {
          await _selection.clear();
          await searchWeb(selected);
        }()),
      ),
    ];
  }

  Future<void> _runInPage(String script) async {
    try {
      await _controller.runJavaScript('window.sinapsis && $script');
      // Una página que se está cambiando por otra no tiene dónde correrlo.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }
}

/// La selección de la página web como la ve quien arma la barra (F38): lo que
/// el navegador dice que está seleccionado, llevado al texto extraído con
/// `ArchivedPageAlignment`.
class _WebSelection implements DocumentSelection {
  _WebSelection(this._state);

  final _WebPageViewerViewState _state;

  @override
  Future<String> text() async => _state._selected?.text ?? '';

  @override
  Future<SelectionLocation> locate() async {
    final selected = _state._selected;
    if (selected == null) {
      return const SelectionLocation.failed(HighlightIssue.nothingSelected);
    }
    final alignment = _state._alignment;
    // Que lo que dice el navegador sean las letras que se contaron acá es la
    // prueba de que se habla de la misma página.
    if (alignment == null ||
        !alignment.agrees(selected.start, selected.end, selected.text)) {
      return const SelectionLocation.failed(HighlightIssue.notLocated);
    }
    final range = alignment.contentRangeOf(selected.start, selected.end);
    return range == null
        ? const SelectionLocation.failed(HighlightIssue.notLocated)
        : SelectionLocation.found([range]);
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
  Future<void> clear() async {
    _state._select(null);
    await _state._runInPage('window.sinapsis.clearSelection();');
  }
}
