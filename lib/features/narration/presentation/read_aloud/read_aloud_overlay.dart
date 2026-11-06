import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/navigation/navigation_bar_scope.dart';
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/core/design/widgets/snack_bar_footprint.dart'
    show LiftAboveSnackBar;
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_anchored_player.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_audio_focus.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_dock.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_media_session.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_player.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_queue_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_room.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_speed_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_face.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';

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
/// `currentReadableProvider`— y no se está leyendo nada, encima de la barra
/// de navegación si la hay y de lo que se le pida esquivar —ver
/// `ReadAloudClearance`—. El reproductor queda siempre en el mismo lugar:
/// encima de la barra de navegación cuando la hay, como el de un reproductor
/// de música, y si no, al pie. Los dos se hacen a un lado mientras se
/// escribe —con el teclado abierto— y mientras hay un diálogo o un panel
/// abierto encima, incluidos los suyos.
///
/// **Las pantallas le dejan su lugar** (F46, paso 5g): lo reciben como algo
/// que tapa el pie de la ventana, igual que el teclado —ver
/// `ReadAloudRoom`—, y cada `Scaffold` achica su cuerpo hasta su borde de
/// arriba. Así no tapa el final de una lista, ni el botón flotante, ni lo
/// que se esquivaba —el campo del chat queda arriba de él—, y **los avisos
/// van por encima del reproductor**, abierto o achicado, sin tapar su ✕. El
/// botón redondo, en cambio, flota sobre los avisos: se corre arriba de uno
/// mientras se ve (`LiftAboveSnackBar`, decisión C).
///
/// Con la **Lectura enfocada** (Ajustes), el reproductor abierto se achica
/// solo mientras se desplaza cualquier pantalla, y vuelve al soltar; su
/// lugar no cambia por eso.
///
/// Y mantiene viva **la tarjeta de lo que suena** (F47, paso 2b) —ver
/// `mediaSessionHubProvider`—, con el lector en ella: con la app minimizada o
/// la pantalla apagada, sigue sonando y se maneja desde la notificación.
///
/// En el marco de lectura (F47, paso 1) no va el botón: el marco trae
/// «Escuchar» abajo (`ReadAloudDock`). El reproductor sí, el mismo de toda la
/// app, con su lugar como en cualquier pantalla.
class ReadAloudOverlay extends ConsumerStatefulWidget {
  const ReadAloudOverlay({
    required this.router,
    required this.child,
    super.key,
  });

  /// De dónde sale el `Navigator` para abrir los paneles —el lector está por
  /// encima de él—. Si la pantalla de arriba tiene la barra de navegación no
  /// sale de acá: lo dice la barra misma (`navigationBarShownProvider`, F46,
  /// paso 5g).
  final GoRouter router;

  final Widget child;

  @override
  ConsumerState<ReadAloudOverlay> createState() => _ReadAloudOverlayState();
}

class _ReadAloudOverlayState extends ConsumerState<ReadAloudOverlay> {
  var _popupOnTop = false;
  var _checkScheduled = false;

  /// Si la persona está desplazando una pantalla, para la Lectura enfocada.
  var _scrolling = false;

  /// El alto del reproductor abierto (`true`) y achicado (`false`), sin el
  /// borde seguro de abajo, de la última vez que se vio cada uno.
  final _heights = <bool, double>{};

