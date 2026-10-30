import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/navigation/adaptive_scaffold.dart'
    show kNavRailBreakpoint;
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_anchored_player.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_audio_focus.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_dock.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_player.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_player_extent.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_queue_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_speed_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_face.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';

/// El alto de `NavigationBar` cuando el tema no dice otro: el de Material 3.
const _navigationBarHeight = 80.0;

/// Los avisos flotantes de Material, cuando el tema no dice otro margen.
const _snackBarInset = EdgeInsets.fromLTRB(15, 5, 15, 10);

/// El lector en voz alta de toda la app (F25): el botón redondo abajo a la
/// derecha y, mientras se lee, el reproductor anclado abajo y a lo ancho
/// (F47, paso 2), por encima de cualquier pantalla.
///
/// Va en el `builder` de `MaterialApp.router`, envolviendo a [child] —el
/// `Navigator` del router—: así sigue en pantalla, y leyendo, aunque se
/// cambie de pestaña o se abra una pantalla encima. Lo que no es el botón ni
/// el reproductor deja pasar los toques a la pantalla de abajo.
///
/// El botón aparece solo donde hay algo que leer —ver
/// `currentReadableProvider`— y no se está leyendo nada. El reproductor queda
/// encima de la barra de navegación cuando la hay, como el de un reproductor
/// de música, y encima de lo que se le pida esquivar —ver
/// `ReadAloudClearance`—. Los dos se hacen a un lado mientras se escribe —con
/// el teclado abierto— y mientras hay un diálogo o un panel abierto encima,
/// incluidos los suyos.
///
/// **Los avisos van por encima del reproductor**: cuánto ocupa se publica en
/// `readAloudPlayerExtentProvider`, y los avisos flotantes de Material suben
/// eso, así que nunca tapa un aviso ni su ✕.
///
/// Con la **Lectura enfocada** (Ajustes), el reproductor abierto se achica
/// solo mientras se desplaza cualquier pantalla, y vuelve al soltar.
class ReadAloudOverlay extends ConsumerStatefulWidget {
  const ReadAloudOverlay({
    required this.router,
    required this.child,
    super.key,
  });

  /// De dónde sale el `Navigator` para abrir los paneles —el lector está por
  /// encima de él— y si la pantalla de arriba tiene la barra de
  /// navegación.
  final GoRouter router;

  final Widget child;

  @override
  ConsumerState<ReadAloudOverlay> createState() => _ReadAloudOverlayState();
}

class _ReadAloudOverlayState extends ConsumerState<ReadAloudOverlay> {
  var _popupOnTop = false;
  var _onShell = false;
  var _checkScheduled = false;

