import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se muestra lo decidido en la Bandeja (F28), en un solo lugar: los
/// filtros de la Biblioteca y el chip del detalle lo dibujan igual, con los
/// mismos íconos que los botones de la Bandeja que llevan a cada estado.
extension InboxStatusPresentation on InboxStatus {
  IconData get icon => switch (this) {
    InboxStatus.pending => Icons.inbox_outlined,
    InboxStatus.triaged => Icons.check,
    InboxStatus.discarded => Icons.archive_outlined,
  };

  /// El nombre del estado en los filtros: «Por revisar», «Triado»,
  /// «Descartado».
  String filterLabel(AppLocalizations l10n) => switch (this) {
    InboxStatus.pending => l10n.libraryFilterInboxPending,
    InboxStatus.triaged => l10n.libraryFilterInboxTriaged,
    InboxStatus.discarded => l10n.libraryFilterInboxDiscarded,
  };

  /// El color con que se tiñe: el mismo de la pista de cada gesto en el mazo
  /// —descartar en rojo, triar en el terciario—, y el principal para lo que
  /// todavía espera.
  Color color(ColorScheme scheme) => switch (this) {
    InboxStatus.pending => scheme.primary,
    InboxStatus.triaged => scheme.tertiary,
    InboxStatus.discarded => scheme.error,
  };
}
