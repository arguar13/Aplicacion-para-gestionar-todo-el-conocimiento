import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se muestran los tipos de fuente y los estados de procesamiento.
///
/// Vive en un solo lugar porque estos pares ícono-etiqueta aparecen en la
/// lista, en el detalle, en los filtros y en cualquier pantalla futura. Con la
/// correspondencia repetida en cada una, agregar un tipo de fuente nuevo
/// obligaría a acordarse de todas — y la que se olvide mostrará un hueco.
extension SourceKindPresentation on SourceKind {
  IconData get icon => switch (this) {
    SourceKind.youtube => Icons.smart_display_outlined,
    SourceKind.webPage => Icons.article_outlined,
    SourceKind.socialPost => Icons.forum_outlined,
    SourceKind.document => Icons.description_outlined,
    SourceKind.image => Icons.image_outlined,
    SourceKind.audio => Icons.graphic_eq,
    SourceKind.video => Icons.movie_outlined,
    SourceKind.manualNote => Icons.edit_note_outlined,
  };

  String label(AppLocalizations l10n) => switch (this) {
    SourceKind.youtube => l10n.sourceKindYoutube,
    SourceKind.webPage => l10n.sourceKindWebPage,
    SourceKind.socialPost => l10n.sourceKindSocialPost,
    SourceKind.document => l10n.sourceKindDocument,
    SourceKind.image => l10n.sourceKindImage,
    SourceKind.audio => l10n.sourceKindAudio,
    SourceKind.video => l10n.sourceKindVideo,
    SourceKind.manualNote => l10n.sourceKindNote,
  };
}

extension ProcessingStatePresentation on ProcessingState {
  /// Solo los estados que le importan al usuario tienen texto.
  ///
  /// `ready` devuelve `null` a propósito: marcar con una insignia que algo
  /// "está listo" es ruido en una lista donde casi todo lo está. Lo que
  /// merece señalarse es lo que falta o lo que falló.
  String? label(AppLocalizations l10n) => switch (this) {
    ProcessingState.pending => l10n.processingPending,
    ProcessingState.processing => l10n.processingInProgress,
    ProcessingState.failed => l10n.processingFailed,
    ProcessingState.ready => null,
  };

  /// El color de la insignia. `failed` usa el de error; los otros dos, un
  /// tono neutro: estar en la cola no es un problema.
  Color? color(ColorScheme scheme) => switch (this) {
    ProcessingState.failed => scheme.error,
    ProcessingState.pending ||
    ProcessingState.processing => scheme.onSurfaceVariant,
    ProcessingState.ready => null,
  };
}
