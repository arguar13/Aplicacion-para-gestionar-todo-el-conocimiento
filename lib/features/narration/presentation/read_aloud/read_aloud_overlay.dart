import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/navigation/adaptive_scaffold.dart'
    show kNavRailBreakpoint;
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_audio_focus.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_player.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_speed_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';

/// El lector flotante de toda la app (F25): el botón redondo abajo a la
/// derecha y el mini reproductor de lectura, por encima de cualquier
/// pantalla.
///
/// Va en el `builder` de `MaterialApp.router`, envolviendo a [child] —el
/// `Navigator` del router—: así sigue en pantalla, y leyendo, aunque se
/// cambie de pestaña o se abra una pantalla encima. Lo que no es el botón ni
/// el reproductor deja pasar los toques a la pantalla de abajo.
///
/// El botón aparece solo donde hay algo que leer —ver
/// `currentReadableProvider`— o mientras se lee. Se para encima de la barra
/// de navegación cuando la hay, y encima de lo que se le pida esquivar —ver
/// `ReadAloudClearance`—. Se hace a un lado mientras se escribe —con el
/// teclado abierto— y mientras hay un diálogo o un panel abierto encima,
/// incluidos los suyos de velocidad y de voz.
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

  @override
  Widget build(BuildContext context) {
    // Uno a la vez con el audio: ver `readAloudAudioFocusProvider`.
    ref.watch(readAloudAudioFocusProvider);

    return Stack(
      children: [
        widget.child,
        // Un `Overlay` propio: por encima del `Navigator` no hay ninguno, y
        // los tooltips de los botones lo necesitan.
        Positioned.fill(
          child: Overlay.wrap(
            child: _ReadAloudLayer(
              navigatorKey: widget.router.routerDelegate.navigatorKey,
              onShell: _onShell,
              popupOnTop: _popupOnTop,
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
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final bool onShell;
  final bool popupOnTop;

  @override
  ConsumerState<_ReadAloudLayer> createState() => _ReadAloudLayerState();
}

class _ReadAloudLayerState extends ConsumerState<_ReadAloudLayer> {
  /// El título de lo último que se leyó: el reproductor lo sigue mostrando
  /// mientras se va, aunque el lector ya se haya cerrado.
  String _title = '';

  /// La separación entre el lector y lo que tiene abajo, y del borde
  /// derecho.
  static const _gap = 16.0;

  /// Encima de lo que se le pide esquivar, un poco más pegado: como un
  /// botón flotante sobre un aviso.
  static const _clearanceGap = 12.0;

  /// El reproductor no pasa de este ancho, como el mini reproductor del
  /// audio.
  static const _playerMaxWidth = 560.0;

  static const _move = Duration(milliseconds: 260);

  void _onButton() {
    final controller = ref.read(readAloudControllerProvider.notifier);
    if (ref.read(readAloudControllerProvider).panel != ReadAloudPanel.hidden) {
      controller.expand();
      return;
    }
    final document = ref.read(currentReadableProvider);
    if (document != null) unawaited(controller.open(document));
  }

  void _openSheet(Widget sheet) {
    final navigator = widget.navigatorKey.currentContext;
    if (navigator == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: navigator,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => sheet,
      ),
    );
  }

  /// Cuánto sube el lector desde el borde de abajo: por encima de la barra
  /// de navegación si la hay, y de lo que pida esquivar.
  double _bottom(MediaQueryData media) {
    final wide = media.size.width >= kNavRailBreakpoint;
    // La barra mide lo suyo más el borde seguro de abajo, que la incluye.
    final bar = widget.onShell && !wide
        ? NavigationBarTheme.of(context).height ?? 80
        : 0.0;
    final base = media.padding.bottom + bar + _gap;
    final clearance = ref.watch(readAloudClearanceProvider);
    if (clearance == null) return base;
    return math.max(base, media.size.height - clearance + _clearanceGap);
  }

  @override
  Widget build(BuildContext context) {
    final (panel, playing, title) = ref.watch(
      readAloudControllerProvider.select(
        (s) => (s.panel, s.playing, s.document?.title),
      ),
    );
    final offered = ref.watch(currentReadableProvider.select((d) => d != null));
    if (title != null) _title = title;

    final media = MediaQuery.of(context);
    // Mientras se escribe o hay algo abierto encima, el lector se hace a un
    // lado; sigue leyendo igual.
    final aside = media.viewInsets.bottom > 0 || widget.popupOnTop;
    final showButton =
        !aside &&
        switch (panel) {
          ReadAloudPanel.hidden => offered,
          ReadAloudPanel.minimized => true,
          ReadAloudPanel.expanded => false,
        };
    final showPlayer = !aside && panel == ReadAloudPanel.expanded;
    final bottom = _bottom(media);

    return Stack(
      children: [
        AnimatedPositioned(
          duration: _move,
          curve: Curves.easeOutCubic,
          right: media.padding.right + _gap,
          bottom: bottom,
          child: _Reveal(
            visible: showButton,
            style: _RevealStyle.pop,
            child: ReadAloudButton(
              reading: panel != ReadAloudPanel.hidden,
              playing: playing,
              onPressed: _onButton,
            ),
          ),
        ),
        AnimatedPositioned(
          duration: _move,
          curve: Curves.easeOutCubic,
          left: media.padding.left + _gap,
          right: media.padding.right + _gap,
          bottom: bottom,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _playerMaxWidth),
              child: _Reveal(
                visible: showPlayer,
                style: _RevealStyle.rise,
                child: ReadAloudPlayer(
                  title: _title,
                  onSpeed: () => _openSheet(const ReadAloudSpeedSheet()),
                  onVoice: () => _openSheet(const ReadAloudVoiceSheet()),
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
