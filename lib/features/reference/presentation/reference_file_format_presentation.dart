import 'package:sinapsis/features/reference/domain/entities/reference_file_format.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

extension ReferenceFileFormatPresentation on ReferenceFileFormat {
  String label(AppLocalizations l10n) => switch (this) {
    ReferenceFileFormat.bibtex => l10n.exportFormatBibtex,
    ReferenceFileFormat.ris => l10n.referenceFileFormatRis,
  };
}
