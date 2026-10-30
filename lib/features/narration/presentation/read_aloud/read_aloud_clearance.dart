import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/top_edge_probe.dart';

/// Lo que el lector flotante tiene que esquivar abajo (F25): el mini
/// reproductor del audio, la caja para escribir del chat... Cada uno avisa
/// dónde empieza —su borde de arriba, en la pantalla— y el botón redondo y
/// el reproductor de lectura se paran encima del más alto, como un botón
/// flotante sobre un aviso.
///
/// El estado es ese borde, o `null` si no hay nada que esquivar.
class ReadAloudClearances extends Notifier<double?> {
  final _tops = <Object, double>{};

  @override
  double? build() => null;

  /// [owner] ocupa la pantalla desde [top] para abajo.
  void report(Object owner, double top) {
    if (_tops[owner] == top) return;
    _tops[owner] = top;
    _refresh();
  }

  /// [owner] ya no ocupa nada.
  void withdraw(Object owner) {
    if (_tops.remove(owner) != null) _refresh();
  }

  void _refresh() {
    double? highest;
    for (final top in _tops.values) {
      if (highest == null || top < highest) highest = top;
    }
    state = highest;
  }
}

final readAloudClearanceProvider =
    NotifierProvider<ReadAloudClearances, double?>(ReadAloudClearances.new);

/// Marca a [child] como algo que el lector flotante no tapa (F25): ver
/// [ReadAloudClearances].
///
/// Como `ReadableRegion`, solo cuenta mientras se ve —una pestaña que no es
/// la de ahora o una pantalla tapada no corren al botón— y mientras
/// [enabled]: el mini reproductor del audio lo apaga cuando se esconde.
///
/// Mide en el dibujo, no en la construcción: la caja del chat sube con el
/// teclado sin reconstruirse, pero sí se vuelve a dibujar.
class ReadAloudClearance extends ConsumerStatefulWidget {
  const ReadAloudClearance({
    required this.child,
    this.enabled = true,
    super.key,
  });

  final bool enabled;
  final Widget child;

  @override
  ConsumerState<ReadAloudClearance> createState() => _ReadAloudClearanceState();
}

class _ReadAloudClearanceState extends ConsumerState<ReadAloudClearance> {
  late final ReadAloudClearances _clearances = ref.read(
    readAloudClearanceProvider.notifier,
  );
  var _active = false;
  double? _top;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ReadAloudClearance oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    _active = widget.enabled && TickerMode.valuesOf(context).enabled;
    _publish();
  }

  void _measured(double top) {
    _top = top;
    _publish();
  }

  /// Fuera del dibujo y de la construcción: cambiar un provider en medio de
  /// un cuadro no está permitido. La medida puede llegar ya al final del
  /// cuadro (ver `TopEdgeProbe`): entonces va en el que sigue, que se pide.
  void _publish() {
    SchedulerBinding.instance.ensureVisualUpdate();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final top = _top;
      if (_active && top != null) {
        _clearances.report(this, top);
      } else {
        _clearances.withdraw(this);
      }
    });
  }

  @override
  void dispose() {
    final clearances = _clearances;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => clearances.withdraw(this),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TopEdgeProbe(onTop: _measured, child: widget.child);
}
