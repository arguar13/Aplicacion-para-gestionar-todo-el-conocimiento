import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Los documentos que tienen su propio reproductor en lo que se ve ahora
/// (F43, paso 7): los visores de extraer de Repasar dibujan el lector en voz
/// alta grande, abajo de la pantalla, con su piel propia. Mientras se lee uno
/// de estos, el lector flotante de toda la app —el botón redondo y el mini
/// reproductor— se hace a un lado: serían dos reproductores de lo mismo.
///
/// Es el mismo motor, no otro: lo que se lee, el amarillo y la posición son
/// los de `readAloudControllerProvider`. Al salir de la pantalla, el lector
/// flotante vuelve a aparecer con la lectura donde iba.
///
/// El estado son los ids de esos documentos (`ReadableDocument.id`).
class ReadAloudDocks extends Notifier<Set<String>> {
  final _owners = <Object, String>{};

  @override
  Set<String> build() => const {};

  /// [owner] muestra el reproductor de [documentId].
  void dock(Object owner, String documentId) {
    if (_owners[owner] == documentId) return;
    _owners[owner] = documentId;
    state = Set.unmodifiable(_owners.values.toSet());
  }

  /// [owner] ya no muestra ninguno.
  void undock(Object owner) {
    if (_owners.remove(owner) == null) return;
    state = Set.unmodifiable(_owners.values.toSet());
  }
}

final readAloudDockProvider = NotifierProvider<ReadAloudDocks, Set<String>>(
  ReadAloudDocks.new,
);

/// Declara que [child] trae su propio reproductor para el documento
/// [documentId] (ver [ReadAloudDocks]).
///
/// Como `ReadableRegion`, solo cuenta mientras se ve: una pantalla tapada por
/// otra —`TickerMode` apagado— deja de contar, y el lector flotante vuelve a
/// mostrar la lectura en las demás.
class ReadAloudDock extends ConsumerStatefulWidget {
  const ReadAloudDock({
    required this.documentId,
    required this.child,
    super.key,
  });

  final String documentId;
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
    final documentId = widget.documentId;
    // Fuera de la construcción: cambiar un provider mientras se construye
    // otro widget no está permitido.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (visible) {
        _docks.dock(this, documentId);
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
