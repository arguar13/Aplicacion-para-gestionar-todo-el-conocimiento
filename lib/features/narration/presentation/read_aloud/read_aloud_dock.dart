import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Las pantallas que traen **su propio lugar para el reproductor** en lo que
/// se ve ahora: el marco de lectura (F47, paso 1, `ReadingFrame`), en el
/// original, el texto extraído, el resumen, la síntesis y lo creado. En su
/// borde de abajo, el marco lleva «Escuchar» si no suena nada, y si suena,
/// le deja su lugar al reproductor anclado de toda la app (F47, paso 2).
/// Mientras se ve, el botón redondo del lector flotante no se dibuja: el
/// marco no lo lleva. El reproductor anclado sí: es uno solo en toda la app.
///
/// Antes (F43, paso 7) eran los ids de los documentos que tenían su propio
/// reproductor —los visores de extraer de Repasar—, y el flotante se apartaba
/// entero. Con el reproductor anclado, ninguna pantalla trae otro: alcanza
/// con saber si hay un marco a la vista. El estado son sus dueños.
class ReadAloudDocks extends Notifier<Set<Object>> {
  @override
  Set<Object> build() => const {};

  /// [owner] trae su lugar para el reproductor.
  void dock(Object owner) {
    if (state.contains(owner)) return;
    state = Set.unmodifiable({...state, owner});
  }

  /// [owner] ya no se ve.
  void undock(Object owner) {
    if (!state.contains(owner)) return;
    state = Set.unmodifiable({...state}..remove(owner));
  }
}

/// Quiénes traen su lugar para el reproductor; con alguno, el botón redondo
/// del lector flotante no se dibuja.
final readAloudDockProvider = NotifierProvider<ReadAloudDocks, Set<Object>>(
  ReadAloudDocks.new,
);

/// Declara que [child] trae su propio lugar para el reproductor (ver
/// [ReadAloudDocks]).
///
/// Como `ReadableRegion`, solo cuenta mientras se ve: una pantalla tapada por
/// otra —`TickerMode` apagado— deja de contar, y el botón redondo vuelve en
/// las demás.
class ReadAloudDock extends ConsumerStatefulWidget {
  const ReadAloudDock({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ReadAloudDock> createState() => _ReadAloudDockState();
}

class _ReadAloudDockState extends ConsumerState<ReadAloudDock> {
  late final ReadAloudDocks _docks = ref.read(readAloudDockProvider.notifier);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ReadAloudDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final visible = TickerMode.valuesOf(context).enabled;
    // Fuera de la construcción: cambiar un provider mientras se construye
    // otro widget no está permitido.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (visible) {
        _docks.dock(this);
      } else {
        _docks.undock(this);
      }
    });
  }

  @override
  void dispose() {
    final docks = _docks;
    WidgetsBinding.instance.addPostFrameCallback((_) => docks.undock(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
