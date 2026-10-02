import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los formatos que la interfaz ofrece para exportar un elemento suelto —el
/// menú de tres puntos de cada fila (que también usa el Explorador) y el
/// botón Exportar del detalle—: los de un documento para leer o seguir
/// editando.
///
/// Markdown, texto plano y BibTeX salieron de los dos menús a pedido del
/// usuario —le alargaban el menú sin usarlos—. Sus exportadores siguen en el
/// registro: solo dejaron de ofrecerse. Una sola lista para los dos lugares a
/// propósito: con dos copias, tarde o temprano dejan de coincidir.
///
/// No aplica a la bibliografía ni a las referencias (F15), donde `.bib` y
/// `.ris` son el formato propio de lo que se exporta.
const offeredItemExportFormats = [ExportFormat.pdf, ExportFormat.docx];

extension ExportFormatPresentation on ExportFormat {
  String label(AppLocalizations l10n) => switch (this) {
    ExportFormat.markdown => l10n.exportFormatMarkdown,
    ExportFormat.plainText => l10n.exportFormatPlainText,
    ExportFormat.pdf => l10n.exportFormatPdf,
    ExportFormat.bibtex => l10n.exportFormatBibtex,
    ExportFormat.docx => l10n.exportFormatDocx,
  };
}
