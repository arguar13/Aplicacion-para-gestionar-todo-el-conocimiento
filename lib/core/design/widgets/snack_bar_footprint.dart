import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Lo que ocupa abajo el aviso que se ve (F45, paso 1): desde su borde de
/// arriba hasta el borde de abajo de la pantalla, y cuánto de eso está ya a
/// la vista.
///
/// Lo publica el aviso común (`AppSnackBar`) en el anfitrión de la app
/// ([SnackBarFootprintHost]), y lo lee lo que flota abajo para correrse
/// arriba del aviso, como un botón flotante de Android: ver
/// [LiftAboveSnackBar].
@immutable
class SnackBarFootprint {
  const SnackBarFootprint({required this.height, required this.presence});

  /// Desde el borde de arriba del aviso hasta el de abajo de la pantalla, con
  /// el aviso entero.
  final double height;

  /// Cuánto de [height] ocupa el aviso ahora, de 0 —todavía no está, o ya se
  /// fue— a 1 —entero—. Sigue la animación del aviso: sube con él al
  /// aparecer y baja cuando se desvanece; con «sin animaciones» salta de una
  /// punta a la otra.
  final Animation<double> presence;

  @override
  bool operator ==(Object other) =>
      other is SnackBarFootprint &&
      other.height == height &&
      identical(other.presence, presence);

  @override
  int get hashCode => Object.hash(height, presence);
}

/// Las huellas de los avisos que se ven, y la más alta como valor: la que hay
/// que esquivar.
///
/// Un aviso puede verse en dos lugares a la vez —en el `Scaffold` de la
/// pantalla que se va y en el de la que llega, mientras pasa de una a otra—;
/// cada uno publica la suya con su dueño.
class SnackBarFootprints extends ChangeNotifier
    implements ValueListenable<SnackBarFootprint?> {
  final _footprints = <Object, SnackBarFootprint>{};
  SnackBarFootprint? _value;
  var _disposed = false;

  @override
  SnackBarFootprint? get value => _value;

  /// [owner] ocupa [footprint].
  void report(Object owner, SnackBarFootprint footprint) {
    if (_disposed || _footprints[owner] == footprint) return;
    _footprints[owner] = footprint;
    _refresh();
  }

  /// [owner] ya no ocupa nada.
  ///
  /// Un aviso se retira al final del cuadro en que se desmontó, y puede que
  /// el anfitrión se haya ido con él —al cerrarse la app—: entonces no hay a
  /// quién avisar.
  void withdraw(Object owner) {
    if (_disposed) return;
    if (_footprints.remove(owner) != null) _refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _refresh() {
    SnackBarFootprint? tallest;
    for (final footprint in _footprints.values) {
      if (tallest == null || footprint.height > tallest.height) {
        tallest = footprint;
      }
    }
    if (tallest == _value) return;
    _value = tallest;
    notifyListeners();
  }
}

/// El anfitrión de los avisos de la app (F45, paso 1): adonde el aviso común
/// publica lo que ocupa abajo ([SnackBarFootprints]), para que lo que flota
/// encima de las pantallas no lo tape.
///
/// Va en el `builder` de `MaterialApp.router`, por encima del `Navigator`: así
/// abarca a los avisos —que se dibujan en el `Scaffold` de cada pantalla— y a
/// lo que flota por encima de todas, como el lector en voz alta. Sin
/// anfitrión, el aviso no publica nada y nada se corre.
class SnackBarFootprintHost extends StatefulWidget {
  const SnackBarFootprintHost({required this.child, super.key});

  final Widget child;

  /// Las huellas de los avisos, o `null` fuera de un anfitrión.
  static SnackBarFootprints? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SnackBarFootprintScope>()
      ?.footprints;

  @override
  State<SnackBarFootprintHost> createState() => _SnackBarFootprintHostState();
}

class _SnackBarFootprintHostState extends State<SnackBarFootprintHost> {
  final _footprints = SnackBarFootprints();

  @override
  void dispose() {
    _footprints.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SnackBarFootprintScope(footprints: _footprints, child: widget.child);
}

/// Pasa las huellas sin reconstruir a nadie cuando cambian: quien las usa las
/// escucha (ver [LiftAboveSnackBar]).
class _SnackBarFootprintScope extends InheritedWidget {
  const _SnackBarFootprintScope({
    required this.footprints,
    required super.child,
  });

  final SnackBarFootprints footprints;

  @override
  bool updateShouldNotify(_SnackBarFootprintScope oldWidget) =>
      !identical(oldWidget.footprints, footprints);
}

/// Corre a [child] para arriba mientras hay un aviso que lo taparía (F45,
/// paso 1, decisión C): se para a [gap] por encima del aviso, como un botón
/// flotante de Android, y vuelve a su lugar cuando el aviso se va. Sube y
/// baja con la animación del aviso, y sin ella con «sin animaciones» (ver
/// [SnackBarFootprint.presence]).
///
/// [bottom] es dónde está parado [child] sin aviso: cuánto sube desde el
/// borde de abajo de la pantalla. Si ya está por encima del aviso, no se
/// mueve. Corre también lo que se toca, no solo lo que se ve.
class LiftAboveSnackBar extends StatelessWidget {
  const LiftAboveSnackBar({
    required this.bottom,
    required this.child,
    this.gap = 12,
    super.key,
  });

  final double bottom;
  final double gap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final footprints = SnackBarFootprintHost.maybeOf(context);
    if (footprints == null) return child;
    // La misma forma con aviso y sin él: cambiarla perdería el estado de
    // [child], como la animación con que aparece el lector.
    return ValueListenableBuilder<SnackBarFootprint?>(
      valueListenable: footprints,
      child: child,
      builder: (context, footprint, child) {
        final rise = footprint == null ? 0.0 : footprint.height + gap - bottom;
        return AnimatedBuilder(
          animation: footprint?.presence ?? kAlwaysDismissedAnimation,
          child: child,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, rise > 0 ? -rise * footprint!.presence.value : 0),
            child: child,
          ),
        );
      },
    );
  }
}
