import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_room.dart';

/// El alto de `NavigationBar` sin el borde seguro de abajo: el del tema, o el
/// de Material 3 si el tema no pone otro.
double navigationBarHeightOf(BuildContext context) =>
    NavigationBarTheme.of(context).height ?? 80;

/// **Si la barra de navegación se ve abajo** (F46, paso 5g): lo dice la barra
/// misma —ver [NavigationBarScope]—, no la configuración del router.
///
/// `go_router` no se entera de una pantalla abierta con
/// `Navigator.of(context, rootNavigator: true).push(...)`: con solo mirar sus
/// rutas, «Clonación de voz» parecía una pestaña, y el reproductor de lectura
/// quedaba a la altura de una barra que no estaba, tapando el pie de la
/// pantalla.
///
/// El estado es si alguna la muestra; cada una avisa con su dueño.
class NavigationBarShown extends Notifier<bool> {
  final _shown = <Object>{};

  @override
  bool build() => false;

  /// La barra de [owner] se ve abajo ([shown]) o no.
  void report(Object owner, {required bool shown}) {
    final changed = shown ? _shown.add(owner) : _shown.remove(owner);
    if (changed) state = _shown.isNotEmpty;
  }

  /// La barra de [owner] ya no está.
  void withdraw(Object owner) => report(owner, shown: false);
}

final navigationBarShownProvider = NotifierProvider<NavigationBarShown, bool>(
  NavigationBarShown.new,
);

/// Si hay un diálogo, un panel de abajo o un menú abierto encima: se llevan
/// el foco al abrirse —y lo devuelven al cerrarse—, así que lo que tiene el
/// foco vive en una ruta emergente.
bool popupRouteHasFocus() {
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused != null &&
      focused.mounted &&
      ModalRoute.of(focused) is PopupRoute;
}

/// Envuelve a la pantalla que tiene la barra de navegación abajo —el
/// `Scaffold` de las pestañas, `AdaptiveScaffold`— y avisa en
/// [navigationBarShownProvider] mientras esa barra se ve (F46, paso 5g).
///
/// Y le deja al reproductor de lectura su lugar **encima de la barra**
/// (`mediaWithRoomAboveBar`): el `Scaffold` achica su cuerpo —las pestañas—
/// hasta el borde de arriba del reproductor, y la barra queda donde está,
/// debajo de él. El lugar lo toma de `ReadAloudRoom`, no del `MediaQuery` de
/// arriba —el de una pantalla sin barra, con el reproductor al pie—: así no
/// cambia mientras se abre o se cierra otra pantalla encima de las pestañas.
/// Sigue al reproductor que se ve (F46, paso 5i): con un diálogo, un panel o
/// un menú abierto el reproductor se hace a un lado y el lugar se va con él,
/// se abra donde se abra —en el navegador de la raíz o en el de una pestaña,
/// adentro de este cuerpo, que si no terminaba a la altura de un reproductor
/// que ya no estaba—.
///
/// Se ve mientras su ruta es la de arriba, o mientras lo de arriba es un
/// diálogo, un panel de abajo o un menú, que la dejan ver. La tapa cualquier
/// pantalla abierta encima, la abra `go_router` o un `Navigator.push`, también
/// a pantalla completa (`fullscreenDialog`): se entera en el momento en que
/// se abre, y vuelve a verse apenas se empieza a cerrar. Una pantalla abierta
/// dentro de una pestaña, en el navegador de la rama, no la tapa: la barra
/// sigue abajo.
///
/// Un diálogo o un panel se llevan el foco al abrirse (ver
/// [popupRouteHasFocus]): así se sabe que lo de arriba es eso y no otra
/// pantalla. Y si su ruta quedó tapada del todo —fuera de escena, como
/// debajo de una pantalla ya abierta—, no se ve aunque arriba haya un
/// diálogo.
class NavigationBarScope extends ConsumerStatefulWidget {
  const NavigationBarScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NavigationBarScope> createState() => _NavigationBarScopeState();
}

class _NavigationBarScopeState extends ConsumerState<NavigationBarScope> {
  late final NavigationBarShown _presence = ref.read(
    navigationBarShownProvider.notifier,
  );
  var _scheduled = false;

  /// La ruta en que está la barra, y si está en escena.
  ModalRoute<Object?>? _route;
  var _onstage = true;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_schedule);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Los dos avisan cuando cambian: si la ruta es la de arriba, y si está en
    // escena.
    _route = ModalRoute.of(context);
    _onstage = TickerMode.valuesOf(context).enabled;
    _schedule();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_schedule);
    final presence = _presence;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => presence.withdraw(this),
    );
    super.dispose();
  }

  /// Al final del cuadro, fuera de la construcción: cambiar un provider en
  /// medio de ella no está permitido, y el foco cambia a mitad de una
  /// navegación.
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) _presence.report(this, shown: _shown());
      })
      ..ensureVisualUpdate();
  }

  bool _shown() {
    if (!_onstage) return false;
    final route = _route;
    return route == null || route.isCurrent || popupRouteHasFocus();
  }

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: mediaWithRoomAboveBar(
      ReadAloudRoom.outerOf(context),
      ReadAloudRoom.heightOf(context),
      barHeight: navigationBarHeightOf(context),
    ),
    child: widget.child,
  );
}
