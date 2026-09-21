import 'package:sinapsis/features/atlas/domain/entities/atlas_gap.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los textos del Atlas que la pantalla y la exportación dicen igual.

/// El rango de años de «Fecha del hecho» que cubre una rama —«44 a.C. – 476»,
/// o un solo año si cubre uno—; `null` si ningún elemento de la rama tiene
/// fecha.
String? atlasAxisText(AppLocalizations l10n, AtlasNode node) {
  final first = node.firstYear;
  final last = node.lastYear;
  if (first == null) return null;
  final from = _yearText(l10n, first);
  if (last == null || last == first) return from;
  return '$from – ${_yearText(l10n, last)}';
}

/// El año astronómico como se lee: 0 es «1 a.C.», -43 es «44 a.C.». Igual que
/// el eje de la línea de tiempo.
String _yearText(AppLocalizations l10n, int astronomicalYear) {
  return astronomicalYear <= 0
      ? l10n.timelineYearBce(1 - astronomicalYear)
      : '$astronomicalYear';
}

/// Qué le pasa a la rama [node], dicho para el vacío [gap]; [now] cuenta hace
/// cuánto que nadie la toca.
String atlasGapMessage(
  AppLocalizations l10n,
  AtlasGap gap,
  AtlasNode node,
  DateTime now,
) => switch (gap.kind) {
  AtlasGapKind.manySourcesNoLivingNote => l10n.atlasGapManySources(
    node.sourceCount,
  ),
  AtlasGapKind.singleItem => l10n.atlasGapSingleItem,
  AtlasGapKind.stale => l10n.atlasGapStale(
    // Meses de 30 días: es un aviso, no un plazo.
    now.difference(node.lastTouched ?? now).inDays ~/ 30,
  ),
};
