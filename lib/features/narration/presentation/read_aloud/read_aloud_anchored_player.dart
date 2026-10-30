import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/reading_queue.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_player_extent.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_speed_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_face.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart'
    show mediaSkipStep;
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El reproductor anclado del lector en voz alta (F47, paso 2, capturas 3, 7,
/// 8 y 15): abajo y a lo ancho, encima de la barra de navegación, como el de
/// un reproductor de música. Una pieza de toda la app —lo monta
/// `ReadAloudOverlay`—, que el marco de lectura (paso 1) usa tal cual.
///
/// **Abierto** ([expanded]):
/// - el título, que se desliza si no entra, con qué voz y a qué velocidad;
/// - ⟲ Repetir, ☰ Cola y ⌄ Achicar;
/// - la barra de avance, con el tiempo leído y el total;
/// - la cara de la voz, −10 s, ▶ grande en el color de acento, +10 s y la
///   velocidad, «1,0×».
///
/// **Achicado**: una línea con ▶, el título, +10 s y ⌃. Arrastrarlo hacia
/// abajo deja de leer.
class ReadAloudAnchoredPlayer extends ConsumerWidget {
  const ReadAloudAnchoredPlayer({
    required this.title,
    required this.expanded,
    required this.onSpeed,
    required this.onVoice,
    required this.onQueue,
    this.onHeight,
    super.key,
  });

  /// Lo que se lee. Viene de afuera y no del estado: al cerrar, el estado ya
  /// no tiene documento pero el reproductor todavía se está yendo.
  final String title;

  final bool expanded;
  final VoidCallback onSpeed;
  final VoidCallback onVoice;
  final VoidCallback onQueue;

  /// El alto que ocupa, con el borde seguro de abajo si lo lleva, cada vez
  /// que cambia: el de su forma de ahora, no el de mientras se anima —ver
  /// `readAloudPlayerExtentProvider`—.
  final ValueChanged<double>? onHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final still = MediaQuery.disableAnimationsOf(context);
    final onHeight = this.onHeight;
    // El borde seguro lo agrega `SafeArea`, afuera de lo que se mide.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final form = expanded
        ? _OpenPlayer(
            key: const Key('read-aloud-player'),
            title: title,
            onSpeed: onSpeed,
            onVoice: onVoice,
            onQueue: onQueue,
          )
        : _CollapsedPlayer(
            key: const Key('read-aloud-collapsed'),
            title: title,
          );
    // Se mide lo de adentro, que ya tiene su alto final: `AnimatedSize` anima
    // el de afuera.
    final measured = onHeight == null
        ? form
        : HeightProbe(
            onHeight: (height) => onHeight(height + bottomInset),
            child: form,
          );

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 8,
      shadowColor: scheme.shadow.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        // Sin animaciones, sin `AnimatedSize`: con duración cero se cambia a
        // sí mismo mientras se mide, y Flutter lo rechaza.
        child: still
            ? measured
            : AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: measured,
              ),
      ),
    );
  }
}

class _OpenPlayer extends ConsumerWidget {
  const _OpenPlayer({
    required this.title,
    required this.onSpeed,
    required this.onVoice,
    required this.onQueue,
    super.key,
  });

