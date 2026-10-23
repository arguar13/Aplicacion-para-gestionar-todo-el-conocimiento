import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_alignment.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_study.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_hand_marks.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_highlight_toolbar.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_selection.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
/// **Lo estudiado (F36, decisión E).** Con [text] y oraciones ya marcadas, la
/// copia las lleva listas —ver `showableArchivedPage`—: sin los
/// programas de la página, que con JavaScript apagado tampoco corrían, y con
/// el de la app, que prende el resumen o la síntesis y las palabras clave sin
/// volver a cargarla, y avisa la palabra que se toca para elegirla. Sin
/// [text], la página se muestra como siempre, con JavaScript apagado.
///
/// **Resaltar a mano (F38).** Con [text], la copia lleva también cómo se
/// corresponde el texto de la página con el extraído —ver
/// `ArchivedPageAlignment`—. Con eso, lo que la persona selecciona en la
/// página se ubica en el texto extraído y se puede resaltar (ver
/// [DocumentSelection]); los resaltados guardados se pintan en la página, con
/// su color y su estilo, encima de las oraciones y debajo de las palabras
/// clave; y tocar uno abre su ficha. Junto a lo seleccionado aparece la
/// barrita de resaltado, la de «Texto extraído» (ver
/// `documentHighlightToolbar`).
///
/// Sin `Scaffold` propio a propósito: `WebPageViewerScreen` lo envuelve para
/// mostrarlo a pantalla completa, y `EmbeddedFileViewer` lo embebe tal cual
/// dentro de un marco acotado en el detalle del elemento.
class WebPageViewerView extends ConsumerStatefulWidget {
  const WebPageViewerView({required this.path, this.url, this.text, super.key});

  final String path;

  /// La dirección de la página: una foto que no quedó guardada adentro del
  /// archivo se busca ahí, si hay conexión.
  final String? url;

  /// El artículo extraído de la página y su forma: de ahí sale lo estudiado y
  /// es donde se resalta.
  final StudyText? text;

  @override
  ConsumerState<WebPageViewerView> createState() => _WebPageViewerViewState();
}

class _WebPageViewerViewState extends ConsumerState<WebPageViewerView> {
  /// `null` donde `webview_flutter` no tiene implementación —en escritorio,
  /// en las pruebas—: crearlo ahí revienta, y se ve el aviso.
  final WebViewController? _webView = _createWebView();

