import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que un recorte ya tenía antes de crear nada (F43, M10): las filas que
/// «Lo creado» pone arriba de las creaciones, para que un documento con
/// tarjetas o con el resumen marcado nunca diga «Todavía no creaste nada».
enum ScopeHolding {
  /// Sus tarjetas, aunque no salgan de una creación: las de «Crear tarjetas
  /// con IA», las hechas a mano y las de su fuente (`StudyScope`).
  cards(StudyCreationKind.flashcards),

  /// El resumen marcado en sus documentos (F36, M5).
  summary(StudyCreationKind.summary),

  /// La síntesis marcada en sus documentos.
  synthesis(StudyCreationKind.synthesis);

  const ScopeHolding(this.kind);

  /// El tipo de creación del que toma el ícono y el color —y, en el resumen y
  /// la síntesis, la vista viva que abre—.
  final StudyCreationKind kind;
}

/// Las filas de lo que [summary] ya tiene, en este orden: las tarjetas, el
/// resumen y la síntesis.
///
/// El resumen o la síntesis que ya son una creación de este mismo recorte no
/// se repiten: su fila de «Lo creado» abre lo mismo, la vista viva de las
/// marcas del documento (decisión E).
List<ScopeHolding> scopeHoldingsOf(
  CreationScopeSummary summary,
  List<StudyCreation> creations,
) {
  bool created(StudyCreationKind kind) => creations.any(
    (c) =>
        c.kind == kind &&
        c.scope == summary.scope &&
        c.status == CreationStatus.ready,
  );
  return [
    if (summary.cards > 0) ScopeHolding.cards,
    if (summary.summaryDocuments > 0 && !created(StudyCreationKind.summary))
      ScopeHolding.summary,
    if (summary.synthesisDocuments > 0 && !created(StudyCreationKind.synthesis))
      ScopeHolding.synthesis,
  ];
}

/// Una fila de lo que el recorte ya tenía, con el mismo dibujo que las de «Lo
/// creado» (M12): arriba y en grande qué es —«Tarjetas de repaso», «Resumen»,
/// «Síntesis»—, abajo y chico el ícono de su tipo en su color y cuánto hay, y
/// una flecha que dice que se abre.
///
/// - **Las tarjetas** abren la sesión de esas tarjetas ([openScopeCards]).
/// - **El resumen y la síntesis** abren la vista viva de extraer, sin IA ni
///   costo ([openScopeExtract]).
class ScopeHoldingTile extends ConsumerStatefulWidget {
  const ScopeHoldingTile({
    required this.holding,
    required this.summary,
    super.key,
  });

  final ScopeHolding holding;
  final CreationScopeSummary summary;

  @override
  ConsumerState<ScopeHoldingTile> createState() => _ScopeHoldingTileState();
}

class _ScopeHoldingTileState extends ConsumerState<ScopeHoldingTile> {
  /// Mientras se arma la vista viva: un segundo toque no crea otra.
  var _opening = false;

  Future<void> _open() async {
    final scope = widget.summary.scope;
    switch (widget.holding) {
      case ScopeHolding.cards:
        openScopeCards(context, scope);
      case ScopeHolding.summary || ScopeHolding.synthesis:
        if (_opening) return;
        setState(() => _opening = true);
        try {
          await openScopeExtract(context, ref, scope, widget.holding.kind);
        } finally {
          if (mounted) setState(() => _opening = false);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = widget.summary;
    final holding = widget.holding;
    final spec = ref.watch(creationKindRegistryProvider).of(holding.kind);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final iconSize = MediaQuery.textScalerOf(
      context,
    ).scale(16).clamp(16.0, 28.0);

    final title = switch (holding) {
      ScopeHolding.cards => l10n.f43S17HeldCards,
      ScopeHolding.summary => l10n.f43DataKindSummary,
      ScopeHolding.synthesis => l10n.f43DataKindSynthesis,
    };
    final marked = switch (holding) {
      ScopeHolding.cards => 0,
      ScopeHolding.summary => summary.summaryDocuments,
      ScopeHolding.synthesis => summary.synthesisDocuments,
    };
    final detail = holding == ScopeHolding.cards
        ? l10n.f43StudioCards(summary.cards)
        : marked >= summary.documents
        ? l10n.f43S17HeldMarkedAll(marked)
        : l10n.f43S17HeldMarkedSome(marked, summary.documents);

    return InkWell(
      key: ValueKey('scope-holding-${holding.name}'),
      onTap: _opening ? null : () => unawaited(_open()),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        spec.iconData,
                        size: iconSize,
                        color: spec.accent.resolve(
                          theme.brightness,
                          scheme.surface,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          detail,
                          key: ValueKey('scope-holding-detail-${holding.name}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Abre la vista viva de [kind] —el resumen o la síntesis— de [scope], sin IA
/// ni costo (decisión E, M10).
///
/// Si ya hay una de ese tipo creada sobre este mismo recorte, abre la más
/// nueva. Si no, la crea como su tarjeta de crear —con las opciones por
/// defecto de su tipo y el último idioma elegido— y la abre. Sus fuentes son
/// los documentos del recorte que ya lo tienen marcado: así no hay ninguno al
/// que haya que pedirle el análisis, que es lo único de extraer que usa la IA.
Future<void> openScopeExtract(
  BuildContext context,
  WidgetRef ref,
  CreationScope scope,
  StudyCreationKind kind,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failed = AppLocalizations.of(context)!.f43StudioCreateFailed;
  final creations = await ref
      .read(studyCreationRepositoryProvider)
      .watchByScope(scope)
      .first;
  if (!context.mounted) return;
  for (final creation in creations) {
    if (creation.kind == kind &&
        creation.scope == scope &&
        creation.status == CreationStatus.ready) {
      openCreation(context, creation);
      return;
    }
  }

  final resolver = ref.read(creationScopeResolverProvider);
  final ids =
      (await resolver.documentIds(scope)).getRight().toNullable() ?? const [];
  final sources =
      (await resolver.sourcesOf(ids)).getRight().toNullable() ?? const [];
  final marked = [
    for (final source in sources)
      if (source.isLive &&
          (kind == StudyCreationKind.summary
              ? source.hasSummary
              : source.hasSynthesis))
        source.documentId,
  ];
  if (!context.mounted) return;
  if (marked.isEmpty) {
    // Se desmarcó mientras tanto: la fila ya se va sola.
    return;
  }
  final spec = ref.read(creationKindRegistryProvider).of(kind);
  final created = await ref
      .read(creationQueueProvider)
      .create(
        CreationRequest(
          kind: kind,
          scope: scope,
          sourceIds: marked,
          options: spec.withDefaults(const {}),
          languageCode:
              ref.read(creationLastChoicesProvider).languageCode ?? 'es',
        ),
      );
  if (!context.mounted) return;
  created.match(
    (_) => messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failed))),
    (creation) => openCreation(context, creation),
  );
}
