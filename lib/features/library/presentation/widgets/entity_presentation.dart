import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
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

extension NoteMaturityPresentation on NoteMaturity {
  /// Cuánto se trabajó una nota viva —`seed`/`developing`/`mature`—, no
  /// cuán buena es: una nota `seed` puede ser exactamente lo que hace
  /// falta, y una `mature` puede seguir creciendo mañana con material
  /// nuevo.
  String label(AppLocalizations l10n) => switch (this) {
    NoteMaturity.seed => l10n.noteMaturitySeed,
    NoteMaturity.developing => l10n.noteMaturityDeveloping,
    NoteMaturity.mature => l10n.noteMaturityMature,
  };

  /// Un tono neutro para `seed` —recién empieza, no hay nada que
  /// señalar—, y uno que se intensifica con cada etapa: mismo criterio
  /// que `ProcessingStatePresentation`.
  Color color(ColorScheme scheme) => switch (this) {
    NoteMaturity.seed => scheme.onSurfaceVariant,
    NoteMaturity.developing => scheme.tertiary,
    NoteMaturity.mature => scheme.primary,
  };
}

extension RelationKindPresentation on RelationKind {
  IconData get icon => switch (this) {
    RelationKind.relatedTo => Icons.link,
    RelationKind.continues => Icons.arrow_forward,
    RelationKind.contradicts => Icons.compare_arrows,
    RelationKind.cites => Icons.format_quote,
    RelationKind.summarizes => Icons.short_text,
    RelationKind.extractedFrom => Icons.content_cut,
  };

  /// Un color propio por tipo de vínculo, para el grafo: la línea que une
  /// dos nodos dice de un vistazo si es una simple relación, una
  /// continuación, una contradicción o una cita, sin tener que acercarse a
  /// leer la etiqueta. Sale de los roles del tema y no de una paleta fija,
  /// para que cambie igual de bien entre modo claro y oscuro que el resto de
  /// la app.
  Color color(ColorScheme scheme) => switch (this) {
    RelationKind.relatedTo => scheme.outline,
    RelationKind.continues => scheme.primary,
    RelationKind.contradicts => scheme.error,
    RelationKind.cites => scheme.tertiary,
    RelationKind.summarizes => scheme.secondary,
    RelationKind.extractedFrom => scheme.tertiaryContainer,
  };

  /// Un nombre corto, sin dirección: para el selector donde se elige qué
  /// clase de vínculo crear, antes de que exista un "origen" y un "destino"
  /// que mostrar.
  String shortLabel(AppLocalizations l10n) => switch (this) {
    RelationKind.relatedTo => l10n.relationKindLabelRelatedTo,
    RelationKind.continues => l10n.relationKindLabelContinues,
    RelationKind.contradicts => l10n.relationKindLabelContradicts,
    RelationKind.cites => l10n.relationKindLabelCites,
    RelationKind.summarizes => l10n.relationKindLabelSummarizes,
    RelationKind.extractedFrom => l10n.relationKindLabelExtractedFrom,
  };

  /// Cómo se lee la fila de un vínculo ya existente, con el nombre del otro
  /// elemento adentro.
  ///
  /// El sentido cambia la frase en los tipos que no son simétricos: que A
  /// *continúe* a B se lee "continúa en B" parado en A, y "es la
  /// continuación de A" parado en B. Mostrar la misma frase en los dos casos
  /// diría lo contrario de lo que pasa la mitad de las veces.
  String describe(
    AppLocalizations l10n, {
    required RelationDirection direction,
    required String otherItemTitle,
  }) {
    final outgoing = direction == RelationDirection.outgoing;

    return switch (this) {
      // Simétricos: da igual desde qué lado se mire.
      RelationKind.relatedTo => l10n.relationKindRelatedTo(otherItemTitle),
      RelationKind.contradicts => l10n.relationKindContradicts(otherItemTitle),
      RelationKind.continues =>
        outgoing
            ? l10n.relationKindContinuesOutgoing(otherItemTitle)
            : l10n.relationKindContinuesIncoming(otherItemTitle),
      RelationKind.cites =>
        outgoing
            ? l10n.relationKindCitesOutgoing(otherItemTitle)
            : l10n.relationKindCitesIncoming(otherItemTitle),
      RelationKind.summarizes =>
        outgoing
            ? l10n.relationKindSummarizesOutgoing(otherItemTitle)
            : l10n.relationKindSummarizesIncoming(otherItemTitle),
      RelationKind.extractedFrom =>
        outgoing
            ? l10n.relationKindExtractedFromOutgoing(otherItemTitle)
            : l10n.relationKindExtractedFromIncoming(otherItemTitle),
    };
  }
}
