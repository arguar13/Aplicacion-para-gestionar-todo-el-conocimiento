import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:sinapsis/core/design/widgets/snack_bar_footprint.dart';
import 'package:sinapsis/core/design/widgets/top_edge_probe.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que dura un aviso de abajo si no se dice otra cosa: lo mismo que
/// `SnackBar`.
const kSnackBarDefaultDuration = Duration(milliseconds: 4000);

/// Hasta cuántos renglones muestra el texto de un aviso de abajo (F45, paso
/// 1); lo que no entra termina en «…».
const kSnackBarMaxLines = 3;

/// El aviso de abajo de la app, el único (F45, paso 1): el texto a la
/// izquierda, hasta [kSnackBarMaxLines] renglones; uno o dos botones a la
/// derecha —«Ver», «Deshacer»—, y la ✕ siempre, también en una confirmación
/// corta como «Copiado» (decisión A), para que se pueda sacar en el acto.
///
/// Se acomoda como una tarjeta:
/// - si el texto entra en un renglón al lado de los botones y la ✕, va todo
///   en ese renglón;
/// - si no, el texto toma el ancho, la ✕ queda arriba a la derecha y los
///   botones bajan juntos a un renglón propio, alineados a la derecha. Nunca
///   queda un hueco en el medio, como dejaba el `SnackBar` de Material con
///   un botón largo.
///
/// Con un botón, el aviso se queda hasta que lo cierren (`persist`), salvo
/// que se pida lo contrario. Mientras se ve, publica lo que ocupa abajo
/// ([SnackBarFootprint]) para que lo que flota encima de las pantallas se
/// corra arriba (decisión C).
///
/// Se muestra con [AppSnackBarMessenger.showAppSnackBar], y así lo exige el
/// censo de los avisos (`test/core/design/snack_bar_census_test.dart`).
class AppSnackBar extends SnackBar {
  AppSnackBar({
    required Widget content,
    super.key,
    SnackBarAction? action,
    SnackBarAction? secondaryAction,
    super.duration = kSnackBarDefaultDuration,
    bool? persist,
    super.behavior,
    super.shape,
    super.margin,
    super.width,
    super.backgroundColor,
    super.onVisible,
    super.dismissDirection,
  }) : super(
         content: _NoticeBody(
           message: content,
           actions: [?secondaryAction, ?action],
         ),
         // Los márgenes de adentro, la ✕ y los botones los pone el aviso: los
         // de Material dejaban el hueco. Tampoco su ✕, aunque la pida el tema:
         // serían dos.
         padding: EdgeInsets.zero,
         showCloseIcon: false,
         persist: persist ?? (action != null || secondaryAction != null),
       );
}

/// La única puerta para mostrar un aviso de abajo (F45, paso 1): recibe un
/// [AppSnackBar], no cualquier `SnackBar`, así que un aviso armado a mano no
/// compila. Fuera de este archivo, `showSnackBar` no se usa: lo vigila el
/// censo de los avisos.
extension AppSnackBarMessenger on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
    AppSnackBar snackBar,
  ) => showSnackBar(snackBar);
}

/// Lo de adentro del aviso: el texto, los botones y la ✕, acomodados por
/// [_NoticeLayout], y la huella que publica mientras se ve.
class _NoticeBody extends StatefulWidget {
  const _NoticeBody({required this.message, required this.actions});

  final Widget message;

  /// En el orden en que se leen: el secundario primero —«Ver»— y el
  /// principal pegado a la ✕ —«Deshacer»—.
  final List<SnackBarAction> actions;

  @override
  State<_NoticeBody> createState() => _NoticeBodyState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Widget>('message', message));
  }
}

class _NoticeBodyState extends State<_NoticeBody> {
  /// La animación con que el `ScaffoldMessenger` muestra y saca el aviso.
  Animation<double> _shown = kAlwaysCompleteAnimation;

  /// [_shown] con la forma con que se mueve el aviso: ver
  /// [SnackBarFootprint.presence].
  CurvedAnimation? _presence;
  bool? _still;

