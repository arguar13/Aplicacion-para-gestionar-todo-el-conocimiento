import 'package:flutter/material.dart';

/// El campo con que se busca en una lista —la Biblioteca, el Índice, el Atlas,
/// la Ayuda, las conversaciones del chat…— y que **suelta el teclado cuando
/// ya no se escribe** (F46, paso 5i).
///
/// Existe porque en el emulador, buscando en la Biblioteca, se cerraba el
/// teclado con «atrás», se tocaba un resultado y, al volver, el campo volvía a
/// tomar el foco y el teclado aparecía solo, tapando la mitad de los
/// resultados: cerrar el teclado no le saca el foco al campo, y la ruta de
/// abajo, al volver a ser la de arriba, le devuelve el foco a lo último que lo
/// tuvo. La regla vive acá, una vez, para todos los buscadores:
///
/// - **al buscar** (la tecla de buscar del teclado) suelta el foco —lo hace
///   el campo mismo con `TextInputAction.search`—;
/// - **al tocar fuera** —un resultado, la lista, un filtro— lo suelta;
/// - **al abrir algo encima** —otra pantalla, una hoja, un diálogo, también
///   sin tocar la pantalla: con el lector de pantalla o por código—, al
///   volver no lo recupera: sigue sin foco hasta que la persona lo toque.
///
/// Lo último se resuelve sin tocar el foco de la otra ruta: mientras el campo
/// está tapado no puede tomar el foco, y cuando lo de abajo vuelve, su ruta lo
/// descarta —una ruta que vuelve no le devuelve el foco a quien no puede
/// tomarlo— y el campo vuelve a poder tomarlo, para cuando se lo toque.
class SearchField extends StatefulWidget {
  const SearchField({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.decoration = const InputDecoration(),
    super.key,
  });

  final TextEditingController? controller;

  /// El foco del campo, para quien lo pide desde afuera —el Índice lo enfoca
  /// al abrirse—. Sin él, el campo tiene el suyo.
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final InputDecoration decoration;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  FocusNode? _ownNode;

  /// El ámbito de foco de la ruta del campo mientras algo lo tapa: avisa
  /// cuando vuelve a tener el foco.
  FocusScopeNode? _coveredScope;

  /// Si algo se llevó el foco a otra ruta sin que el campo lo soltara: hasta
  /// que vuelva, el campo no puede tomar el foco.
  var _covered = false;

  FocusNode get _node =>
      widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'SearchField'));

  @override
  void initState() {
    super.initState();
    _node.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    (oldWidget.focusNode ?? _ownNode)?.removeListener(_focusChanged);
    _node.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _node.removeListener(_focusChanged);
    _coveredScope?.removeListener(_scopeChanged);
    _ownNode?.dispose();
    super.dispose();
  }

  /// El campo perdió el foco sin soltarlo —su ruta todavía lo recuerda para
  /// devolvérselo—: algo se abrió encima. Soltarlo con `unfocus` ya no se
  /// puede —le sacaría el foco a lo que se abrió—, así que el campo deja de
  /// poder tomarlo hasta que su ruta vuelva a tenerlo.
  void _focusChanged() {
    if (_node.hasFocus || _covered) return;
    final scope = _node.enclosingScope;
    if (scope == null || scope.focusedChild != _node) return;
    _coveredScope = scope..addListener(_scopeChanged);
    setState(() => _covered = true);
  }

  /// Lo de abajo volvió: su ruta ya descartó al campo, que no podía tomar el
  /// foco, y el foco quedó en ella. El campo vuelve a poder tomarlo.
  void _scopeChanged() {
    final scope = _coveredScope;
    if (scope == null || !scope.hasFocus) return;
    scope.removeListener(_scopeChanged);
    _coveredScope = null;
    if (mounted) setState(() => _covered = false);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    focusNode: _node,
    canRequestFocus: !_covered,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    textInputAction: TextInputAction.search,
    onTapOutside: (_) => _node.unfocus(),
    decoration: widget.decoration,
  );
}