  final String title;
  final VoidCallback onSpeed;
  final VoidCallback onVoice;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final controller = ref.read(readAloudControllerProvider.notifier);
    final (playing, speed, voice, repeat, waiting) = ref.watch(
      readAloudControllerProvider.select(
        (s) => (
          s.playing,
          s.speed,
          s.voice,
          s.queue.repeat,
          s.queue.upcoming.length,
        ),
      ),
    );
    final speedText = formatReadAloudSpeed(speed, locale);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarqueeText(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const _StatusLine(),
                  ],
                ),
              ),
              _RepeatButton(repeat: repeat, onPressed: controller.cycleRepeat),
              IconButton(
                key: const Key('read-aloud-queue'),
                tooltip: l10n.f47P2QueueCount(waiting),
                onPressed: onQueue,
                icon: Badge(
                  isLabelVisible: waiting > 0,
                  label: Text('$waiting'),
                  child: const Icon(Icons.queue_music_rounded),
                ),
              ),
              IconButton(
                key: const Key('read-aloud-minimize'),
                tooltip: l10n.f47P2Collapse,
                onPressed: controller.minimize,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.only(right: 8), child: _TimeBar()),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Tooltip(
                    message: l10n.f47P2VoiceFace(
                      readAloudVoiceName(voice, l10n),
                    ),
                    child: InkResponse(
                      key: const Key('read-aloud-voice'),
                      onTap: onVoice,
                      radius: 28,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: ReadAloudVoiceFace(),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('read-aloud-replay'),
                tooltip: l10n.readAloudReplay,
                iconSize: 30,
                onPressed: () => unawaited(controller.skip(-mediaSkipStep)),
                icon: const Icon(Icons.replay_10_rounded),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const Key('read-aloud-play'),
                tooltip: playing ? l10n.mediaPlayerPause : l10n.mediaPlayerPlay,
                iconSize: 36,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  fixedSize: const Size.square(64),
                ),
                onPressed: () => unawaited(controller.togglePlay()),
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                key: const Key('read-aloud-forward'),
                tooltip: l10n.readAloudForward,
                iconSize: 30,
                onPressed: () => unawaited(controller.skip(mediaSkipStep)),
                icon: const Icon(Icons.forward_10_rounded),
              ),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Semantics(
                      button: true,
                      label: l10n.f47P2SpeedButton(speedText),
                      excludeSemantics: true,
                      child: FilledButton.tonal(
                        key: const Key('read-aloud-speed'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(52, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        onPressed: onSpeed,
                        child: Text(speedText),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CollapsedPlayer extends ConsumerWidget {
  const _CollapsedPlayer({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.read(readAloudControllerProvider.notifier);
    final playing = ref.watch(
      readAloudControllerProvider.select((s) => s.playing),
    );

    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.readAloudClose): () =>
            unawaited(controller.close()),
      },
      child: GestureDetector(
        // Arrastrarlo hacia abajo lo saca, como el de un reproductor de
        // música; para el lector de pantalla, la acción «Dejar de leer».
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 300) {
            unawaited(controller.close());
          }
        },
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
              child: Row(
                children: [
                  IconButton.filled(
                    key: const Key('read-aloud-collapsed-play'),
                    tooltip: playing
                        ? l10n.mediaPlayerPause
                        : l10n.mediaPlayerPlay,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                    ),
                    onPressed: () => unawaited(controller.togglePlay()),
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      button: true,
                      hint: l10n.f47P2Expand,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: controller.expand,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: MarqueeText(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('read-aloud-collapsed-forward'),
                    tooltip: l10n.readAloudForward,
                    onPressed: () => unawaited(controller.skip(mediaSkipStep)),
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                  IconButton(
                    key: const Key('read-aloud-expand'),
                    tooltip: l10n.f47P2Expand,
                    onPressed: controller.expand,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                ],
              ),
            ),
            // El avance, como un hilo en el borde de arriba.
            const Positioned(left: 0, right: 0, top: 0, child: _Thread()),
          ],
        ),
      ),
    );
  }
}

/// Debajo del título: con qué voz y a qué velocidad suena, en pausa, si
/// terminó o si el motor falló; y la luna si hay un Temporizador para
/// dormir.
class _StatusLine extends ConsumerWidget {
  const _StatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final (playing, failed, finished, speed, voice, sleeping) = ref.watch(
      readAloudControllerProvider.select(
        (s) => (
          s.playing,
          s.failed,
          s.finished,
          s.speed,
          s.voice,
          s.sleep != null,
        ),
      ),
    );
    final voiceName = readAloudVoiceName(voice, l10n);
    final speedText = formatReadAloudSpeed(speed, locale);
    final text = failed
        ? l10n.readAloudFailed
        : finished
        ? l10n.f47P2Finished
        : playing
        ? l10n.f47P2ReadingWith(voiceName, speedText)
        : l10n.f47P2PausedWith(voiceName, speedText);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: failed ? scheme.error : scheme.onSurfaceVariant,
    );

    return Row(
      key: const Key('read-aloud-status'),
      children: [
        if (sleeping) ...[
          Icon(
            Icons.bedtime_outlined,
            key: const Key('read-aloud-sleeping'),
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// ⟲: no repetir, repetir la cola o repetir esto, uno detrás del otro.
class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.repeat, required this.onPressed});

  final ReadAloudRepeat repeat;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('read-aloud-repeat'),
      tooltip: switch (repeat) {
        ReadAloudRepeat.off => l10n.f47P2RepeatOff,
        ReadAloudRepeat.all => l10n.f47P2RepeatAll,
        ReadAloudRepeat.one => l10n.f47P2RepeatOne,
      },
      isSelected: repeat != ReadAloudRepeat.off,
      onPressed: onPressed,
      icon: const Icon(Icons.repeat_rounded),
      selectedIcon: Icon(
        repeat == ReadAloudRepeat.one
            ? Icons.repeat_one_on_rounded
            : Icons.repeat_on_rounded,
      ),
    );
  }
}

/// La barra de avance, con el tiempo leído y el total (F47, paso 2). Se
/// arrastra, y al soltarla sigue desde ahí; mientras se arrastra marca el
/// tiempo al que va.
class _TimeBar extends ConsumerStatefulWidget {
  const _TimeBar();

  @override
  ConsumerState<_TimeBar> createState() => _TimeBarState();
}