  SnackBarFootprints? _footprints;
  var _visible = false;
  var _viewHeight = 0.0;
  double? _top;

  /// Mientras se va, el aviso ya no recibe toques: otro botón tocado a
  /// destiempo haría algo sobre un aviso que ya se cerró.
  var _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La del `SnackBar` que lo muestra: `ScaffoldMessenger` arma uno nuevo
    // con su animación (`withAnimation`), y ese es el que está arriba.
    final shown =
        context.findAncestorWidgetOfExactType<SnackBar>()?.animation ??
        kAlwaysCompleteAnimation;
    // Con el lector de pantalla, Material muestra el aviso sin animación; con
    // «sin animaciones», lo que se corre por él tampoco se anima.
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (!identical(shown, _shown) || still != _still) {
      _shown.removeStatusListener(_onStatus);
      _presence?.dispose();
      _shown = shown..addStatusListener(_onStatus);
      _still = still;
      _presence = CurvedAnimation(
        parent: shown,
        // Al llegar, sube como el aviso, que crece desde abajo con esta curva
        // (la de Material 3). Al irse, el aviso se desvanece en el medio de
        // su animación y su lugar se suelta al final: lo de encima espera a
        // que se desvanezca y baja.
        curve: still ? const Threshold(0) : Curves.easeInOutQuart,
        reverseCurve: still
            ? const Threshold(0)
            : const Interval(0, 0.6, curve: Curves.easeOutCubic),
      );
      _leaving = shown.status == AnimationStatus.reverse;
    }

    final footprints = SnackBarFootprintHost.maybeOf(context);
    if (!identical(footprints, _footprints)) {
      final previous = _footprints;
      if (previous != null) _afterFrame(() => previous.withdraw(this));
      _footprints = footprints;
    }
    // Una pantalla tapada por otra o una pestaña que no es la de ahora
    // dibujan el aviso fuera de la vista: no corren nada.
    _visible = TickerMode.valuesOf(context).enabled;
    _viewHeight = MediaQuery.sizeOf(context).height;
    _publish();
  }

  void _onStatus(AnimationStatus status) {
    final leaving = status == AnimationStatus.reverse;
    if (leaving != _leaving && mounted) setState(() => _leaving = leaving);
  }

  void _measured(double top) {
    _top = top;
    _publish();
  }

  /// Al final del cuadro, no en medio del dibujo ni de la construcción: lo
  /// que escucha las huellas se reconstruye.
  void _publish() => _afterFrame(() {
    if (!mounted) return;
    final footprints = _footprints;
    final top = _top;
    final presence = _presence;
    if (footprints == null) return;
    if (_visible && top != null && presence != null) {
      footprints.report(
        this,
        SnackBarFootprint(
          height: math.max(0, _viewHeight - top),
          presence: presence,
        ),
      );
    } else {
      footprints.withdraw(this);
    }
  });

  /// Al final de este cuadro, o del que sigue si este ya terminó: la sonda
  /// también mide al final del cuadro.
  void _afterFrame(VoidCallback callback) => SchedulerBinding.instance
    ..addPostFrameCallback((_) => callback())
    ..ensureVisualUpdate();

  @override
  void dispose() {
    _shown.removeStatusListener(_onStatus);
    final footprints = _footprints;
    final presence = _presence;
    // La huella se retira al final del cuadro, y recién entonces se suelta su
    // animación: hasta ahí, lo que se corrió la sigue leyendo.
    _afterFrame(() {
      footprints?.withdraw(this);
      presence?.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = widget.actions;
    return IgnorePointer(
      ignoring: _leaving,
      child: TopEdgeProbe(
        onTop: _measured,
        child: _NoticeLayout(
          textDirection: Directionality.of(context),
          message: DefaultTextStyle.merge(
            maxLines: kSnackBarMaxLines,
            overflow: TextOverflow.ellipsis,
            child: widget.message,
          ),
          actions: actions.isEmpty
              ? null
              : OverflowBar(
                  spacing: _NoticeLayout.actionsSpacing,
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: actions,
                ),
          // La ✕ de Material, con su color sobre el aviso en cada tema; el
          // nombre dice qué cierra, para no confundirse con la ✕ de una hoja
          // que esté abierta debajo.
          close: IconButton(
            key: StandardComponentType.closeButton.key,
            icon: const Icon(Icons.close),
            iconSize: 24,
            color:
                SnackBarTheme.of(context).closeIconColor ??
                theme.colorScheme.onInverseSurface,
            tooltip:
                AppLocalizations.of(context)?.f45S1CloseNotice ??
                MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss),
          ),
        ),
      ),
    );
  }
}

