import 'package:flutter/material.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
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
/// sus propios lectores en vez de sumar un renderizador de formato
/// cerrado: nadie mantiene un motor de maquetación de DOCX en Flutter, y
/// uno que se abandone dejaría la lectura rota de un día para el otro.
///
/// **Paginado, no un solo scroll infinito.** [splitIntoReaderPages] corta
/// [content] antes de que esta pantalla le ponga formato a una sola letra;
/// `PageView.builder` arma —y descarta— una página Markdown por vez, así
/// que abrir un libro de mil páginas cuesta lo mismo que abrir uno de diez.
/// Ver el comentario de esa función para por qué hace falta.
class DocumentReaderScreen extends StatefulWidget {
  const DocumentReaderScreen({
    required this.title,
    required this.content,
    super.key,
  });

  final String title;
  final String content;

  @override
  State<DocumentReaderScreen> createState() => _DocumentReaderScreenState();
}

class _DocumentReaderScreenState extends State<DocumentReaderScreen> {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
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
                    itemBuilder: (context, index) =>
                        _ReaderPage(content: _pages[index]),
                  ),
                ),
                if (_pages.length > 1)
                  _PageControls(
                    label: l10n.documentReaderPageOf(
                      _pageIndex + 1,
                      _pages.length,
                    ),
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
  const _ReaderPage({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rendered = RenderedMarkdown.parse(content);

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
                baseStyle: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
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
/// más", no cualquier punto intermedio.
class _PageControls extends StatelessWidget {
  const _PageControls({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
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
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
