import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_illustration_providers.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/export/deck_pdf_exporter.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/providers/presentation_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El PDF de una presentación (F43, punto 5: «exportar a PDF»): lo que dan
/// «Descargar» y «Compartir» en «Lo creado» y en el visor
/// (`CreationKindSpec.exporter`).
///
/// Con el diseño que se ve —el del visor abierto, o el guardado—, sus
/// ilustraciones y, en «Del presentador», una página de notas después de
/// cada diapositiva: lo que hace falta para presentarla impresa.
Future<CreationExportFile?> exportPresentationPdf(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final content = PresentationContent.decode(creation.content);
  final deck = content.deck;
  if (deck.slides.isEmpty) return null;
  final viewer = presentationViewerProvider(creation.id);
  final design = ref.exists(viewer)
      ? ref.read(viewer).design
      : PresentationViewerController.designOf(creation);
  final files = ref.read(creationIllustrationStoreProvider);

  final images = <String, ImageProvider>{};
  for (final path in content.files) {
    final bytes = await files.read(path);
    if (bytes != null) images[path] = MemoryImage(bytes);
  }
  final bytes = await const DeckPdfExporter().export(
    deck: deck,
    design: design,
    includeSpeakerNotes: deck.format == DeckFormat.presenter,
    illustrations: (reference) => images[reference],
    labels: DeckPdfLabels(
      notesTitle: l10n.f43DeckPdfNotesTitle,
      noNotes: l10n.f43DeckPdfNoNotes,
      slideOf: l10n.f43DeckPdfSlideOf,
    ),
  );
  return CreationExportFile(
    fileName: sanitizeFileName('${studyCreationTitle(l10n, creation)}.pdf'),
    bytes: bytes,
    mimeType: 'application/pdf',
  );
}
