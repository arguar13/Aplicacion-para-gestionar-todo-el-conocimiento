import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/reading_scroll_physics.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/features/library/presentation/widgets/summarize_button.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_selection_aloud.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
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
class DocumentReaderView extends ConsumerStatefulWidget {
  const DocumentReaderView({
    required this.title,
    required this.content,
    this.markdown = true,
    this.showFontControls = false,
    this.controlsAtBottom = false,
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

  @override
  ConsumerState<DocumentReaderView> createState() => _DocumentReaderViewState();
}

class _DocumentReaderViewState extends ConsumerState<DocumentReaderView> {
  /// Cuántas páginas, contando la que se ve, se ofrecen para leer de una vez
  /// (F25): cerca de una hora de lectura. Partir el libro entero en líneas al
  /// abrirlo costaría, en uno de mil páginas, lo que no cuesta mostrarlo —ver
  /// [splitIntoReaderPages]—; así cuesta lo mismo que unas pocas páginas.
  static const _readAheadPages = 20;

  late final _pages = splitIntoReaderPages(widget.content);
  late final _controller = PageController();
  var _pageIndex = 0;

  /// El libro, para el lector flotante: el mismo contenido en el detalle y a
  /// pantalla completa es el mismo libro, y cada uno resalta y da vuelta la
  /// página de lo que el otro empezó a leer.
  late final _book = 'reader:${widget.content.hashCode}';

  /// Las líneas de cada página, armadas la primera vez que hacen falta: pasar
  /// de página no vuelve a preparar lo que ya se preparó.
  final _pageSegments = <int, List<ReadableSegment>>{};

  /// Lo que se ofrece ahora, y desde qué página.
  (int, ReadableDocument)? _readable;

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
  ReadableDocument _readableFrom(int from) {
    final cached = _readable;
    if (cached != null && cached.$1 == from) return cached.$2;
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
    );
    _readable = (from, document);
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

    return ReadableRegion(
      document: _readableFrom(_pageIndex),
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
                  children: [SummarizeButton(content: _pages[_pageIndex])],
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
/// Lo que lee el lector flotante, en amarillo (F25).
class _ReaderPage extends ConsumerWidget {
  const _ReaderPage({
    required this.content,
    required this.fontScale,
    required this.markdown,
    required this.sourceKey,
  });

  final String content;
  final double fontScale;
  final bool markdown;

  /// Con qué nombre la conoce el lector flotante: las posiciones de lo que
  /// lee son de [content].
  final String sourceKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reading = ref.watch(readAloudHighlightProvider(sourceKey));
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
              ),
              // El menú de selección de la app; "Leer en voz alta" lee las
              // líneas que toca la selección, en las posiciones de
              // [content].
              contextMenuBuilder: (context, editable) => buildSelectionMenu(
                context,
                editable,
                onReadAloud: () {
                  final selection = editable.textEditingValue.selection;
                  final start = rendered.renderToRaw(selection.start);
                  final end = rendered.renderToRaw(selection.end, isEnd: true);
                  unawaited(
                    readSelectionAloud(
                      ref,
                      text: content.substring(start, end),
                      sourceKey: sourceKey,
                      start: start,
                      end: end,
                    ),
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