  /// Si la persona está desplazando una pantalla, para la Lectura enfocada.
  var _scrolling = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_scheduleCheck);
    widget.router.routerDelegate.addListener(_scheduleCheck);
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(ReadAloudOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_scheduleCheck);
      widget.router.routerDelegate.addListener(_scheduleCheck);
      _scheduleCheck();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_scheduleCheck);
    widget.router.routerDelegate.removeListener(_scheduleCheck);
    super.dispose();
  }

  /// Vuelve a mirar qué hay arriba al final del cuadro, no en el momento del
  /// aviso: el router avisa a mitad de su construcción —que está debajo de
  /// este widget—, y el foco cambia a mitad de una navegación, con la ruta
  /// que lo tenía ya desmontándose.
  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _checkScheduled = false;
        if (!mounted) return;
        final onShell = _shellOnTop();
        final popup = _popupInFocus();
        if (onShell == _onShell && popup == _popupOnTop) return;
        setState(() {
          _onShell = onShell;
          _popupOnTop = popup;
        });
      })
      ..ensureVisualUpdate();
  }

  /// Si lo de arriba es una pantalla de las pestañas —con la barra de
  /// navegación abajo— y no una abierta por encima de ellas, como el modo
  /// lectura.
  bool _shellOnTop() {
    final matches = widget.router.routerDelegate.currentConfiguration.matches;
    return matches.isNotEmpty && matches.last is ShellRouteMatch;
  }

  /// Un diálogo, un panel de abajo o un menú se llevan el foco al abrirse
  /// —y lo devuelven al cerrarse—: si lo que tiene el foco vive en una ruta
  /// emergente, hay algo encima de la pantalla y el lector no lo tapa.
  bool _popupInFocus() {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        focused.mounted &&
        ModalRoute.of(focused) is PopupRoute;
  }

  /// La Lectura enfocada mira si la persona desplaza algo: el comienzo y el
  /// final de cada arrastre, no cada píxel. Solo lo vertical: pasar fichas
  /// de costado no es leer.
  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final scrolling = notification.direction != ScrollDirection.idle;
    if (scrolling != _scrolling) setState(() => _scrolling = scrolling);
    return false;
  }

  /// Cuánto tienen que subir los avisos flotantes para quedar por encima del
  /// reproductor: lo que ocupa, menos lo que el andamio de la pantalla ya
  /// esquiva solo —la barra de navegación, o el borde seguro—.
  double _snackBarLift(MediaQueryData media) {
    final extent = ref.watch(
      readAloudPlayerExtentProvider.select((extent) => extent.resting),
    );
    if (extent == 0) return 0;
    final wide = media.size.width >= kNavRailBreakpoint;
    final avoided = _onShell && !wide
        ? (NavigationBarTheme.of(context).height ?? _navigationBarHeight) +
              media.padding.bottom
        : media.padding.bottom;
    return math.max(0, extent - avoided);
  }

  @override
  Widget build(BuildContext context) {
    // Uno a la vez con el audio: ver `readAloudAudioFocusProvider`.
    ref.watch(readAloudAudioFocusProvider);
    final theme = Theme.of(context);
    final inset = theme.snackBarTheme.insetPadding ?? _snackBarInset;
    final lift = _snackBarLift(MediaQuery.of(context));

    return Stack(
      children: [
        // Siempre con el mismo `Theme` encima, aunque no haya que subir nada:
        // ponerlo y sacarlo volvería a armar todas las pantallas.
        Theme(
          data: theme.copyWith(
            snackBarTheme: theme.snackBarTheme.copyWith(
              insetPadding: inset.copyWith(bottom: inset.bottom + lift),
            ),
          ),
          child: NotificationListener<UserScrollNotification>(
            onNotification: _onUserScroll,
            child: widget.child,
          ),
        ),
        // Un `Overlay` propio: por encima del `Navigator` no hay ninguno, y
        // los tooltips de los botones lo necesitan.
        Positioned.fill(
          child: Overlay.wrap(
            child: _ReadAloudLayer(
              navigatorKey: widget.router.routerDelegate.navigatorKey,
              onShell: _onShell,
              popupOnTop: _popupOnTop,
              scrolling: _scrolling,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadAloudLayer extends ConsumerStatefulWidget {
  const _ReadAloudLayer({
    required this.navigatorKey,
    required this.onShell,
    required this.popupOnTop,
    required this.scrolling,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final bool onShell;
  final bool popupOnTop;
  final bool scrolling;

  @override
  ConsumerState<_ReadAloudLayer> createState() => _ReadAloudLayerState();
}

class _ReadAloudLayerState extends ConsumerState<_ReadAloudLayer> {
  /// El título de lo último que se leyó: el reproductor lo sigue mostrando
  /// mientras se va, aunque el lector ya se haya cerrado.
  String _title = '';

  /// El alto del reproductor abierto (`true`) y achicado (`false`), de la
  /// última vez que se vio cada uno.
  final _heights = <bool, double>{};

  /// La separación del botón redondo con lo que tiene abajo, y del borde
  /// derecho.
  static const _gap = 16.0;

  /// Encima de lo que se le pide esquivar, el botón va un poco más pegado:
  /// como un botón flotante sobre un aviso.
  static const _clearanceGap = 12.0;

  /// El reproductor no pasa de este ancho en una pantalla ancha.
  static const _playerMaxWidth = 640.0;

  static const _move = Duration(milliseconds: 260);

  void _onButton() {
    final document = ref.read(currentReadableProvider);
    if (document == null) return;
    unawaited(ref.read(readAloudControllerProvider.notifier).open(document));
  }

  /// Las hojas del reproductor se abren con el `Navigator` de la app: el
  /// lector está por encima de él.
  BuildContext? get _navigator => widget.navigatorKey.currentContext;

  void _openSheet(Widget sheet) {
    final navigator = _navigator;
    if (navigator != null) unawaited(showReadAloudSheet(navigator, sheet));
  }

  void _openVoices() {
    final navigator = _navigator;
    if (navigator != null) openVoicePicker(navigator);
  }

  /// Desde dónde se para el reproductor: encima de la barra de navegación si
  /// la hay —que ya incluye el borde seguro de abajo—, y de lo que pida
  /// esquivar. Sin nada debajo, desde el borde, con su propio borde seguro.
  double _playerBottom(MediaQueryData media, double? clearance) {
    final wide = media.size.width >= kNavRailBreakpoint;
    final bar = widget.onShell && !wide
        ? (NavigationBarTheme.of(context).height ?? _navigationBarHeight) +
              media.padding.bottom
        : 0.0;
    if (clearance == null) return bar;
    return math.max(bar, media.size.height - clearance);
  }

  /// Desde dónde se para el botón redondo: lo mismo, con su separación.
  double _buttonBottom(MediaQueryData media, double? clearance) {
    final wide = media.size.width >= kNavRailBreakpoint;
    final bar = widget.onShell && !wide
        ? NavigationBarTheme.of(context).height ?? _navigationBarHeight
        : 0.0;
    final base = media.padding.bottom + bar + _gap;
    if (clearance == null) return base;
    return math.max(base, media.size.height - clearance + _clearanceGap);
  }

  /// Publica cuánto ocupa el reproductor, fuera de la construcción.
  void _publishExtent(PlayerExtent extent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _extent.report(extent);
    });
  }

  late final ReadAloudPlayerExtent _extent = ref.read(
    readAloudPlayerExtentProvider.notifier,
  );

  @override
  void dispose() {
    final extent = _extent;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => extent.report(const PlayerExtent()),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (panel, title, reading) = ref.watch(
      readAloudControllerProvider.select(
        (s) => (s.panel, s.document?.title, s.document?.id),
      ),
    );
    final offered = ref.watch(currentReadableProvider.select((d) => d != null));
    final focused = ref.watch(
      narrationSettingsNotifierProvider.select((s) => s.focusedReading),
    );
    if (title != null) _title = title;
    // Lo que suena tiene su propio reproductor en la pantalla que se ve —un
    // visor de extraer de Repasar (F43, paso 7)—: este no lo repite.
    final docked = ref.watch(
      readAloudDockProvider.select((ids) => ids.contains(reading)),
    );

    final media = MediaQuery.of(context);
    final clearance = ref.watch(readAloudClearanceProvider);
    // Mientras se escribe o hay algo abierto encima, el lector se hace a un
    // lado; sigue leyendo igual.
    final aside = media.viewInsets.bottom > 0 || widget.popupOnTop || docked;
    final showButton = !aside && panel == ReadAloudPanel.hidden && offered;
    final showPlayer = !aside && panel != ReadAloudPanel.hidden;
    // La Lectura enfocada achica lo abierto mientras se desplaza, sin
    // cambiar lo que se eligió: al soltar, vuelve como estaba.
    final expanded =
        panel == ReadAloudPanel.expanded && !(focused && widget.scrolling);
    final playerBottom = _playerBottom(media, clearance);
    final height = _heights[expanded] ?? 0;
    final restingHeight = _heights[panel == ReadAloudPanel.expanded] ?? height;
    _publishExtent(
      showPlayer
          ? PlayerExtent(
              current: playerBottom + height,
              resting: playerBottom + restingHeight,
            )
          : const PlayerExtent(),
    );

    return Stack(
      children: [
        AnimatedPositioned(
          duration: _move,
          curve: Curves.easeOutCubic,
          right: media.padding.right + _gap,
          bottom: _buttonBottom(media, clearance),
          child: _Reveal(
            visible: showButton,
            style: _RevealStyle.pop,
            child: ReadAloudButton(onPressed: _onButton),
          ),
        ),
        AnimatedPositioned(
          duration: _move,
          curve: Curves.easeOutCubic,
          left: 0,
          right: 0,
          bottom: playerBottom,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _playerMaxWidth),
              child: _Reveal(
                visible: showPlayer,
                style: _RevealStyle.rise,
                // Parado sobre algo, el borde seguro de abajo ya lo cubre lo
                // que tiene debajo.
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: playerBottom > 0,
                  child: ReadAloudAnchoredPlayer(
                    title: _title,
                    expanded: expanded,
                    onSpeed: () => _openSheet(const ReadAloudSpeedSheet()),
                    onVoice: _openVoices,
                    onQueue: () => _openSheet(const ReadAloudQueueSheet()),
                    onHeight: (height) {
                      if (height != _heights[expanded] && mounted) {
                        setState(() => _heights[expanded] = height);
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _RevealStyle {
  /// Crece desde el centro, como un botón flotante de Material.
  pop,

  /// Sube desde abajo, como el mini reproductor del audio.
  rise,
}

/// Muestra y esconde a [child] con una animación; escondido del todo, ni se
/// construye ni recibe toques.
class _Reveal extends StatefulWidget {
  const _Reveal({
    required this.visible,
    required this.style,
    required this.child,
  });

  final bool visible;
  final _RevealStyle style;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
    value: widget.visible ? 1 : 0,
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(_Reveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      unawaited(widget.visible ? _controller.forward() : _controller.reverse());
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        if (_controller.isDismissed) return const SizedBox.shrink();
        final t = _curve.value;
        final moved = switch (widget.style) {
          _RevealStyle.pop => Transform.scale(
            scale: 0.6 + 0.4 * t,
            child: child,
          ),
          _RevealStyle.rise => FractionalTranslation(
            translation: Offset(0, 0.4 * (1 - t)),
            child: child,
          ),
        };
        return IgnorePointer(
          ignoring: !widget.visible,
          child: Opacity(opacity: t, child: moved),
        );
      },
    );
  }
}