  /// El lugar que se le deja al reproductor: ver [ReadAloudRoom].
  var _room = 0.0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_scheduleCheck);
    _scheduleCheck();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_scheduleCheck);
    super.dispose();
  }

  /// Vuelve a mirar si hay algo abierto encima al final del cuadro, no en el
  /// momento del aviso: el foco cambia a mitad de una navegación, con la
  /// ruta que lo tenía ya desmontándose. Si hay un diálogo, un panel o un
  /// menú encima, el lector no lo tapa (ver `popupRouteHasFocus`).
  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _checkScheduled = false;
        if (!mounted) return;
        final popup = popupRouteHasFocus();
        if (popup != _popupOnTop) setState(() => _popupOnTop = popup);
      })
      ..ensureVisualUpdate();
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

  void _measured(double height, {required bool expanded}) {
    if (_heights[expanded] != height && mounted) {
      setState(() => _heights[expanded] = height);
    }
  }

  /// El lugar del reproductor: el alto de la forma que se eligió —abierta o
  /// achicada—, no el de cada momento, así la Lectura enfocada no cambia el
  /// alto de lo que se está desplazando. Mientras no se midió esa forma, el
  /// de antes.
  double _roomFor(ReadAloudPanel panel) {
    if (panel == ReadAloudPanel.hidden) return 0;
    return _heights[panel == ReadAloudPanel.expanded] ?? _room;
  }

  /// Tocar la tarjeta de lo que suena lleva a la pantalla que lo ofreció,
  /// si no es la de ahora: encima de la de ahora, como el widget «Seguir
  /// escuchando».
  void _openLocation(String location) {
    if (widget.router.state.uri.toString() == location) return;
    unawaited(widget.router.push<void>(location));
  }

  @override
  Widget build(BuildContext context) {
    // Uno a la vez con el audio: ver `readAloudAudioFocusProvider`.
    ref
      ..watch(readAloudAudioFocusProvider)
      // La tarjeta de lo que suena, en la notificación (F47, paso 2b).
      ..watch(mediaSessionHubProvider);
    // La barra de navegación se ve abajo: lo dice ella (F46, paso 5g). En una
    // pantalla ancha no la hay —va el riel al costado—, y tampoco en una
    // pantalla abierta encima de las pestañas.
    final onShell = ref.watch(navigationBarShownProvider);
    final panel = ref.watch(readAloudControllerProvider.select((s) => s.panel));
    _room = _roomFor(panel);
    final media = MediaQuery.of(context);
    final still = MediaQuery.disableAnimationsOf(context);

    return ReadAloudMediaSession(
      onOpenLocation: _openLocation,
      child: Stack(
        children: [
          // Las pantallas le dejan su lugar al reproductor (F46, paso 5g),
          // con su mismo andar: cambia de alto con `AnimatedSize`
          // (`ReadAloudAnchoredPlayer`). La de las pestañas lo toma de
          // `ReadAloudRoom` —encima de su barra—, aunque haya algo abierto
          // encima: ahí no lo ve nadie más. Las demás, del `MediaQuery` de
          // arriba del `Navigator`, que también ven los diálogos y los
          // paneles: con uno abierto el reproductor se hace a un lado, y su
          // lugar se va con él en el acto —un panel no tiene por qué
          // empezar más alto—.
          _AnimatedRoom(
            room: _room,
            still: still,
            builder: (context, room, child) => _AnimatedRoom(
              room: _popupOnTop ? 0 : _room,
              still: still || _popupOnTop,
              child: child!,
              builder: (context, ownRoom, child) => ReadAloudRoom(
                height: room,
                outer: media,
                child: MediaQuery(
                  data: mediaWithRoomAtBottom(media, ownRoom),
                  child: child!,
                ),
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
                onShell: onShell,
                popupOnTop: _popupOnTop,
                scrolling: _scrolling,
                onHeight: _measured,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadAloudLayer extends ConsumerStatefulWidget {
  const _ReadAloudLayer({
    required this.navigatorKey,
    required this.onShell,
    required this.popupOnTop,
    required this.scrolling,
    required this.onHeight,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final bool onShell;
  final bool popupOnTop;
  final bool scrolling;

  /// El alto del reproductor abierto (`true`) o achicado, cada vez que
  /// cambia.
  final void Function(double height, {required bool expanded}) onHeight;

  @override
  ConsumerState<_ReadAloudLayer> createState() => _ReadAloudLayerState();
}

class _ReadAloudLayerState extends ConsumerState<_ReadAloudLayer> {
  /// El título de lo último que se leyó: el reproductor lo sigue mostrando
  /// mientras se va, aunque el lector ya se haya cerrado.
  String _title = '';

  /// La separación del botón redondo con lo que tiene abajo, y del borde
  /// derecho.
  static const _gap = 16.0;

  /// Encima de lo que se le pide esquivar y de un aviso, el botón va un poco
  /// más pegado: como un botón flotante sobre un aviso.
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
  /// la hay —que ya incluye el borde seguro de abajo—. Sin barra, desde el
  /// borde, con su propio borde seguro. Lo que pide esquivar al botón
  /// redondo, el reproductor no lo esquiva: la pantalla le deja su lugar
  /// debajo (`ReadAloudRoom`), y eso queda arriba de él.
  double _playerBottom(MediaQueryData media) => widget.onShell
      ? navigationBarHeightOf(context) + media.padding.bottom
      : 0.0;

  /// Desde dónde se para el botón redondo: lo mismo, con su separación.
  double _buttonBottom(MediaQueryData media, double? clearance) {
    final bar = widget.onShell ? navigationBarHeightOf(context) : 0.0;
    final base = media.padding.bottom + bar + _gap;
    if (clearance == null) return base;
    return math.max(base, media.size.height - clearance + _clearanceGap);
  }

  @override
  Widget build(BuildContext context) {
    final (panel, title) = ref.watch(
      readAloudControllerProvider.select((s) => (s.panel, s.document?.title)),
    );
    final offered = ref.watch(currentReadableProvider.select((d) => d != null));
    final focused = ref.watch(
      narrationSettingsNotifierProvider.select((s) => s.focusedReading),
    );
    if (title != null) _title = title;
    // La pantalla que se ve es el marco de lectura (F47, paso 1), que trae
    // «Escuchar» abajo: ahí no va el botón flotante.
    final framed = ref.watch(
      readAloudDockProvider.select((owners) => owners.isNotEmpty),
    );

    final media = MediaQuery.of(context);
    final clearance = ref.watch(readAloudClearanceProvider);
    // Mientras se escribe o hay algo abierto encima, el lector se hace a un
    // lado; sigue leyendo igual.
    final aside = media.viewInsets.bottom > 0 || widget.popupOnTop;
    final showButton =
        !aside && !framed && panel == ReadAloudPanel.hidden && offered;
    final showPlayer = !aside && panel != ReadAloudPanel.hidden;
    // La Lectura enfocada achica lo abierto mientras se desplaza, sin
    // cambiar lo que se eligió: al soltar, vuelve como estaba.
    final expanded =
        panel == ReadAloudPanel.expanded && !(focused && widget.scrolling);
    final playerBottom = _playerBottom(media);
    final buttonBottom = _buttonBottom(media, clearance);

    return Stack(
      children: [
        AnimatedPositioned(
          duration: _move,
          curve: Curves.easeOutCubic,
          right: media.padding.right + _gap,
          bottom: buttonBottom,
          child: LiftAboveSnackBar(
            bottom: buttonBottom,
            child: _Reveal(
              visible: showButton,
              style: _RevealStyle.pop,
              child: ReadAloudButton(onPressed: _onButton),
            ),
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
                    onHeight: (height) =>
                        widget.onHeight(height, expanded: expanded),
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

/// Lleva [room] a su nuevo valor con el andar del reproductor —o de una vez,
/// con [still]— y le pasa el de cada cuadro a [builder].
class _AnimatedRoom extends StatefulWidget {
  const _AnimatedRoom({
    required this.room,
    required this.still,
    required this.builder,
    required this.child,
  });

  final double room;
  final bool still;
  final ValueWidgetBuilder<double> builder;
  final Widget child;

  @override
  State<_AnimatedRoom> createState() => _AnimatedRoomState();
}

class _AnimatedRoomState extends State<_AnimatedRoom>
    with SingleTickerProviderStateMixin {
  /// El de `AnimatedSize` en `ReadAloudAnchoredPlayer`.
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late Animation<double> _room = AlwaysStoppedAnimation(widget.room);

  @override
  void didUpdateWidget(_AnimatedRoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.room == oldWidget.room) return;
    if (widget.still) {
      _controller.stop();
      _room = AlwaysStoppedAnimation(widget.room);
      return;
    }
    _room = Tween(begin: _room.value, end: widget.room).animate(_curve);
    unawaited(_controller.forward(from: 0));
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => widget.builder(context, _room.value, child),
  );
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
