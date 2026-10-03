import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/explorer/presentation/providers/explorer_providers.dart';

/// Pone el Explorador a mirar un valor de una propiedad cuando se llega con
/// `?value=` (F13), o un tema cuando se llega con `?space=` (F28): lo que
/// abren el Atlas y el Mapa desde una rama, un vacío o un tema.
///
/// Envuelve a la pantalla en vez de tocarla: el Explorador es un destino del
/// shell que sigue vivo mientras se cambia de pestaña, así que llegar con otro
/// valor NO crea una pantalla nueva sino que cambia lo que la de siempre
/// mira —de ahí `didUpdateWidget`—. Sin ninguno de los dos, no hace nada.
class ExplorerFocus extends ConsumerStatefulWidget {
  const ExplorerFocus({
    required this.valueId,
    required this.child,
    this.spaceId,
    super.key,
  });

  /// El valor por el que filtrar, o `null` si se llegó sin uno.
  final String? valueId;

  /// El tema en el que pararse, o `null` si se llegó sin uno.
  final String? spaceId;

  final Widget child;

  @override
  ConsumerState<ExplorerFocus> createState() => _ExplorerFocusState();
}

class _ExplorerFocusState extends ConsumerState<ExplorerFocus> {
  /// Si el filtro pedido ya se aplicó. Sin ninguno, siempre.
  late bool _applied = widget.valueId == null && widget.spaceId == null;

  @override
  void initState() {
    super.initState();
    // El filtro vive en un proveedor que se descarta si nadie lo mira, y hasta
    // que se aplique no hay pantalla que lo mire: este oyente lo mantiene.
    ref.listenManual(explorerQueryNotifierProvider, (_, _) {});
    _applyIfAsked(null);
  }

  @override
  void didUpdateWidget(ExplorerFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyIfAsked(oldWidget);
  }

  /// Aplica lo que se pidió si es nuevo respecto de [old].
  void _applyIfAsked(ExplorerFocus? old) {
    final valueId = widget.valueId;
    final spaceId = widget.spaceId;
    if (valueId != null && valueId != old?.valueId) {
      _apply((explorer) => explorer.focusOnValue(valueId));
    } else if (spaceId != null && spaceId != old?.spaceId) {
      _apply((explorer) => explorer.focusOnSpace(spaceId));
    }
  }

  /// Un proveedor no se modifica mientras se arma el árbol: se aplica apenas
  /// termina.
  void _apply(void Function(ExplorerQueryNotifier explorer) focus) {
    scheduleMicrotask(() {
      if (!mounted) return;
      focus(ref.read(explorerQueryNotifierProvider.notifier));
      if (!_applied) setState(() => _applied = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Hasta que se aplique el filtro, sin la pantalla: sin él serían todos los
    // elementos de la bóveda, para descartarlos enseguida.
    if (!_applied) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return widget.child;
  }
}
