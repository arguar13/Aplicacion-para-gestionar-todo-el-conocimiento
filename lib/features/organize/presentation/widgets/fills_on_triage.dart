import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si ya hay algo procesado (F41, paso 6): el Atlas, el Mapa y la Línea de
/// tiempo se arman solo con eso, y sin nada muestran [FillsOnTriage]. `null`
/// mientras se cuenta.
final hasProcessedProvider = Provider.autoDispose<bool?>(
  (ref) => ref
      .watch(processedCountProvider(const ProcessedQuery()))
      .whenData((count) => count > 0)
      .valueOrNull,
);

/// Lo que muestran el Atlas, el Mapa y la Línea de tiempo antes de que haya
/// nada procesado (F41, paso 6): que se llenan al triar —con lo que la persona
/// elige de cada fuente, no con la Biblioteca— y el camino a la Bandeja.
///
/// Empiezan de cero, como eligió el dueño: lo que las fuentes ya tenían sigue
/// en cada una, y no se muestra acá.
class FillsOnTriage extends StatelessWidget {
  const FillsOnTriage({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return EmptyStateView(
      key: const ValueKey('fills-on-triage'),
      icon: icon,
      title: title,
      message: message,
      actionLabel: l10n.organizedGoToInbox,
      onAction: () => context.go(RoutePaths.inbox),
    );
  }
}