  static WebViewController? _createWebView() {
    try {
      return WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setBackgroundColor(Colors.white);
      // Sin implementación nativa falla una aserción o un null: ninguna de
      // las dos cosas tiene un tipo que atrapar.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  WebViewController get _controller => _webView!;

  late final Future<bool> _loaded = _load();

  /// La página archivada, tal cual.
  String? _html;

  /// Las oraciones que lleva la copia que se ve; `null`, la página tal cual.
  List<ArchivedPageSentence>? _shown;

  /// Las que se pidieron mostrar, por si llegan mientras se arma otra copia.
  List<ArchivedPageSentence> _wanted = const [];
  bool _building = false;
  bool _studyReady = false;

  /// Lo último que se le pidió a la página, y si ya terminó de cargar.
  String? _state;
  bool _pageReady = false;

  /// Cómo se corresponde el texto de la copia que se ve con el extraído; solo
  /// con [WebPageViewerView.text].
  ArchivedPageAlignment? _alignment;

  /// Los resaltados de la persona, de abajo hacia arriba, y el pedido para
  /// pintarlos en la página; y cuál se le mandó a esta copia de la página.
  List<Highlight> _highlights = const [];
  String? _marks;
  String? _appliedMarks;

  /// Lo que la persona tiene seleccionado en la página, o `null`.
  ArchivedPageSelected? _selected;

  late final DocumentSelection _selection = _WebSelection(this);

  Future<bool> _load() async {
    if (_webView == null) return false;
    try {
      _html = await File(widget.path).readAsString();
      await _show();
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

  /// Muestra la copia de la página con las oraciones que se quieren ver, si
  /// cambiaron: la primera vez, siempre, por las fotos.
  Future<void> _show() async {
    final html = _html;
    if (html == null || _building) return;
    _building = true;
    try {
      while (_shown == null || !listEquals(_wanted, _shown)) {
        final sentences = _wanted;
        final text = widget.text;
        // Con texto, la copia siempre lleva el programa de la app y cómo se
        // corresponde su texto con el extraído, aunque no haya oraciones
        // todavía: es lo que permite resaltar a mano (F38).
        final study = text == null
            ? null
            : (content: text.content, sentences: sentences, colors: _colors());
        // Sin texto, una copia ya armada se queda: sin nada prendido se ve
        // igual que la original.
        if (study == null && _shown != null) {
          _shown = sentences;
          continue;
        }
        // Una página archivada pesa megas: se arma fuera del hilo de la
        // pantalla.
        final shown = await Isolate.run(
          () => showArchivedPage(html, study: study),
        );
        if (!mounted) return;
        if (study != null) await _prepareStudy();
        _pageReady = false;
        _appliedMarks = null;
        _alignment = shown.alignment;
        _updateMarks(force: true);
        await _controller.loadHtmlString(shown.html, baseUrl: widget.url);
        _shown = sentences;
      }
    } finally {
      _building = false;
    }
  }

  Future<void> _prepareStudy() async {
    if (_studyReady) return;
    _studyReady = true;
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

  void _onWordTapped(String message) {
    final text = widget.text;
    final offset = int.tryParse(message);
    if (text == null || offset == null || !mounted) return;
    unawaited(
      toggleStudyKeywordAt(
        ref,
        context,
        renditionId: text.renditionId,
        content: text.content,
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
      case null:
        break;
    }
  }

  Future<void> _apply() async {
    final state = _state;
    if (!_pageReady) return;
    try {
      if (state != null) await _controller.runJavaScript(state);
      // Los resaltados se pintan una vez por copia de la página, y de nuevo
      // cuando cambian: volver a envolver el texto en cada cambio de lo
      // estudiado sería un parpadeo de balde.
      final marks = _marks;
      if (marks != null && marks != _appliedMarks) {
        _appliedMarks = marks;
        await _controller.runJavaScript(marks);
      }
      // Una página que se está cambiando por otra no tiene dónde correrlo:
      // lo recibe la siguiente al terminar de cargar.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }

  /// Arma el pedido para pintar los resaltados de la persona [_highlights] en
  /// la copia que se ve, y lo manda si cambió (o con [force]).
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
    final script = archivedPageMarksScript(marks);
    if (script == _marks && !force) return;
    _marks = script;
    unawaited(_apply());
  }

  /// La página es la del sitio, sobre su fondo: los colores claros, en los
  /// dos modos.
  ArchivedPageColors _colors() {
    final palette = StudyPalette.of(Brightness.light);
    return (
      summary: palette.summary.toARGB32(),
      synthesis: palette.synthesis.toARGB32(),
      keyword: palette.keyword.toARGB32(),
    );
  }

  void _follow(StudyText text) {
    final study = ref
        .watch(documentStudyProvider(text.renditionId))
        .valueOrNull;
    final view = ref.watch(studyViewProvider(text.renditionId));
    final marks = study?.marks ?? const <StudyMark>[];
    final sentences = <ArchivedPageSentence>[
      for (final mark in marks)
        if (mark.kind != StudyMarkKind.keyword)
          (start: mark.start, end: mark.end, kind: mark.kind),
    ];
    if (!listEquals(sentences, _wanted)) {
      _wanted = sentences;
      if (_html != null) unawaited(_show());
    }

    final state = archivedPageStateScript(
      layer: view.layer?.kind,
      keywords: view.showsKeywords,
      picking: view.picking,
      keywordOffsets: [
        for (final mark in marks)
          if (mark.kind == StudyMarkKind.keyword) mark.start,
      ],
    );
    if (state != _state) {
      _state = state;
      unawaited(_apply());
    }

    final highlights = stackedHighlights(
      ref.watch(renditionHighlightsProvider(text.renditionId)).valueOrNull ??
          const <Highlight>[],
    );
    if (!listEquals(highlights, _highlights)) {
      _highlights = highlights;
      _updateMarks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (text != null) _follow(text);
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
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
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
    try {
      await _state._controller.runJavaScript(
        'window.sinapsis && window.sinapsis.clearSelection();',
      );
      // Una página que se está cambiando por otra no tiene dónde correrlo.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }
}
