import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';

/// Qué texto se puede leer en voz alta en lo que se ve ahora (F25): las
/// pantallas con texto lo declaran —ver [ReadableRegion]— y el botón
/// flotante aparece mientras haya alguno.
///
/// Una pila: la pantalla de más arriba —la última que se declaró— es la que
/// se ve. Una pantalla que queda tapada, o una pestaña que no es la de
/// ahora, retira lo suyo mientras no se ve.
class ReadableRegistry extends Notifier<List<ReadableDocument>> {
  final _owners = <Object>[];

  @override
  List<ReadableDocument> build() => const [];

  /// [owner] ofrece [document]. Volver a ofrecerlo lo actualiza en su lugar.
  void offer(Object owner, ReadableDocument document) {
    final index = _owners.indexOf(owner);
    final next = [...state];
    if (index < 0) {
      _owners.add(owner);
      next.add(document);
    } else {
      if (next[index] == document) return;
      next[index] = document;
    }
    state = next;
  }

  /// [owner] ya no ofrece nada.
  void withdraw(Object owner) {
    final index = _owners.indexOf(owner);
    if (index < 0) return;
    _owners.removeAt(index);
    state = [...state]..removeAt(index);
  }
}

final readableRegistryProvider =
    NotifierProvider<ReadableRegistry, List<ReadableDocument>>(
      ReadableRegistry.new,
    );

/// El texto de la pantalla que se ve, o `null` si no hay ninguno: lo que lee
/// el botón flotante.
final currentReadableProvider = Provider<ReadableDocument?>((ref) {
  final offered = ref.watch(readableRegistryProvider);
  for (final document in offered.reversed) {
    if (!document.isEmpty) return document;
  }
  return null;
});

/// Declara que [child] muestra [document], para leerlo en voz alta (F25).
///
/// Lo ofrece solo mientras se ve: una pestaña que no es la de ahora o una
/// pantalla tapada por otra quedan fuera de escena —`TickerMode` apagado—, y
/// retiran lo suyo hasta volver a verse. Con [document] `null` o vacío no
/// ofrece nada.
class ReadableRegion extends ConsumerStatefulWidget {
  const ReadableRegion({
    required this.document,
    required this.child,
    super.key,
  });

  final ReadableDocument? document;
  final Widget child;

  @override
  ConsumerState<ReadableRegion> createState() => _ReadableRegionState();
}

class _ReadableRegionState extends ConsumerState<ReadableRegion> {
  late final ReadableRegistry _registry = ref.read(
    readableRegistryProvider.notifier,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ReadableRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final document = widget.document;
    final visible = TickerMode.valuesOf(context).enabled;
    // Fuera de la construcción: cambiar un provider mientras se construye
    // otro widget no está permitido.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (visible && document != null && !document.isEmpty) {
        _registry.offer(this, document);
      } else {
        _registry.withdraw(this);
      }
    });
  }

  @override
  void dispose() {
    final registry = _registry;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => registry.withdraw(this),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