enum _NoticeSlot { message, actions, close }

/// Acomoda el texto, los botones y la ✕ del aviso: en un renglón si el texto
/// entra entero al lado de los botones y la ✕; si no, como una tarjeta, con
/// la ✕ arriba a la derecha y los botones abajo, juntos y a la derecha.
class _NoticeLayout
    extends SlottedMultiChildRenderObjectWidget<_NoticeSlot, RenderBox> {
  const _NoticeLayout({
    required this.textDirection,
    required this.message,
    required this.actions,
    required this.close,
  });

  /// Entre un botón y el otro: cada uno ya trae su aire adentro.
  static const actionsSpacing = 4.0;

  final TextDirection textDirection;
  final Widget message;
  final Widget? actions;
  final Widget close;

  @override
  Iterable<_NoticeSlot> get slots => _NoticeSlot.values;

  @override
  Widget? childForSlot(_NoticeSlot slot) => switch (slot) {
    _NoticeSlot.message => message,
    _NoticeSlot.actions => actions,
    _NoticeSlot.close => close,
  };

  @override
  _RenderNoticeLayout createRenderObject(BuildContext context) =>
      _RenderNoticeLayout(textDirection: textDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNoticeLayout renderObject,
  ) {
    renderObject.textDirection = textDirection;
  }
}

/// Dónde va cada parte del aviso, y su tamaño.
typedef _NoticeGeometry = ({
  Size size,
  Offset message,
  Offset? actions,
  Offset close,
});

