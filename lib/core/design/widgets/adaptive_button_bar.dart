import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Los botones de un aviso o de una tarjeta —«Marcar con IA» y «Abrir el
/// documento», por ejemplo—: **en un renglón si entran, y si no, uno debajo
/// del otro, todos del ancho entero** (F46, paso 5c).
///
/// Existe porque un `Wrap` los dejaba mal cuando no entraban: cada uno con su
/// propio ancho, pegados a la izquierda y con un hueco grande a la derecha, y
/// en un renglón a veces dos y a veces uno según el largo de cada texto. Acá
/// la decisión es una sola para todos: si la suma de sus anchos naturales y
/// los espacios entra en el ancho que hay, van juntos en ese orden, con
/// [spacing] entre ellos y centrados en alto; si no, van apilados con
/// [runSpacing], estirados al mismo ancho —el de la tarjeta—, en el mismo
/// orden. Con la letra grande o en un teléfono angosto, se apilan; en una
/// pantalla ancha, van juntos.
///
/// Un renglón respeta la dirección del texto: de derecha a izquierda, el
/// primero queda a la derecha.
class AdaptiveButtonBar extends MultiChildRenderObjectWidget {
  const AdaptiveButtonBar({
    required super.children,
    this.spacing = 8,
    this.runSpacing = 8,
    super.key,
  });

  /// El espacio entre dos botones del mismo renglón.
  final double spacing;

  /// El espacio entre dos botones apilados.
  final double runSpacing;

  @override
  RenderAdaptiveButtonBar createRenderObject(BuildContext context) =>
      RenderAdaptiveButtonBar(
        spacing: spacing,
        runSpacing: runSpacing,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAdaptiveButtonBar renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..textDirection = Directionality.of(context);
  }
}

class _BarParentData extends ContainerBoxParentData<RenderBox> {}

/// Lo que dibuja [AdaptiveButtonBar].
class RenderAdaptiveButtonBar extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BarParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BarParentData> {
  RenderAdaptiveButtonBar({
    required double spacing,
    required double runSpacing,
    required TextDirection textDirection,
  }) : _spacing = spacing,
       _runSpacing = runSpacing,
       _textDirection = textDirection;

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  double get runSpacing => _runSpacing;
  set runSpacing(double value) {
    if (value == _runSpacing) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// Si quedaron apilados en el último acomodo: para las pruebas.
  bool get stacked => _stacked;
  var _stacked = false;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BarParentData) {
      child.parentData = _BarParentData();
    }
  }

  List<RenderBox> get _children {
    final children = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      children.add(child);
      child = childAfter(child);
    }
    return children;
  }

  /// Lo que ocupan todos juntos en un renglón, con su ancho natural.
  double _rowWidth(List<RenderBox> children) {
    if (children.isEmpty) return 0;
    var width = spacing * (children.length - 1);
    for (final child in children) {
      width += child.getMaxIntrinsicWidth(double.infinity);
    }
    return width;
  }

  bool _fits(List<RenderBox> children, double maxWidth) =>
      !maxWidth.isFinite || _rowWidth(children) <= maxWidth;

  @override
  double computeMinIntrinsicWidth(double height) {
    var width = 0.0;
    for (final child in _children) {
      width = math.max(width, child.getMinIntrinsicWidth(height));
    }
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) => _rowWidth(_children);

  @override
  double computeMinIntrinsicHeight(double width) => _heightFor(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _heightFor(width);

  double _heightFor(double width) {
    final children = _children;
    if (children.isEmpty) return 0;
    if (_fits(children, width)) {
      var height = 0.0;
      for (final child in children) {
        height = math.max(
          height,
          child.getMaxIntrinsicHeight(
            child.getMaxIntrinsicWidth(double.infinity),
          ),
        );
      }
      return height;
    }
    var height = runSpacing * (children.length - 1);
    for (final child in children) {
      height += child.getMaxIntrinsicHeight(width);
    }
    return height;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  @override
  void performLayout() {
    size = _layout(constraints, dry: false);
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final children = _children;
    if (children.isEmpty) return constraints.smallest;
    final maxWidth = constraints.maxWidth;
    final fits = _fits(children, maxWidth);
    if (!dry) _stacked = !fits;

    Size measure(RenderBox child, BoxConstraints given) {
      if (dry) return child.getDryLayout(given);
      child.layout(given, parentUsesSize: true);
      return child.size;
    }

    if (fits) {
      final sizes = [
        for (final child in children)
          measure(
            child,
            BoxConstraints(
              maxWidth: math.min(
                child.getMaxIntrinsicWidth(double.infinity),
                maxWidth,
              ),
            ),
          ),
      ];
      final height = sizes.fold<double>(
        0,
        (high, s) => math.max(high, s.height),
      );
      final width = maxWidth.isFinite ? maxWidth : _rowWidth(children);
      var used = 0.0;
      for (var i = 0; i < children.length; i++) {
        if (!dry) {
          final x = textDirection == TextDirection.rtl
              ? width - used - sizes[i].width
              : used;
          (children[i].parentData! as _BarParentData).offset = Offset(
            x,
            (height - sizes[i].height) / 2,
          );
        }
        used += sizes[i].width + spacing;
      }
      return constraints.constrain(Size(width, height));
    }

    var top = 0.0;
    for (var i = 0; i < children.length; i++) {
      final childSize = measure(
        children[i],
        BoxConstraints.tightFor(width: maxWidth),
      );
      if (!dry) {
        (children[i].parentData! as _BarParentData).offset = Offset(0, top);
      }
      top += childSize.height + (i < children.length - 1 ? runSpacing : 0);
    }
    return constraints.constrain(Size(maxWidth, top));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
