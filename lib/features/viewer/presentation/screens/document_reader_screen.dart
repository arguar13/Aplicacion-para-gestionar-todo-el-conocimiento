import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/library/presentation/widgets/summarize_button.dart';
import 'package:sinapsis/features/narration/presentation/widgets/narration_player.dart';
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
/// sus propios lectores en vez de sumar un renderizador de formato
/// cerrado: nadie mantiene un motor de maquetación de DOCX en Flutter, y
/// uno que se abandone dejaría la lectura rota de un día para el otro.
///
/// **Paginado, no un solo scroll infinito.** [splitIntoReaderPages] corta
/// [content] antes de que esta pantalla le ponga formato a una sola letra;
/// `PageView.builder` arma —y descarta— una página Markdown por vez, así
/// que abrir un libro de mil páginas cuesta lo mismo que abrir uno de diez.
/// Ver el comentario de esa función para por qué hace falta.
///
/// **Tamaño de letra e ir a página, no solo pasar de a una.** Ver la
/// decisión 24 en docs/arquitectura.md.
class DocumentReaderScreen extends ConsumerStatefulWidget {
  const DocumentReaderScreen({
    required this.title,
    required this.content,
    super.key,
  });

  final String title;
  final String content;

  @override
  ConsumerState<DocumentReaderScreen> createState() =>
      _DocumentReaderScreenState();
}

class _DocumentReaderScreenState extends ConsumerState<DocumentReaderScreen> {
  late final _pages = splitIntoReaderPages(widget.content);
  late final _controller = PageController();
  var _pageIndex = 0;

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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
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
        bottom: _pages.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: (_pageIndex + 1) / _pages.length,
                ),
              )
            : null,
      ),
      body: _pages.isEmpty
          ? const SizedBox.shrink()
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (index) =>
                        setState(() => _pageIndex = index),
                    itemBuilder: (context, index) => _ReaderPage(
                      content: _pages[index],
                      fontScale: fontScale,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [SummarizeButton(content: _pages[_pageIndex])],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  // La clave por página cierra el lector de voz si estaba
                  // abierto al cambiar de página: seguir leyendo la página
                  // anterior mientras se ve otra distinta confundiría más
                  // de lo que ayuda.
                  child: NarrationPlayer(
                    key: ValueKey(_pageIndex),
                    text: _pages[_pageIndex],
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
    );
  }
}

/// Una página del libro: el mismo formato de tarjeta que tenía la pantalla
/// entera antes de paginarse, ahora acotado a lo que entra en una página.
class _ReaderPage extends StatelessWidget {
  const _ReaderPage({required this.content, required this.fontScale});

  final String content;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rendered = RenderedMarkdown.parse(content);
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
            child: SelectableText.rich(
              rendered.buildSpans(
                theme,
                const [],
                baseStyle: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  fontSize: baseSize * fontScale,
                ),
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
    return SafeArea(
      top: false,
      child: Padding(
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
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: onNext,
            ),
          ],
        ),
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