class _RenderNoticeLayout extends RenderBox
    with SlottedContainerRenderObjectMixin<_NoticeSlot, RenderBox> {
  _RenderNoticeLayout({required TextDirection textDirection})
    : _textDirection = textDirection;

  /// Del borde al texto, como el `SnackBar` flotante de Material.
  static const _start = 16.0;

  /// Arriba y abajo del texto: con un renglón, el aviso mide 48, como el de
  /// Material.
  static const _textVertical = 14.0;

  /// Del borde a la ✕ y a los botones: cada uno ya trae su aire adentro.
  static const _end = 4.0;

  /// Entre el texto y los botones o la ✕, en un renglón.
  static const _gap = 8.0;

  /// Entre el texto y los botones que bajan, y debajo de ellos.
  static const _below = 4.0;

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _message => childForSlot(_NoticeSlot.message)!;
  RenderBox? get _actions => childForSlot(_NoticeSlot.actions);
  RenderBox get _close => childForSlot(_NoticeSlot.close)!;

  /// En el orden en que se dibujan. Mientras se arma, puede faltar alguno.
  @override
  Iterable<RenderBox> get children => [
    for (final slot in _NoticeSlot.values) ?childForSlot(slot),
  ];

  /// Lo que pide todo en un renglón, con el texto entero.
  double _inlineWidth() =>
      _start +
      _message.getMaxIntrinsicWidth(double.infinity) +
      _gap +
      (_actions?.getMaxIntrinsicWidth(double.infinity) ?? 0) +
      _close.getMaxIntrinsicWidth(double.infinity) +
      _end;

  _NoticeGeometry _compute(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
  ) {
    final message = _message;
    final actions = _actions;
    final closeSize = layoutChild(_close, const BoxConstraints());
    final inlineWidth = _inlineWidth();
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : inlineWidth;

    if (inlineWidth <= width) {
      // En un solo renglón: el texto se lleva lo que sobra, y los botones y
      // la ✕ quedan pegados a la derecha, centrados con él.
      final actionsSize = actions == null
          ? Size.zero
          : layoutChild(
              actions,
              BoxConstraints(
                maxWidth: actions.getMaxIntrinsicWidth(double.infinity),
              ),
            );
      final closeX = width - _end - closeSize.width;
      final actionsX = closeX - actionsSize.width;
      final messageSize = layoutChild(
        message,
        BoxConstraints(maxWidth: math.max(0, actionsX - _gap - _start)),
      );
      final height = constraints.constrainHeight(
        math.max(
          messageSize.height + 2 * _textVertical,
          math.max(closeSize.height, actionsSize.height),
        ),
      );
      double centered(Size size) => (height - size.height) / 2;
      return (
        size: Size(width, height),
        message: Offset(_start, centered(messageSize)),
        actions: actions == null
            ? null
            : Offset(actionsX, centered(actionsSize)),
        close: Offset(closeX, centered(closeSize)),
      );
    }

    // Como una tarjeta: el texto toma el ancho menos la ✕, que queda arriba a
    // la derecha, centrada con el primer renglón.
    final closeX = width - _end - closeSize.width;
    final messageSize = layoutChild(
      message,
      BoxConstraints(maxWidth: math.max(0, closeX - _start)),
    );
    final firstLine = math.min(
      messageSize.height,
      message.getMinIntrinsicHeight(
        message.getMaxIntrinsicWidth(double.infinity),
      ),
    );
    final closeY = math.max<double>(
      0,
      _textVertical + firstLine / 2 - closeSize.height / 2,
    );
    final messageBottom = _textVertical + messageSize.height;
    final closeBottom = closeY + closeSize.height;

    if (actions == null) {
      return (
        size: constraints.constrain(
          Size(width, math.max(messageBottom + _textVertical, closeBottom)),
        ),
        message: const Offset(_start, _textVertical),
        actions: null,
        close: Offset(closeX, closeY),
      );
    }

    // Los botones, juntos en su renglón, a la derecha, debajo del texto y de
    // la ✕. Si ni así entran, se apilan, también a la derecha.
    final actionsSize = layoutChild(
      actions,
      BoxConstraints(maxWidth: math.max(0, width - _start - _end)),
    );
    final actionsY = math.max(messageBottom + _below, closeBottom);
    return (
      size: constraints.constrain(
        Size(width, actionsY + actionsSize.height + _below),
      ),
      message: const Offset(_start, _textVertical),
      actions: Offset(width - _end - actionsSize.width, actionsY),
      close: Offset(closeX, closeY),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final actions = _actions;
    return math.max(
      _start +
          _message.getMinIntrinsicWidth(double.infinity) +
          _close.getMinIntrinsicWidth(double.infinity) +
          _end,
      actions == null
          ? 0
          : _start + actions.getMinIntrinsicWidth(double.infinity) + _end,
    );
  }

  @override
  double computeMaxIntrinsicWidth(double height) => _inlineWidth();

  @override
  double computeMinIntrinsicHeight(double width) => _compute(
    BoxConstraints.tightFor(width: width),
    ChildLayoutHelper.dryLayoutChild,
  ).size.height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _compute(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final message = _message;
    final distance = message.getDistanceToActualBaseline(baseline);
    if (distance == null) return null;
    return distance + (message.parentData! as BoxParentData).offset.dy;
  }

  @override
  void performLayout() {
    final geometry = _compute(constraints, ChildLayoutHelper.layoutChild);
    size = geometry.size;
    _place(_message, geometry.message);
    if (_actions case final actions?) _place(actions, geometry.actions!);
    _place(_close, geometry.close);
  }

  /// Pone a [child] en [offset], medido de izquierda a derecha; en un idioma
  /// que se escribe al revés, lo da vuelta.
  void _place(RenderBox child, Offset offset) {
    (child.parentData! as BoxParentData).offset = switch (textDirection) {
      TextDirection.ltr => offset,
      TextDirection.rtl => Offset(
        size.width - offset.dx - child.size.width,
        offset.dy,
      ),
    };
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(
        child,
        (child.parentData! as BoxParentData).offset + offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final hit = result.addWithPaintOffset(
        offset: (child.parentData! as BoxParentData).offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}
