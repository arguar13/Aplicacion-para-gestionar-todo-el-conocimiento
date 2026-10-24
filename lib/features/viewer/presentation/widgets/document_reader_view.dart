import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/reading_scroll_physics.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/features/library/presentation/widgets/summarize_button.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_selection_aloud.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_readable_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_page_segments.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_pagination.dart';
import 'package:sinapsis/features/viewer/presentation/providers/reader_font_scale_notifier.dart';
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
/// **Tamaño de letra e ir a página, no solo pasar de a una.** Ver la
/// decisión 24 en docs/arquitectura.md.
///
/// Sin `Scaffold` propio a propósito: `DocumentReaderScreen` lo envuelve
/// para mostrarlo a pantalla completa —ahí con [showFontControls] en
/// `true`, porque hay lugar de sobra—, y `EmbeddedFileViewer` lo embebe tal
/// cual dentro de un marco acotado en el detalle del elemento, sin esos
/// controles: ajustar la letra es algo que se hace leyendo de corrido, no
/// mirando de pasada un fragmento embebido.
///
/// **Se lee en voz alta (F25).** Ofrece al lector flotante la página que se
/// ve y las que siguen; mientras lee, la línea va en amarillo y, cuando
/// pasa a otra página, el lector la da vuelta solo.
///
/// **Lo estudiado se pinta en la página (F36).** Con [study], las
/// oraciones del resumen o de la síntesis y las palabras clave se ven con sus
/// colores de resaltador, y eligiendo palabras clave, tocar una la agrega o
/// la saca. Cada página es un tramo tal cual de [content] —ver
/// [readerPageRanges]—, así que lo marcado cae en su lugar sin traducir nada.
/// Abajo van los botones de estudiar, en vez de «Resumir con IA».
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
    this.showFontControls = false,
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
  final bool showFontControls;

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
  /// Cuántas páginas, contando la que se ve, se ofrecen para leer de una vez
  /// (F25): cerca de una hora de lectura. Partir el libro entero en líneas al
  /// abrirlo costaría, en uno de mil páginas, lo que no cuesta mostrarlo —ver
  /// [splitIntoReaderPages]—; así cuesta lo mismo que unas pocas páginas.
  static const _readAheadPages = 20;

  late final _ranges = readerPageRanges(widget.content);
  late final _pages = [
    for (final range in _ranges)
      widget.content.substring(range.start, range.end),
  ];
  late final _controller = PageController();
  var _pageIndex = 0;

  /// El libro, para el lector flotante: el mismo contenido en el detalle y a
  /// pantalla completa es el mismo libro, y cada uno resalta y da vuelta la
  /// página de lo que el otro empezó a leer.
  late final _book = 'reader:${widget.content.hashCode}';

  /// Las líneas de cada página, armadas la primera vez que hacen falta: pasar
  /// de página no vuelve a preparar lo que ya se preparó.
  final _pageSegments = <int, List<ReadableSegment>>{};

  /// Lo que se ofrece ahora, desde qué página y con qué estudiado: el mismo
  /// documento mientras no cambie ninguna de las dos cosas.
  (int, Map<ReadScope, List<ReadableSegment>>, ReadableDocument)? _readable;

  String _pageKey(int page) => '$_book:page:$page';

  /// La página de [sourceKey], si es una de este libro.
  int? _pageOf(String? sourceKey) {
    final prefix = '$_book:page:';
    if (sourceKey == null || !sourceKey.startsWith(prefix)) return null;
    return int.tryParse(sourceKey.substring(prefix.length));
  }

  /// La página [from] y las que le siguen: el lector empieza por la que se
  /// ve. Empezar por otra página es leer otra cosa —otro
  /// [ReadableDocument.id]—, pero las líneas se llaman igual desde cualquier
  /// página —[_pageKey]—, así que lo que se está leyendo se resalta y se
  /// sigue aunque la página de la que se partió ya no sea la que se ve.
  ///
  /// [studied] es lo que se lee con cada capa de lo estudiado, en posiciones
  /// del texto entero: se lleva a las mismas páginas, así que el resumen, la
  /// síntesis y las palabras clave también se resaltan donde suenan (F39).
  ReadableDocument _readableFrom(
    int from,
    Map<ReadScope, List<ReadableSegment>> studied,
  ) {
    final cached = _readable;
    if (cached != null && cached.$1 == from && identical(cached.$2, studied)) {
      return cached.$3;
    }
    final until = (from + _readAheadPages).clamp(0, _pages.length);
    final document = ReadableDocument(
      id: '$_book:from:$from',
      title: widget.title,
      segments: [
        for (var page = from; page < until; page++)
          ...(_pageSegments[page] ??= buildReadableSegments(
            _pages[page],
            sourceKey: _pageKey(page),
            markdown: widget.markdown,
          )),
      ],
      scopes: {
        for (final MapEntry(:key, :value) in studied.entries)
          key: readerPageSegments(
            value,
            _ranges,
            from: from,
            until: until,
            keyOf: _pageKey,
          ),
      },
    );
    _readable = (from, studied, document);
    return document;
  }

  /// El lector pasó a otra página de este documento: se la da vuelta, para
  /// que lo que se oye sea lo que se ve. A la de al lado, con la animación de
  /// siempre; más lejos —se retrocedió diez segundos hasta la anterior a la
  /// anterior—, de un salto, sin armar las del medio.
  void _followReader(String? sourceKey) {
    final page = _pageOf(sourceKey);
    if (page == null || page == _pageIndex || page >= _pages.length) return;
    if (!_controller.hasClients) return;
    if ((page - _pageIndex).abs() == 1) {
      _goTo(page);
    } else {
      _controller.jumpToPage(page);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
          _PagePickerDialog(current: _pageIndex, total: _pages.length),
    );
    if (chosen != null) _goTo(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fontScale = ref.watch(readerFontScaleNotifierProvider);
    ref.listen(
      readAloudControllerProvider.select(
        (s) => s.panel == ReadAloudPanel.hidden
            ? null
            : s.currentSegment?.sourceKey,
      ),
      (previous, next) => _followReader(next),
    );

    if (_pages.isEmpty) return const SizedBox.shrink();

    final studied = switch (widget.study) {
      final study? => ref.watch(studyReadScopesProvider(study)),
      null => const <ReadScope, List<ReadableSegment>>{},
    };

    return ReadableRegion(
      document: _readableFrom(_pageIndex, studied),
      child: _buildReader(l10n, fontScale),
    );
  }

  Widget _buildReader(AppLocalizations l10n, double fontScale) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pages.length > 1)
          LinearProgressIndicator(value: (_pageIndex + 1) / _pages.length),
        if (widget.showFontControls)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.text_decrease),
                  tooltip: l10n.documentReaderSmallerText,
                  onPressed: fontScale <= ReaderFontScaleNotifier.min
                      ? null
                      : () => ref
                            .read(readerFontScaleNotifierProvider.notifier)
                            .decrease(),
                ),
                IconButton(
                  icon: const Icon(Icons.text_increase),
                  tooltip: l10n.documentReaderLargerText,
                  onPressed: fontScale >= ReaderFontScaleNotifier.max
                      ? null
                      : () => ref
                            .read(readerFontScaleNotifierProvider.notifier)
                            .increase(),
                ),
              ],
            ),
          ),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (index) => setState(() => _pageIndex = index),
            itemBuilder: (context, index) => _ReaderPage(
              content: _pages[index],
              fontScale: fontScale,
              markdown: widget.markdown,
              sourceKey: _pageKey(index),
              study: switch (widget.study) {
                final study? => (
                  itemId: study.itemId,
                  renditionId: study.renditionId,
                  content: widget.content,
                  markdown: study.markdown,
                  start: _ranges[index].start,
                ),
                null => null,
              },
            ),
          ),
        ),
        ReadAloudClearance(
          enabled: widget.controlsAtBottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.study case final study?)
                      Expanded(
                        child: StudyBar(text: study, padding: EdgeInsets.zero),
                      )
                    else
                      SummarizeButton(content: _pages[_pageIndex]),
                  ],
                ),
              ),
              if (_pages.length > 1)
                _PageControls(
                  label: l10n.documentReaderPageOf(
                    _pageIndex + 1,
                    _pages.length,
                  ),
                  onLabelTap: () => _openPagePicker(l10n),
                  onPrevious: _pageIndex > 0
                      ? () => _goTo(_pageIndex - 1)
                      : null,
                  onNext: _pageIndex < _pages.length - 1
                      ? () => _goTo(_pageIndex + 1)
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Una página del libro: el mismo formato de tarjeta que tenía la pantalla
/// entera antes de paginarse, ahora acotado a lo que entra en una página.
/// Lo que lee el lector flotante, en amarillo (F25), y lo estudiado con
/// sus colores (F36).
class _ReaderPage extends ConsumerWidget {
  const _ReaderPage({
    required this.content,
    required this.fontScale,
    required this.markdown,
    required this.sourceKey,
    required this.study,
  });

  final String content;
  final double fontScale;
  final bool markdown;

  /// Con qué nombre la conoce el lector flotante: las posiciones de lo que
  /// lee son de [content].
  final String sourceKey;

  /// El texto entero que se estudia y dónde empieza esta página en él: lo
  /// estudiado y lo resaltado a mano guardan posiciones del texto entero.
  final ({
    String itemId,
    String renditionId,
    String content,
    bool markdown,
    int start,
  })?
  study;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reading = ref.watch(readAloudHighlightProvider(sourceKey));
    final study = this.study;
    final paints = study == null
        ? const <PaintedRange>[]
        : paintsWithin(
            watchStudyPaints(ref, context, study.renditionId),
            study.start,
            study.start + content.length,
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
            from: study.start,
            to: study.start + content.length,
          );
    final rendered = markdown
        ? RenderedMarkdown.parse(content)
        : RenderedMarkdown.plain(content);
    final baseSize = theme.textTheme.bodyLarge?.fontSize ?? 16;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const ReadingScrollPhysics(),
            child: SelectableText.rich(
              rendered.buildSpans(
                theme,
                const [],
                baseStyle: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  fontSize: baseSize * fontScale,
                ),
                activeRange: reading,
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
                          study.start +
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
                  return (study!.start + start, study.start + end);
                }

                // "Leer en voz alta" lee las líneas que toca la selección, en
                // las posiciones de [content].
                void readAloud() {
                  final (start, end) = pageRange();
                  unawaited(
                    readSelectionAloud(
                      ref,
                      text: content.substring(start, end),
                      sourceKey: sourceKey,
                      start: start,
                      end: end,
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
                );
              },
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
