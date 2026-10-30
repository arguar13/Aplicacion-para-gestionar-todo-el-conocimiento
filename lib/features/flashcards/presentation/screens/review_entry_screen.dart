import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_customize_sheet.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_kind_grid.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_scope_picker.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_tile.dart';
import 'package:sinapsis/features/creations/presentation/widgets/scope_holdings.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/ai_flashcards_banner.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_today_strip.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Repasar (F43, punto 2 del plan), como el «Studio» de NotebookLM, sin
/// perder nada de lo de antes (F31):
///
/// - **arriba**, la racha, el historial y exportar a Anki, como siempre
///   («Crear tarjetas con IA» está en la hoja de «Tarjetas didácticas», M18);
/// - **el selector** de sobre qué se estudia —todo lo procesado, un
///   documento, un cuaderno o un tema, nunca la Biblioteca—, que manda en toda
///   la pantalla;
/// - **las diez tarjetas de crear**, que abren su hoja de personalizar;
/// - **«Lo creado»** sobre lo elegido: primero lo que el recorte ya tenía
///   —sus tarjetas, su resumen y su síntesis marcados (M10)— y después lo
///   creado, lo más nuevo arriba;
/// - **«Para hoy»**, compacto, con «Empezar» y «Mis tarjetas» (M14, decisión
///   K): lo de crear y lo creado quedan juntos, y el repaso del día justo
///   después.
///
/// Va todo en una sola lista que se desplaza: con letra grande o en un
/// teléfono chico nada queda fijo ocupando la pantalla, ni se corta.
///
/// [requestedScopeKey] es el recorte que pide la dirección
/// (`/review?scope=…`, «Crear en Repasar»): se elige al abrir y cada vez que
/// cambia.
class ReviewEntryScreen extends ConsumerStatefulWidget {
  const ReviewEntryScreen({this.requestedScopeKey, super.key});

  final String? requestedScopeKey;

  @override
  ConsumerState<ReviewEntryScreen> createState() => _ReviewEntryScreenState();
}

class _ReviewEntryScreenState extends ConsumerState<ReviewEntryScreen> {
  var _exporting = false;

  @override
  void initState() {
    super.initState();
    _applyRequested();
  }

