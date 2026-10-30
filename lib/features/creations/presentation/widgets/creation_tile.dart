import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_actions.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_kind_icon.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué fila de «Lo creado» está abierta con sus botones a la vista (al
/// deslizarla): una sola a la vez.
final openCreationRowProvider = StateProvider<String?>((ref) => null);

/// Una fila de «Lo creado» (F43), como las del Studio de NotebookLM: plana, y
/// que dice de qué es (M12):
///
/// - **arriba, grande**, de dónde sale —el documento, el cuaderno o el tema;
///   con varias fuentes, «Lazarillo y 2 más»; una fuente borrada lo dice—;
/// - **abajo, chico**, el ícono de su tipo en su color, el tipo, el título
///   propio si lo tiene y es otro, y cuándo: «Tarjetas didácticas · San
///   Jerónimo: Vida y obra · Hace 5 min».
///
/// - **Tocarla**, lista, abre su visor.
/// - **Mantenerla apretada** (o el clic derecho) abre su menú flotante:
///   Compartir y Descargar —si su tipo arma su archivo—, Cambiar nombre, Ver
///   petición y fuentes (con las fuentes como fichas tocables, M6),
///   reintentar, cancelar o volver a generar según su estado, y Eliminar, que
///   la manda a la papelera con «Deshacer».
/// - **Deslizarla a la izquierda** muestra dos botones cuadrados al ras de la
///   derecha —Descargar y Eliminar—, y queda abierta o cerrada según hasta
///   dónde se la llevó. Solo una abierta a la vez. Sigue al dedo; el encaje
///   final se anima, salvo con «sin animaciones», que encaja de una.
/// - **Mientras se genera** dice en qué va, con un brillo que recorre (quieto
///   con «sin animaciones»); **si falló**, por qué, con «Reintentar».
///
/// Lo del menú está también, entero, en las acciones del lector de pantalla.
///
/// La usan «Lo creado» de Repasar y la sección «En Repasar» de un documento
/// procesado y de un cuaderno.
class CreationTile extends ConsumerStatefulWidget {
  const CreationTile({required this.creation, super.key});

  final StudyCreation creation;

  @override
  ConsumerState<CreationTile> createState() => _CreationTileState();
}

class _CreationTileState extends ConsumerState<CreationTile>
    with SingleTickerProviderStateMixin {
  /// Cuánto se corrió la fila a la izquierda: 0 cerrada, `-ancho de los
  /// botones` abierta.
  var _offset = 0.0;
  var _from = 0.0;
  var _to = 0.0;

  late final _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(_onSnapTick);

  StudyCreation get creation => widget.creation;

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  void _onSnapTick() => setState(
    () => _offset =
        _from + (_to - _from) * Curves.easeOutCubic.transform(_snap.value),
  );

  /// Lleva la fila a [target]: con el encaje animado, o de una con «sin
  /// animaciones».
  void _snapTo(double target) {
    final open = ref.read(openCreationRowProvider.notifier);
    if (target != 0) {
      open.state = creation.id;
    } else if (open.state == creation.id) {
      open.state = null;
    }
    _snap.stop();
    if (MediaQuery.disableAnimationsOf(context) || _offset == target) {
      setState(() => _offset = target);
      return;
    }
    _from = _offset;
    _to = target;
    unawaited(_snap.forward(from: 0));
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    _snap.stop();
    setState(
      () => _offset = (_offset + details.primaryDelta!).clamp(-width, 0),
    );
  }

  void _onDragEnd(DragEndDetails details, double width) {
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity < -300 || (velocity <= 300 && _offset < -width / 2);
    _snapTo(open ? -width : 0);
  }

  Future<void> _menu() async {
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    _snapTo(0);
    await showCreationActionsMenu(context, ref, creation, anchor: anchor);
  }

  Future<void> _run(CreationAction action) async {
    _snapTo(0);
    await runCreationAction(context, ref, creation, action);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spec = ref.watch(creationKindRegistryProvider).of(creation.kind);
    final ready = creation.status == CreationStatus.ready;
    final actions = availableCreationActions(ref, creation);
    final swipe = [
      if (actions.contains(CreationAction.download)) CreationAction.download,
      CreationAction.trash,
    ];
    final tileWidth = MediaQuery.textScalerOf(
      context,
    ).scale(76).clamp(76.0, 112.0);
    final width = tileWidth * swipe.length;

    // Si se abre otra, esta se cierra.
    ref.listen(openCreationRowProvider, (_, open) {
      if (open != creation.id && _offset != 0) _snapTo(0);
    });

    final row = InkWell(
      key: ValueKey('creation-tile-${creation.id}'),
      onTap: _offset != 0
          ? () => _snapTo(0)
          : ready
          ? () => openCreation(context, creation)
          : null,
      onLongPress: () => unawaited(_menu()),
      onSecondaryTap: () => unawaited(_menu()),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Origin(creation: creation),
            const SizedBox(height: 4),
            _KindLine(
              creation: creation,
              icon: spec.iconData,
              accent: spec.accent.resolve(theme.brightness, scheme.surface),
            ),
            if (!ready) ...[
              const SizedBox(height: 4),
              _Status(creation: creation),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      label: studyCreationKindLabel(l10n, creation.kind),
      customSemanticsActions: {
        for (final action in actions)
          if (action != CreationAction.open)
            CustomSemanticsAction(
              label: creationActionLabel(l10n, action),
            ): () =>
                unawaited(_run(action)),
      },
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
        onHorizontalDragEnd: (d) => _onDragEnd(d, width),
        child: ClipRect(
          child: Stack(
            children: [
              // Los botones, debajo, al ras de la derecha: solo mientras la
              // fila se corre, para que nunca se toquen sin verlos.
              if (_offset != 0)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: width,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final action in swipe)
                        Expanded(
                          child: _SwipeButton(
                            key: ValueKey(
                              'creation-swipe-${action.name}-${creation.id}',
                            ),
                            action: action,
                            onTap: () => unawaited(_run(action)),
                          ),
                        ),
                    ],
                  ),
                ),
              Transform.translate(
                offset: Offset(_offset, 0),
                child: ColoredBox(
                  // Corrida, tapa los botones con el fondo de lo que la tiene
                  // —la pantalla en Repasar, la tarjeta de «En Repasar» en un
                  // documento o un cuaderno—; quieta, no pinta nada: queda
                  // sobre cualquier fondo.
                  color: _offset == 0
                      ? Colors.transparent
                      : Material.maybeOf(context)?.color ??
                            theme.scaffoldBackgroundColor,
                  child: creation.status.isPending ? _Shimmer(child: row) : row,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un botón cuadrado de los que aparecen al deslizar una fila, como los de
/// NotebookLM: superficie tonal e ícono de contorno (Descargar con el tinte
/// principal).
class _SwipeButton extends StatelessWidget {
  const _SwipeButton({required this.action, required this.onTap, super.key});

  final CreationAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final download = action == CreationAction.download;
    return Material(
      color: download
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: creationActionLabel(l10n, action),
          child: Center(
            child: Icon(
              download
                  ? Icons.download_for_offline_outlined
                  : Icons.delete_outline,
              size: 28,
              color: download ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// De dónde sale [creation], al día.
CreationOrigin? _originOf(WidgetRef ref, StudyCreation creation) => ref
    .watch(
      creationOriginProvider(
        CreationOriginKey(
          creation.scope,
          CreationSourceIds(creation.sourceIds),
        ),
      ),
    )
    .valueOrNull;

/// Arriba y en grande, de dónde sale (M12): el documento, el cuaderno o el
/// tema; con varias fuentes, «Lazarillo y 2 más», con el «y 2 más» siempre a
/// la vista aunque el nombre no entre; si ya no está, lo dice.
class _Origin extends ConsumerWidget {
  const _Origin({required this.creation});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium;
    final key = ValueKey('creation-origin-${creation.id}');
    final origin = _originOf(ref, creation);

    // Lo que tarda en llegar es un instante: el renglón, en su alto.
    if (origin == null) return Text(' ', key: key, style: style);
    if (origin.deleted) {
      return Text(
        l10n.f43S17OriginDeleted(origin.more + 1),
        key: key,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    final name = Text(
      origin.name ?? l10n.f43StudioScopeAll,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (origin.more == 0) return KeyedSubtree(key: key, child: name);
    return Row(
      key: key,
      children: [
        Flexible(child: name),
        Text(' ${l10n.f43S17OriginMore(origin.more)}', style: style),
      ],
    );
  }
}

/// Abajo y chico (M12): el ícono del tipo en su color, el tipo, el título
/// propio —el que puso la IA o la persona, si dice algo más que el origen o
/// el tipo— y, lista, cuándo: «Tarjetas didácticas · San Jerónimo: Vida y
/// obra · Hace 5 min». Lo que no entra es el título, con «…»; el cuándo queda
/// siempre a la vista.
class _KindLine extends ConsumerWidget {
  const _KindLine({
    required this.creation,
    required this.icon,
    required this.accent,
  });

  final StudyCreation creation;
  final IconData icon;
  final Color accent;

  static bool _same(String a, String? b) =>
      b != null && a.toLowerCase() == b.trim().toLowerCase();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final kind = studyCreationKindLabel(l10n, creation.kind);
    final title = creation.title?.trim() ?? '';
    final ownTitle =
        title.isNotEmpty &&
        !_same(title, kind) &&
        !_same(title, _originOf(ref, creation)?.name);
    final ready = creation.status == CreationStatus.ready;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = ref.watch(clockProvider)();
    final iconSize = MediaQuery.textScalerOf(
      context,
    ).scale(16).clamp(16.0, 28.0);

    return Row(
      children: [
        Icon(icon, size: iconSize, color: accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: kind,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (ownTitle) TextSpan(text: ' · $title'),
              ],
            ),
            key: ValueKey('creation-meta-${creation.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ),
        if (ready)
          Text(
            ' · ${creationAgo(l10n, creation.createdAt, now, locale: locale)}',
            key: ValueKey('creation-when-${creation.id}'),
            maxLines: 1,
            style: muted,
          ),
      ],
    );
  }
}

/// Cómo va, debajo del tipo, mientras no está lista: en la cola, generándose
/// o fallida. Lista no dice nada más: el cuándo va en la línea del tipo.
class _Status extends ConsumerWidget {
  const _Status({required this.creation});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final locale = Localizations.localeOf(context).toLanguageTag();

    switch (creation.status) {
      case CreationStatus.ready:
        return const SizedBox.shrink();
      case CreationStatus.queued:
        return Text(
          creation.runNow
              ? l10n.f43StudioStatusQueued
              : l10n.f43StudioStatusLater,
          key: ValueKey('creation-status-${creation.id}'),
          style: muted,
        );
      case CreationStatus.generating:
        final progress = creation.progress;
        final step = creation.step;
        final percent = progress == null
            ? null
            : NumberFormat.percentPattern(locale).format(progress);
        final stepLabel = step == null
            ? l10n.f43DataStepWriting
            : creationStepLabel(l10n, step);
        final label = percent == null ? stepLabel : '$stepLabel · $percent';
        return Column(
          key: ValueKey('creation-status-${creation.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: muted),
            if (progress != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1).toDouble(),
                  minHeight: 4,
                ),
              ),
            ],
          ],
        );
      case CreationStatus.failed:
        final failure = creation.failure ?? CreationFailure.error;
        return Wrap(
          key: ValueKey('creation-status-${creation.id}'),
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(
              creationFailureMessage(l10n, failure),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
            TextButton.icon(
              key: ValueKey('creation-retry-${creation.id}'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () =>
                  unawaited(ref.read(creationQueueProvider).retry(creation.id)),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.f43StudioRetry),
            ),
          ],
        );
    }
  }
}

/// El brillo que recorre la fila mientras se genera. Con «sin animaciones»
/// queda quieto: un velo apenas más claro, sin moverse.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});

  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlight = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.06);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final still = !_controller.isAnimating;
        final t = still ? 0.5 : _controller.value;
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('creation-shimmer'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.zero,
                    gradient: LinearGradient(
                      begin: Alignment(-1.5 + 3 * t, -0.3),
                      end: Alignment(-0.5 + 3 * t, 0.3),
                      colors: [
                        highlight.withValues(alpha: 0),
                        highlight,
                        highlight.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
