import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/processed_depth.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se muestra cuánto se trabajó un documento procesado (F41, paso 6): el
/// mismo nombre y el mismo color en el Atlas y en el tablero del Mapa.
extension ProcessedDepthPresentation on ProcessedDepth {
  String label(AppLocalizations l10n) => switch (this) {
    ProcessedDepth.textOnly => l10n.processedDepthTextOnly,
    ProcessedDepth.summarized => l10n.processedDepthSummarized,
    ProcessedDepth.cut => l10n.processedDepthCut,
    ProcessedDepth.annotated => l10n.processedDepthAnnotated,
  };

  /// De lo de la fuente a lo propio: el texto copiado lleva el color de las
  /// fuentes, lo que escribió la persona el de las notas, y lo del medio, los
  /// del esquema que no son de ninguna de las dos.
  Color color(ColorScheme colors) => switch (this) {
    ProcessedDepth.textOnly => EntityRole.source.accent(colors),
    ProcessedDepth.summarized => colors.tertiary,
    ProcessedDepth.cut => colors.secondary,
    ProcessedDepth.annotated => EntityRole.note.accent(colors),
  };
}