  @override
  void didUpdateWidget(ReviewEntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestedScopeKey != widget.requestedScopeKey) {
      _applyRequested();
    }
  }

  /// Elige el recorte de la dirección, si se entiende. Después del cuadro: un
  /// proveedor no se cambia mientras se arma la pantalla.
  void _applyRequested() {
    final key = widget.requestedScopeKey;
    final scope = key == null ? null : CreationScope.parse(key);
    if (scope == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) chooseRepasarScope(ref, scope);
    });
  }

  Future<void> _chooseScope(CreationScope current) async {
    final chosen = await showCreationScopePicker(context, current: current);
    if (chosen == null || !mounted) return;
    chooseRepasarScope(ref, chosen);
  }

  void _start(StudyScope scope, {bool practice = false}) {
    unawaited(
      context.push(
        RoutePaths.reviewSessionFor(
          kind: scope.kind.name,
          id: scope.id,
          practice: practice,
        ),
      ),
    );
  }

  /// Pregunta el alcance (F17, D4) y el formato (commit 5) antes de
  /// exportar: incremental por defecto —solo lo que nunca se exportó—, con
  /// «todo el mazo» como interruptor aparte, y el `.apkg` completo por
  /// defecto, con TSV/CSV como camino alternativo (D5). No distingue
  /// "canceló el diálogo de guardado" de "lo guardó" — igual que el resto
  /// de las exportaciones de la app (ver `ExportItemUseCase`). Solo avisa
  /// cuando algo salió mal de verdad.
  Future<void> _exportToAnki() async {
    final l10n = AppLocalizations.of(context)!;
    final scope = await _chooseExportScope(context, l10n);
    if (scope == null || !mounted) return;

    setState(() => _exporting = true);

    final result = await ref.read(exportFlashcardsToAnkiUseCaseProvider)(
      ExportFlashcardsToAnkiParams(
        exportAll: scope.exportAll,
        format: scope.format,
      ),
    );
    if (!mounted) return;
    setState(() => _exporting = false);

    result.match((failure) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    }, (_) {});
  }

  Future<({bool exportAll, AnkiExportFormat format})?> _chooseExportScope(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return showDialog(
      context: context,
      builder: (context) => _ExportScopeDialog(l10n: l10n),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scope = ref.watch(repasarScopeProvider);
    final studyScope = scope.studyScope;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reviewTitle),
        actions: [
          // La racha y el historial se ven siempre (F39, decisión D): ya no
          // hay un interruptor en Ajustes que los apague.
          const _StreakIndicator(),
          // F43, M17: las estadísticas y el historial, juntos; cada uno abre
          // su pestaña de la misma pantalla.
          IconButton(
            key: const Key('review-open-stats'),
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: l10n.f43S20StatsTooltip,
            onPressed: () => context.push(kRouteReviewStats),
          ),
          IconButton(
            key: const Key('review-open-history'),
            icon: const Icon(Icons.show_chart_rounded),
            tooltip: l10n.reviewHistoryTooltip,
            onPressed: () => context.push(RoutePaths.reviewHistory),
          ),
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            tooltip: l10n.reviewExportToAnkiTooltip,
            onPressed: _exporting ? null : _exportToAnki,
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: CustomScrollView(
              key: const Key('review-entry'),
              slivers: [
                // Cómo va el pedido de tarjetas con IA (F30), si hay uno: trae
                // su propio margen.
                const SliverToBoxAdapter(child: AiFlashcardsBanner()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverList.list(
                    children: [
                      CreationScopePill(
                        scope: scope,
                        onTap: () => unawaited(_chooseScope(scope)),
                      ),
                      const SizedBox(height: 20),
                      CreationKindGrid(
                        onOpen: (kind) => unawaited(
                          showCreationCustomizeSheet(
                            context,
                            kind: kind,
                            scope: scope,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _CreatedHeader(title: l10n.f43StudioCreatedTitle),
                    ],
                  ),
                ),
                _Created(scope: scope),
                // El repaso del día, justo después de lo de crear y lo creado
                // (decisión K), con «Mis tarjetas» adentro.
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  sliver: SliverToBoxAdapter(
                    child: ReviewTodayStrip(
                      scope: studyScope,
                      onStart: () => _start(studyScope),
                      onPractice: () => _start(studyScope, practice: true),
                      onResetScope: () => chooseRepasarScope(
                        ref,
                        const CreationScope.allProcessed(),
                      ),
                      onMyCards: () => unawaited(context.push(kRouteCards)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «─── Lo creado ───», como en la captura.
class _CreatedHeader extends StatelessWidget {
  const _CreatedHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = Expanded(
      child: Divider(color: theme.colorScheme.outlineVariant),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          line,
          Flexible(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// Lo creado sobre el recorte elegido: arriba, lo que el recorte ya tenía
/// (M10); después, las creaciones, lo más nuevo arriba. Las dos partes están
/// al día: marcar el resumen en el original, sumar una tarjeta o crear algo
/// aparece solo.
class _Created extends ConsumerWidget {
  const _Created({required this.scope});

  final CreationScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final creations = ref.watch(studyCreationsProvider(scope));
    final summary = ref.watch(creationScopeSummaryProvider(scope));
    final list = creations.valueOrNull;
    final held = summary.valueOrNull;

    Widget line(String text, {Key? key, bool error = false}) => SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      sliver: SliverToBoxAdapter(
        child: Text(
          text,
          key: key,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: error
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    if (list == null) {
      // Lo que tarda en llegar es un instante: el lugar, quieto.
      return creations.hasError
          ? line(l10n.f43StudioCreatedFailedLoad, error: true)
          : const SliverToBoxAdapter(child: SizedBox(height: 48));
    }
    // Si las cifras del recorte fallan, lo creado se ve igual; mientras
    // llegan, no se dice «vacío» antes de tiempo.
    if (held == null && summary.isLoading) {
      return const SliverToBoxAdapter(child: SizedBox(height: 48));
    }
    final holdings = held == null
        ? const <ScopeHolding>[]
        : scopeHoldingsOf(held, list);
    if (list.isEmpty && holdings.isEmpty) {
      return line(
        l10n.f43StudioCreatedEmpty,
        key: const Key('repasar-created-empty'),
      );
    }
    return SliverPadding(
      // Las filas son planas y traen su propio margen, como en NotebookLM.
      padding: const EdgeInsets.only(top: 4),
      sliver: SliverList.builder(
        key: const Key('repasar-created'),
        itemCount: holdings.length + list.length,
        itemBuilder: (context, index) => index < holdings.length
            ? ScopeHoldingTile(holding: holdings[index], summary: held!)
            : CreationTile(creation: list[index - holdings.length]),
      ),
    );
  }
}

/// La racha (F17, D3/D6/commit 8): oculto sin ninguna, mismo criterio que
/// la insignia de pendientes de `dueFlashcardCountProvider` —nada que
/// mostrar, nada que ocupar lugar—. El color marca si hoy ya cuenta o si
/// todavía hace falta hacer algo para mantenerla.
class _StreakIndicator extends ConsumerWidget {
  const _StreakIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(currentStreakProvider).valueOrNull;
    if (streak == null || streak.days == 0) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = streak.activeToday
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: streak.activeToday
          ? l10n.reviewStreakActiveTooltip(streak.days)
          : l10n.reviewStreakPendingTooltip(streak.days),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          key: const Key('review-streak-indicator'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, size: 18, color: color),
            const SizedBox(width: 4),
            Text(
              '${streak.days}',
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// El interruptor de F17, D4 —«exportar todo» empieza apagado, el camino
/// incremental es el que se ofrece por defecto— y el formato de F17,
/// commit 5 —el `.apkg` completo por defecto, TSV/CSV como camino
/// alternativo (D5)—.
class _ExportScopeDialog extends StatefulWidget {
  const _ExportScopeDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_ExportScopeDialog> createState() => _ExportScopeDialogState();
}

class _ExportScopeDialogState extends State<_ExportScopeDialog> {
  var _exportAll = false;
  var _format = AnkiExportFormat.apkg;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.reviewExportToAnkiTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('review-export-all-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.reviewExportToAnkiExportAll),
            value: _exportAll,
            onChanged: (value) => setState(() => _exportAll = value),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.reviewExportToAnkiFormatTitle,
            style: theme.textTheme.labelLarge,
          ),
          RadioGroup<AnkiExportFormat>(
            groupValue: _format,
            onChanged: (value) => setState(() => _format = value!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final format in AnkiExportFormat.values)
                  RadioListTile<AnkiExportFormat>(
                    key: Key('review-export-format-${format.name}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(_formatLabel(l10n, format)),
                    value: format,
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('review-export-confirm'),
          onPressed: () => Navigator.of(
            context,
          ).pop((exportAll: _exportAll, format: _format)),
          child: Text(l10n.reviewExportToAnkiConfirm),
        ),
      ],
    );
  }

  String _formatLabel(AppLocalizations l10n, AnkiExportFormat format) =>
      switch (format) {
        AnkiExportFormat.apkg => l10n.reviewExportToAnkiFormatApkg,
        AnkiExportFormat.tsv => l10n.reviewExportToAnkiFormatTsv,
        AnkiExportFormat.csv => l10n.reviewExportToAnkiFormatCsv,
      };
}
