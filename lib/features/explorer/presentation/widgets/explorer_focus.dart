import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/explorer/presentation/providers/explorer_providers.dart';

/// Pone el Explorador a mirar un valor de una propiedad cuando se llega con
/// `?value=` (F13): lo que abre el Atlas desde una rama o un vacío.
///
/// Envuelve a la pantalla en vez de tocarla: el Explorador es un destino del
/// shell que sigue vivo mientras se cambia de pestaña, así que llegar con otro
/// valor NO crea una pantalla nueva sino que cambia lo que la de siempre
/// mira —de ahí `didUpdateWidget`—. Sin valor, no hace nada.
class ExplorerFocus extends ConsumerStatefulWidget {
  const ExplorerFocus({required this.valueId, required this.child, super.key});

  /// El valor por el que filtrar, o `null` si se llegó sin uno.
  final String? valueId;

  final Widget child;

  @override
  ConsumerState<ExplorerFocus> createState() => _ExplorerFocusState();
}

class _ExplorerFocusState extends ConsumerState<ExplorerFocus> {
  /// Si el filtro de este valor ya se aplicó. Sin valor, siempre.
  late bool _applied = widget.valueId == null;

  @override
  void initState() {
    super.initState();
    // El filtro vive en un proveedor que se descarta si nadie lo mira, y hasta
    // que se aplique no hay pantalla que lo mire: este oyente lo mantiene.
    ref.listenManual(explorerQueryNotifierProvider, (_, _) {});
    final valueId = widget.valueId;
    if (valueId != null) _apply(valueId);
  }

  @override
  void didUpdateWidget(ExplorerFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    final valueId = widget.valueId;
    if (valueId != null && valueId != oldWidget.valueId) _apply(valueId);
  }

  /// Un proveedor no se modifica mientras se arma el árbol: se aplica apenas
  /// termina.
  void _apply(String valueId) {
    scheduleMicrotask(() {
      if (!mounted) return;
      ref.read(explorerQueryNotifierProvider.notifier).focusOnValue(valueId);
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
