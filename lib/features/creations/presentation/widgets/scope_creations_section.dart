import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_tile.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «En Repasar» (F43, M6): lo creado sobre un recorte, con «Crear en
/// Repasar», que abre Repasar con el recorte ya elegido.
///
/// Es la pieza que va en cada documento procesado y en cada cuaderno. En un
/// documento muestra también lo que lo usó como fuente aunque se haya creado
/// sobre un cuaderno o un tema (`StudyCreationRepository.watchByScope`).
///
/// Sin [title], «En Repasar». Con [showHeader] apagado, solo la lista: para
/// quien ya tiene su propio encabezado.
class ScopeCreationsSection extends ConsumerWidget {
  const ScopeCreationsSection({
    required this.scope,
    this.title,
    this.showHeader = true,
    super.key,
  });

  final CreationScope scope;
  final String? title;
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final creations = ref.watch(studyCreationsProvider(scope));
    final list = creations.valueOrNull;

    return Column(
      key: ValueKey('scope-creations-${scope.storageKey}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                title ?? l10n.f43StudioInRepasar,
                style: theme.textTheme.titleMedium,
              ),
              TextButton.icon(
                key: ValueKey('scope-creations-create-${scope.storageKey}'),
                onPressed: () => openRepasarWith(context, scope),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(l10n.f43StudioCreateInRepasar),
              ),
            ],
          ),
        if (list == null && creations.hasError)
          _Line(text: l10n.f43StudioCreatedFailedLoad, error: true)
        else if (list == null)
          // Lo que tarda en llegar la lista es un instante: un lugar quieto,
          // sin una barra que se mueva y que pase sola.
          const SizedBox(height: 48)
        else if (list.isEmpty)
          _Line(text: l10n.f43StudioInRepasarEmpty)
        else
          // Filas planas, con su propio margen, como en Repasar.
          for (final creation in list) CreationTile(creation: creation),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: error
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
