import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

extension ExportFormatPresentation on ExportFormat {
  String label(AppLocalizations l10n) => switch (this) {
    ExportFormat.markdown => l10n.exportFormatMarkdown,
    ExportFormat.plainText => l10n.exportFormatPlainText,
    ExportFormat.pdf => l10n.exportFormatPdf,
    ExportFormat.bibtex => l10n.exportFormatBibtex,
    ExportFormat.docx => l10n.exportFormatDocx,
  };
}
