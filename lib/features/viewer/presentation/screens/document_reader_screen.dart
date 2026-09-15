import 'package:flutter/material.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';

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
class DocumentReaderScreen extends StatelessWidget {
  const DocumentReaderScreen({
    required this.title,
    required this.content,
    super.key,
  });

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rendered = RenderedMarkdown.parse(content);

    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: Center(
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
      ),
    );
  }
}