class _TimeBarState extends ConsumerState<_TimeBar> {
  /// Lo que marca la barra mientras se arrastra, de 0 a 1.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final (elapsed, total) = ref.watch(
      readAloudControllerProvider.select((s) => (s.elapsed, s.total)),
    );
    final totalMicros = total.inMicroseconds;
    final fraction =
        _dragging ??
        (totalMicros == 0
            ? 0.0
            : (elapsed.inMicroseconds / totalMicros).clamp(0.0, 1.0));
    final shown = _dragging == null
        ? elapsed
        : Duration(microseconds: (totalMicros * fraction).round());
    final timeStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            key: const Key('read-aloud-progress'),
            value: fraction,
            label: l10n.f47P2Seek,
            semanticFormatterCallback: (value) => l10n.f47P2TimeOf(
              formatReadAloudTime(
                Duration(microseconds: (totalMicros * value).round()),
              ),
              formatReadAloudTime(total),
            ),
            onChanged: totalMicros == 0
                ? null
                : (value) => setState(() => _dragging = value),
            onChangeEnd: (value) {
              setState(() => _dragging = null);
              unawaited(
                ref
                    .read(readAloudControllerProvider.notifier)
                    .seekTo(
                      Duration(microseconds: (totalMicros * value).round()),
                    ),
              );
            },
          ),
        ),
        // El tiempo ya lo dice la barra al lector de pantalla.
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  formatReadAloudTime(shown),
                  key: const Key('read-aloud-elapsed'),
                  style: timeStyle,
                ),
                const Spacer(),
                Text(
                  formatReadAloudTime(total),
                  key: const Key('read-aloud-total'),
                  style: timeStyle,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// El avance del reproductor achicado: un hilo, sin controles.
class _Thread extends ConsumerWidget {
  const _Thread();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (elapsed, total) = ref.watch(
      readAloudControllerProvider.select((s) => (s.elapsed, s.total)),
    );
    return ExcludeSemantics(
      child: LinearProgressIndicator(
        key: const Key('read-aloud-thread'),
        value: total == Duration.zero
            ? 0
            : (elapsed.inMicroseconds / total.inMicroseconds).clamp(0.0, 1.0),
        minHeight: 3,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}

/// «4:05», o «1:02:09» pasada la hora.
String formatReadAloudTime(Duration time) {
  final minutes = time.inMinutes.remainder(60);
  final seconds = time.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (time.inHours == 0) return '$minutes:$seconds';
  return '${time.inHours}:${minutes.toString().padLeft(2, '0')}:$seconds';
}

/// Un texto de una línea que, si no entra, se desliza para mostrarse entero
/// (F47, paso 2: el título del reproductor). Se desliza dos veces, con una
/// pausa al principio y al final, y después queda quieto con sus tres
/// puntos: un título que se mueve para siempre distrae de lo que se lee.
///
/// Con «sin animaciones» no se mueve nunca. Para el lector de pantalla es
/// el texto entero, se mueva o no.
class MarqueeText extends StatefulWidget {
  const MarqueeText(this.text, {this.style, super.key});

  final String text;
  final TextStyle? style;

  /// Cuántos píxeles por segundo se desliza.
  static const speed = 40.0;

  /// Cuánto se queda quieto al principio y al final de cada pasada.
  static const pause = Duration(milliseconds: 1200);

  /// Cuántas pasadas da.
  static const passes = 2;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);

  /// Cuánto no entra, de la última vez que se midió; 0 si entra.
  double _overflow = 0;
  var _passesLeft = MarqueeText.passes;

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.reset();
      _passesLeft = MarqueeText.passes;
      _overflow = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _passesLeft--;
    if (_passesLeft > 0) {
      unawaited(_controller.forward(from: 0));
    } else if (mounted) {
      // Terminó de deslizarse: vuelve al comienzo, con sus tres puntos.
      setState(() {});
    }
  }

  /// Arranca la primera pasada si hace falta, fuera de la construcción.
  void _start(double overflow) {
    if (overflow == _overflow) return;
    _overflow = overflow;
    final scroll = Duration(
      milliseconds: (overflow / MarqueeText.speed * 1000).round(),
    );
    _controller.duration = MarqueeText.pause * 2 + scroll;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _passesLeft <= 0 || _controller.isAnimating) return;
      unawaited(_controller.forward(from: 0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final still = MediaQuery.disableAnimationsOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    Widget plain() => Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        final width = painter.width;
        final height = painter.height;
        painter.dispose();
        final overflow = width - constraints.maxWidth;
        if (still || overflow <= 0 || !constraints.hasBoundedWidth) {
          return plain();
        }
        _start(overflow);
        if (_passesLeft <= 0 && !_controller.isAnimating) return plain();

        final pause = MarqueeText.pause.inMicroseconds;
        return SizedBox(
          height: height,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final total = _controller.duration!.inMicroseconds;
                final at = _controller.value * total;
                final t = ((at - pause) / (total - 2 * pause)).clamp(0.0, 1.0);
                return Transform.translate(
                  offset: Offset(-overflow * Curves.easeInOut.transform(t), 0),
                  child: child,
                );
              },
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                maxWidth: double.infinity,
                child: Text(
                  widget.text,
                  maxLines: 1,
                  softWrap: false,
                  style: style,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
