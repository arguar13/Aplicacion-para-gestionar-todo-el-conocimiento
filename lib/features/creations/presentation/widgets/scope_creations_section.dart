import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_kind_icon.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_tile.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántas creaciones muestra la sección, las más nuevas: las demás se ven en
/// Repasar, con el recorte ya elegido. Un documento con cuarenta creaciones
/// no se vuelve una lista de cuarenta filas en medio de su pantalla.
const kScopeCreationsShown = 5;

/// «En Repasar» (F43, M6): Procesado y Cuadernos conectados con Repasar. Lo
/// creado sobre un recorte, sus tarjetas para hoy y «Crear en Repasar», que
/// abre Repasar con el recorte ya elegido en el selector.
///
/// Es la pieza que va en cada documento procesado y en cada cuaderno, en una
/// tarjeta redondeada como las de Repasar:
///
/// - **arriba**, «En Repasar», cuántas creaciones hay y «Crear en Repasar»;
/// - **sus tarjetas para hoy**, si hay, con «Empezar»: la sesión de repaso de
///   ese recorte (`StudyScope.processed`), la misma que «Para hoy» de Repasar
///   con el recorte elegido;
/// - **lo creado**, las [maxShown] más nuevas, con las mismas filas de «Lo
///   creado» —el ícono y el color de su tipo, su estado, su menú y deslizar—;
///   tocar una abre su visor, y «atrás» vuelve acá. Si hay más, «Ver las N en
///   Repasar».
///
/// En un documento entra también lo que lo usó como fuente aunque se haya
/// creado sobre un cuaderno o un tema; en un cuaderno, lo creado con el
/// cuaderno como recorte. La regla es una sola, la de Repasar
/// (`StudyCreationRepository.watchByScope`): las dos listas no pueden
/// discrepar. Todo se actualiza solo: una creación que se genera aparece acá
/// enseguida y cambia su avance sin que nadie avise.
///
/// Sin nada creado, un vacío que invita a crear, con los íconos de lo que se
/// puede hacer y «Crear en Repasar». Con [hideWhenEmpty], sin nada creado no
/// dibuja nada: para quien no tiene sobre qué crear todavía —un cuaderno
/// vacío—, pero no debe esconder lo que ya se creó.
///
/// Sin [title], «En Repasar». Con [showHeader] apagado, sin la fila del
/// título: para quien ya tiene su propio encabezado.
class ScopeCreationsSection extends ConsumerWidget {
  const ScopeCreationsSection({
    required this.scope,
    this.title,
    this.showHeader = true,
    this.maxShown = kScopeCreationsShown,
    this.hideWhenEmpty = false,
    super.key,
  });

  final CreationScope scope;
  final String? title;
  final bool showHeader;

  /// Cuántas se muestran como mucho; `null`, todas.
  final int? maxShown;
  final bool hideWhenEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final creations = ref.watch(studyCreationsProvider(scope));
    final list = creations.valueOrNull;
    final dueToday =
        ref.watch(studyCountsProvider(scope.studyScope)).valueOrNull?.total ??
        0;

    if (hideWhenEmpty && (list == null || list.isEmpty)) {
      return const SizedBox.shrink();
    }

    final limit = maxShown;
    final shown = list == null || limit == null || list.length <= limit
        ? list
        : list.sublist(0, limit);
    final hidden = (list?.length ?? 0) - (shown?.length ?? 0);
    final key = scope.storageKey;

    return Material(
      key: ValueKey('scope-creations-$key'),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHeader)
            _Header(
              scope: scope,
              title: title ?? l10n.f43StudioInRepasar,
              count: list?.length ?? 0,
              // Vacía, el botón grande va en el vacío: uno solo a la vista.
              showCreate: list != null && list.isNotEmpty,
            ),
          if (dueToday > 0) _Today(scope: scope, count: dueToday),
          if (shown == null && creations.hasError)
            _Line(text: l10n.f43StudioCreatedFailedLoad)
          else if (shown == null)
            // Lo que tarda en llegar la lista es un instante: un lugar quieto,
            // sin una barra que se mueva y que pase sola.
            const SizedBox(height: 48)
          else if (shown.isEmpty)
            _Empty(scope: scope)
          else ...[
            // Las filas de «Lo creado», planas y con su propio margen.
            for (final creation in shown) CreationTile(creation: creation),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: ValueKey('scope-creations-all-$key'),
                    onPressed: () => openRepasarWith(context, scope),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(l10n.f43LinkSeeAll(list!.length)),
                  ),
                ),
              )
            else
              const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// «En Repasar», cuántas creaciones hay y «Crear en Repasar». Con la letra
/// grande o en una pantalla angosta, el botón baja debajo del título.
class _Header extends StatelessWidget {
  const _Header({
    required this.scope,
    required this.title,
    required this.count,
    required this.showCreate,
  });

  final CreationScope scope;
  final String title;
  final int count;
  final bool showCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: theme.textTheme.titleMedium),
                    ),
                    if (count > 0)
                      Text(
                        l10n.f43LinkCreatedCount(count),
                        key: ValueKey(
                          'scope-creations-count-${scope.storageKey}',
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (showCreate)
            TextButton.icon(
              key: ValueKey('scope-creations-create-${scope.storageKey}'),
              onPressed: () => openRepasarWith(context, scope),
              icon: const Icon(Icons.add),
              label: Text(l10n.f43StudioCreateInRepasar),
            ),
        ],
      ),
    );
  }
}

/// Sus tarjetas para hoy, con «Empezar»: la sesión de repaso del recorte.
class _Today extends StatelessWidget {
  const _Today({required this.scope, required this.count});

  final CreationScope scope;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = scope.storageKey;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.style_outlined,
                      size: 20,
                      color: scheme.tertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      l10n.f43LinkTodayCards(count),
                      key: ValueKey('scope-today-$key'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              FilledButton.tonalIcon(
                key: ValueKey('scope-today-start-$key'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => openScopeReview(context, scope),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.reviewEntryStart),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo que se ve sin nada creado: los íconos de lo que se puede hacer, con su
/// color, qué es esto y «Crear en Repasar».
class _Empty extends ConsumerWidget {
  const _Empty({required this.scope});

  final CreationScope scope;

  /// Los que se muestran de muestra: los que nombra el texto.
  static const _sample = [
    StudyCreationKind.presentation,
    StudyCreationKind.summary,
    StudyCreationKind.infographic,
    StudyCreationKind.quiz,
    StudyCreationKind.mindMap,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final registry = ref.watch(creationKindRegistryProvider);
    final (title, message) = switch (scope) {
      ProcessedDocumentScope() => (
        l10n.f43LinkEmptyDocumentTitle,
        l10n.f43LinkEmptyDocument,
      ),
      NotebookScope() => (
        l10n.f43LinkEmptyNotebookTitle,
        l10n.f43LinkEmptyNotebook,
      ),
      AllProcessed() ||
      TopicScope() ||
      SpaceScope() => (l10n.f43LinkEmptyTopicTitle, l10n.f43LinkEmptyTopic),
    };

    return Padding(
      key: ValueKey('scope-creations-empty-${scope.storageKey}'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in _sample)
                  CreationKindIcon(spec: registry.of(kind), size: 36),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            key: ValueKey('scope-creations-create-${scope.storageKey}'),
            onPressed: () => openRepasarWith(context, scope),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(l10n.f43StudioCreateInRepasar),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
